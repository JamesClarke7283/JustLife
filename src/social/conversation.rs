//! Conversation system (Phase 8.4).
//!
//! Two sims standing close with room in their social need strike up a
//! conversation. Each exchange picks a social action (biased by the running
//! context), scales its effect by trait compatibility, and feeds the change
//! into both sims' directional relationships. Accumulated warmth/romance shift
//! the conversation between Friendly, Romantic and Tense contexts. A coloured
//! bubble floats over each speaker as a mood indicator.

use bevy::prelude::*;
use bevy::utils::HashSet;

use crate::core::components::RouteTo;
use crate::core::resources::{GameConfig, GameSpeed};
use crate::core::state::GameState;
use crate::interaction::InteractionCategory;
use crate::sim::desperation::Collapsed;
use crate::sim::interaction::InteractionQueue;
use crate::sim::moodlet::{ActiveMoodlets, Mood};
use crate::sim::movement::MoveTo;
use crate::sim::needs::Needs;
use crate::sim::{AnimationState, SimId, SimTraits, Trait};
use crate::social::catalog::{SocialAction, actions_in_category};
use crate::social::{
    Conversation, ConversationContext, RelationshipData, Relationships, Sentiment, Sentiments,
};

/// Sims within this distance (world units) can start a conversation.
const CONVERSATION_RANGE: f32 = 3.0;
/// Distance past which an in-progress conversation breaks up.
const BREAK_RANGE: f32 = 4.5;
/// In-game minutes between exchanges.
const EXCHANGE_INTERVAL: f32 = 4.0;
/// Exchanges after which the conversation wraps up.
const MAX_EXCHANGES: u32 = 6;
/// Only sims with social below this will start chatting.
const SOCIAL_GATE: f32 = 80.0;
/// Social need restored to each participant when a conversation ends well.
const SOCIAL_REWARD: f32 = 40.0;
/// Accumulated warmth above which a finished conversation leaves a Close bond.
const CLOSE_WARMTH: f32 = 25.0;
/// Maximum sims in one conversation group.
const MAX_GROUP: usize = 4;

/// Marks a sim currently in a conversation, pointing at the conversation entity.
#[derive(Component, Debug, Clone, Copy)]
pub struct InConversation {
    pub conversation: Entity,
    pub partner: Entity,
}

/// A floating mood bubble rendered over a conversing sim.
#[derive(Component)]
struct ConversationBubble;

/// Trait-compatibility multiplier (0.4..1.8): shared traits raise it, clashing
/// trait pairs (e.g. Cheerful/Gloomy, Good/Evil) lower it.
pub fn trait_compatibility(a: &[Trait], b: &[Trait]) -> f32 {
    let mut score = 1.0;
    for &ta in a {
        for &tb in b {
            score += pair_affinity(ta, tb);
        }
    }
    score.clamp(0.4, 1.8)
}

/// Per-pair affinity contribution: + for a shared trait, - for a clashing pair.
fn pair_affinity(a: Trait, b: Trait) -> f32 {
    use Trait::*;
    if a == b {
        return 0.15;
    }
    let clash = matches!(
        (a, b),
        (Cheerful, Gloomy)
            | (Gloomy, Cheerful)
            | (Outgoing, Introvert)
            | (Introvert, Outgoing)
            | (Good, Evil)
            | (Evil, Good)
            | (Neat, Slob)
            | (Slob, Neat)
            | (Active, Lazy)
            | (Lazy, Active)
            | (Romantic, Unflirty)
            | (Unflirty, Romantic)
    );
    if clash { -0.2 } else { 0.0 }
}

/// Derive the conversation context from accumulated warmth/romance.
pub fn derive_context(warmth: f32, romance: f32) -> ConversationContext {
    if warmth <= -10.0 {
        ConversationContext::Tense
    } else if romance >= 12.0 {
        ConversationContext::Romantic
    } else {
        ConversationContext::Friendly
    }
}

/// Pick the next social action for an exchange, biased by context and gated by
/// the current relationship. Falls back to a plain Chat when nothing else fits.
pub fn choose_action(
    context: ConversationContext,
    rel: &RelationshipData,
    exchange: u32,
) -> SocialAction {
    let category = match context {
        ConversationContext::Romantic => InteractionCategory::Romantic,
        ConversationContext::Tense | ConversationContext::Mean => InteractionCategory::Mean,
        ConversationContext::Funny => InteractionCategory::Funny,
        ConversationContext::Friendly => {
            if exchange % 3 == 2 {
                InteractionCategory::Funny
            } else {
                InteractionCategory::Friendly
            }
        }
    };
    let options: Vec<SocialAction> = actions_in_category(category)
        .into_iter()
        .filter(|a| a.is_available(rel))
        .collect();
    let chat = actions_in_category(InteractionCategory::Friendly)
        .into_iter()
        .find(|a| a.name == "Chat")
        .expect("Chat exists in the catalog");
    options
        .get(exchange as usize % options.len().max(1))
        .copied()
        .unwrap_or(chat)
}

/// Effective friendship/romance change for an exchange, scaled by compatibility.
pub fn exchange_delta(action: &SocialAction, compatibility: f32) -> (f32, f32) {
    (
        action.friendship * compatibility,
        action.romance * compatibility,
    )
}

/// How well social interactions land given a sim's dominant mood: happy sims
/// connect better, angry/embarrassed sims worse.
pub fn mood_multiplier(mood: Mood) -> f32 {
    match mood {
        Mood::Happy => 1.3,
        Mood::Flirty => 1.15,
        Mood::Energized => 1.1,
        Mood::Focused | Mood::Fine => 1.0,
        Mood::Sad => 0.85,
        Mood::Tense | Mood::Uncomfortable => 0.8,
        Mood::Angry => 0.7,
        Mood::Embarrassed => 0.6,
    }
}

/// A category a mood pushes a sim toward, overriding the conversation context:
/// angry sims argue, flirty sims romance, sad sims reach out for comfort.
pub fn mood_action_bias(mood: Mood) -> Option<InteractionCategory> {
    match mood {
        Mood::Angry => Some(InteractionCategory::Mean),
        Mood::Flirty => Some(InteractionCategory::Romantic),
        Mood::Sad => Some(InteractionCategory::Friendly),
        _ => None,
    }
}

/// Embarrassed sims withdraw from social contact entirely.
pub fn avoids_social(mood: Mood) -> bool {
    matches!(mood, Mood::Embarrassed)
}

/// Whether a sim may join an existing group: not withdrawn, and room to spare.
/// (Embarrassed/withdrawn sims are the exclusion mechanic - left out of groups.)
pub fn can_join(mood: Mood, group_size: usize) -> bool {
    !avoids_social(mood) && group_size < MAX_GROUP
}

/// The group activity cycled in for this exchange (3+ sims do these together).
pub fn group_activity_for(exchange: u32) -> &'static str {
    const ACTIVITIES: [&str; 3] = ["Tell Group Story", "Play Game", "Dance Together"];
    ACTIVITIES[(exchange as usize / 3) % ACTIVITIES.len()]
}

/// Pick the exchange action, letting the actor's mood override the context's
/// category bias (and steering a sad sim specifically toward being consoled).
pub fn pick_exchange_action(
    context: ConversationContext,
    mood: Mood,
    rel: &RelationshipData,
    exchange: u32,
) -> SocialAction {
    if let Some(category) = mood_action_bias(mood) {
        let options: Vec<SocialAction> = actions_in_category(category)
            .into_iter()
            .filter(|a| a.is_available(rel))
            .collect();
        if mood == Mood::Sad
            && let Some(console) = options.iter().find(|a| a.name == "Console")
        {
            return *console;
        }
        if !options.is_empty() {
            return options[exchange as usize % options.len()];
        }
    }
    choose_action(context, rel, exchange)
}

/// Themed colour for a conversation context (used for the mood bubble).
fn context_color(context: ConversationContext) -> Color {
    match context {
        ConversationContext::Friendly => Color::srgb(0.35, 0.78, 0.45),
        ConversationContext::Romantic => Color::srgb(0.90, 0.42, 0.60),
        ConversationContext::Tense => Color::srgb(0.80, 0.30, 0.28),
        ConversationContext::Funny => Color::srgb(0.96, 0.78, 0.30),
        ConversationContext::Mean => Color::srgb(0.55, 0.20, 0.22),
    }
}

/// Ensure every sim carries the social components conversations rely on.
fn ensure_social_components(
    mut commands: Commands,
    sims: Query<Entity, (With<SimId>, Without<Relationships>)>,
) {
    for entity in &sims {
        commands
            .entity(entity)
            .insert((Relationships::default(), Sentiments::default()));
    }
}

/// Start conversations between eligible sims standing close together.
#[allow(clippy::type_complexity)]
fn start_conversations(
    mut commands: Commands,
    sims: Query<
        (Entity, &Transform, &Needs, &ActiveMoodlets),
        (
            With<SimId>,
            Without<Collapsed>,
            Without<InConversation>,
            With<Relationships>,
        ),
    >,
) {
    let candidates: Vec<(Entity, Vec3)> = sims
        .iter()
        .filter(|(_, _, needs, moodlets)| {
            needs.social < SOCIAL_GATE && !avoids_social(moodlets.dominant_mood())
        })
        .map(|(e, t, _, _)| (e, t.translation))
        .collect();

    let mut paired: HashSet<Entity> = HashSet::new();
    for i in 0..candidates.len() {
        for j in (i + 1)..candidates.len() {
            let (a, pa) = candidates[i];
            let (b, pb) = candidates[j];
            if paired.contains(&a) || paired.contains(&b) {
                continue;
            }
            if pa.distance(pb) > CONVERSATION_RANGE {
                continue;
            }
            let convo = commands
                .spawn((
                    Conversation {
                        participants: vec![a, b],
                        context: ConversationContext::Friendly,
                        ..default()
                    },
                    Name::new("Conversation"),
                ))
                .id();
            for (sim, partner) in [(a, b), (b, a)] {
                commands
                    .entity(sim)
                    .insert(InConversation {
                        conversation: convo,
                        partner,
                    })
                    .remove::<RouteTo>()
                    .remove::<MoveTo>();
            }
            paired.insert(a);
            paired.insert(b);
        }
    }
}

/// Let eligible sims near an existing conversation join it, turning a chat into
/// a group. Withdrawn (embarrassed) sims and full groups are excluded.
#[allow(clippy::type_complexity)]
fn join_conversations(
    mut commands: Commands,
    mut convos: Query<(Entity, &mut Conversation)>,
    transforms: Query<&Transform>,
    joiners: Query<
        (Entity, &Transform, &Needs, &ActiveMoodlets),
        (
            With<SimId>,
            Without<Collapsed>,
            Without<InConversation>,
            With<Relationships>,
        ),
    >,
) {
    for (entity, transform, needs, moodlets) in &joiners {
        if needs.social >= SOCIAL_GATE || avoids_social(moodlets.dominant_mood()) {
            continue;
        }
        for (convo_entity, mut convo) in &mut convos {
            if !can_join(moodlets.dominant_mood(), convo.participants.len()) {
                continue;
            }
            let near = convo.participants.iter().any(|&p| {
                transforms.get(p).is_ok_and(|t| {
                    t.translation.distance(transform.translation) <= CONVERSATION_RANGE
                })
            });
            if near {
                let partner = convo.participants[0];
                convo.participants.push(entity);
                commands
                    .entity(entity)
                    .insert(InConversation {
                        conversation: convo_entity,
                        partner,
                    })
                    .remove::<RouteTo>()
                    .remove::<MoveTo>();
                break;
            }
        }
    }
}

/// Advance running conversations: hold participants in place, run exchanges on a
/// timer, update relationships and context, and wrap up after enough exchanges.
#[allow(clippy::too_many_arguments, clippy::type_complexity)]
fn run_conversations(
    mut commands: Commands,
    game_config: Res<GameConfig>,
    game_speed: Res<GameSpeed>,
    time: Res<Time>,
    mut convos: Query<(Entity, &mut Conversation)>,
    transforms: Query<&Transform>,
    traits: Query<&SimTraits>,
    mut rels: Query<&mut Relationships>,
    mut anims: Query<&mut AnimationState>,
    mut needs: Query<&mut Needs>,
    mut queues: Query<&mut InteractionQueue>,
    moodlets: Query<&ActiveMoodlets>,
    mut sentiments: Query<&mut Sentiments>,
) {
    let speed = game_speed.multiplier();
    if speed == 0.0 {
        return;
    }
    let game_minutes = time.delta_seconds() * speed / game_config.real_seconds_per_game_minute;

    for (convo_entity, mut convo) in &mut convos {
        // Drop anyone who vanished or strayed from the group's centroid.
        let alive: Vec<Entity> = convo
            .participants
            .iter()
            .copied()
            .filter(|&p| transforms.get(p).is_ok())
            .collect();
        let centroid = {
            let mut sum = Vec3::ZERO;
            let mut count = 0.0;
            for &p in &alive {
                if let Ok(t) = transforms.get(p) {
                    sum += t.translation;
                    count += 1.0;
                }
            }
            (count > 0.0).then(|| sum / count)
        };
        let present: Vec<Entity> = alive
            .iter()
            .copied()
            .filter(|&p| {
                transforms.get(p).is_ok_and(|t| {
                    centroid.is_none_or(|c| t.translation.distance(c) <= BREAK_RANGE)
                })
            })
            .collect();
        for &gone in &alive {
            if !present.contains(&gone) {
                if let Some(mut ent) = commands.get_entity(gone) {
                    ent.remove::<InConversation>();
                }
                if let Ok(mut anim) = anims.get_mut(gone) {
                    *anim = AnimationState::Idle;
                }
            }
        }
        convo.participants = present.clone();

        let n = present.len();
        let finished = convo.exchanges >= MAX_EXCHANGES || n < 2;

        if finished {
            // Every pair that stuck out a warm chat grows Close.
            if convo.warmth >= CLOSE_WARMTH && convo.exchanges >= 3 {
                for i in 0..n {
                    for j in (i + 1)..n {
                        if let Ok([mut si, mut sj]) =
                            sentiments.get_many_mut([present[i], present[j]])
                        {
                            si.add(Sentiment::close(present[j]));
                            sj.add(Sentiment::close(present[i]));
                        }
                    }
                }
            }
            for &sim in &present {
                if let Some(mut ent) = commands.get_entity(sim) {
                    ent.remove::<InConversation>();
                }
                if let Ok(mut anim) = anims.get_mut(sim) {
                    *anim = AnimationState::Idle;
                }
                if let Ok(mut need) = needs.get_mut(sim) {
                    need.modify(crate::sim::needs::NeedType::Social, SOCIAL_REWARD);
                }
            }
            commands.entity(convo_entity).despawn_recursive();
            continue;
        }

        // Hold every participant in the conversation: talking, no solo plan.
        for &sim in &present {
            if let Ok(mut anim) = anims.get_mut(sim) {
                *anim = AnimationState::Talking;
            }
            if let Ok(mut queue) = queues.get_mut(sim) {
                queue.clear();
            }
        }

        convo.timer += game_minutes;
        if convo.timer < EXCHANGE_INTERVAL {
            continue;
        }
        convo.timer = 0.0;

        // With three or more, the group periodically does an activity together.
        if n >= 3 && convo.exchanges % 3 == 2 {
            let _activity = group_activity_for(convo.exchanges);
            for &sim in &present {
                if let Ok(mut need) = needs.get_mut(sim) {
                    need.modify(crate::sim::needs::NeedType::Social, 6.0);
                    need.modify(crate::sim::needs::NeedType::Fun, 8.0);
                }
            }
            convo.exchanges += 1;
            convo.warmth += 6.0;
            convo.context = derive_context(convo.warmth, convo.romance);
            continue;
        }

        // One sim speaks; everyone else reacts (directed exchange to each).
        let speaker = present[convo.exchanges as usize % n];
        let mood = moodlets
            .get(speaker)
            .map(|m| m.dominant_mood())
            .unwrap_or(Mood::Fine);
        let mut warmth_sum = 0.0;
        let mut romance_sum = 0.0;
        let mut listeners = 0.0;
        for &listener in &present {
            if listener == speaker {
                continue;
            }
            let compatibility = match (traits.get(speaker), traits.get(listener)) {
                (Ok(ts), Ok(tl)) => trait_compatibility(&ts.traits, &tl.traits),
                _ => 1.0,
            };
            let rel_snapshot = rels
                .get(speaker)
                .ok()
                .and_then(|r| r.get(listener).cloned())
                .unwrap_or_default();
            let action = pick_exchange_action(convo.context, mood, &rel_snapshot, convo.exchanges);
            let (df, dr) = exchange_delta(&action, compatibility * mood_multiplier(mood));
            if let Ok([mut rs, mut rl]) = rels.get_many_mut([speaker, listener]) {
                rs.record(listener, df, dr);
                rl.record(speaker, df, dr);
            }
            match action.name {
                "Fight" => {
                    if let Ok([mut ss, mut sl]) = sentiments.get_many_mut([speaker, listener]) {
                        ss.add(Sentiment::furious(listener));
                        sl.add(Sentiment::furious(speaker));
                    }
                }
                "Console" => {
                    if let Ok(mut sl) = sentiments.get_mut(listener) {
                        sl.add(Sentiment::grateful(speaker));
                    }
                }
                _ => {}
            }
            let bias = sentiments
                .get(speaker)
                .map(|s| s.net_modifier(listener))
                .unwrap_or(0.0);
            warmth_sum += df + bias * 0.05;
            romance_sum += dr.max(0.0);
            listeners += 1.0;
        }
        if listeners > 0.0 {
            convo.warmth += warmth_sum / listeners;
            convo.romance += romance_sum / listeners;
        }
        convo.exchanges += 1;
        convo.context = derive_context(convo.warmth, convo.romance);
    }
}

/// Immediate-mode mood bubbles: one coloured sphere over each speaker.
fn render_conversation_bubbles(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut cache: Local<Option<BubbleAssets>>,
    bubbles: Query<Entity, With<ConversationBubble>>,
    convos: Query<&Conversation>,
    transforms: Query<&Transform, With<SimId>>,
) {
    for entity in &bubbles {
        commands.entity(entity).despawn_recursive();
    }

    let assets = cache.get_or_insert_with(|| BubbleAssets::new(&mut meshes, &mut materials));

    for convo in &convos {
        let material = assets.material(convo.context);
        for &participant in &convo.participants {
            if let Ok(transform) = transforms.get(participant) {
                commands.spawn((
                    PbrBundle {
                        mesh: assets.mesh.clone(),
                        material: material.clone(),
                        transform: Transform::from_translation(
                            transform.translation + Vec3::new(0.0, 2.4, 0.0),
                        ),
                        ..default()
                    },
                    ConversationBubble,
                    Name::new("Speech Bubble"),
                ));
            }
        }
    }
}

/// Cached bubble mesh + per-context materials (built once, reused each frame).
struct BubbleAssets {
    mesh: Handle<Mesh>,
    materials: Vec<(ConversationContext, Handle<StandardMaterial>)>,
}

impl BubbleAssets {
    fn new(meshes: &mut Assets<Mesh>, materials: &mut Assets<StandardMaterial>) -> Self {
        use ConversationContext::*;
        let mesh = meshes.add(Sphere::new(0.28));
        let materials = [Friendly, Romantic, Tense, Funny, Mean]
            .into_iter()
            .map(|context| {
                let handle = materials.add(StandardMaterial {
                    base_color: context_color(context),
                    unlit: true,
                    ..default()
                });
                (context, handle)
            })
            .collect();
        Self { mesh, materials }
    }

    fn material(&self, context: ConversationContext) -> Handle<StandardMaterial> {
        self.materials
            .iter()
            .find(|(c, _)| *c == context)
            .map(|(_, h)| h.clone())
            .unwrap_or_else(|| self.materials[0].1.clone())
    }
}

/// Registers the conversation systems (live mode only).
pub struct ConversationPlugin;

impl Plugin for ConversationPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<Conversation>().add_systems(
            Update,
            (
                ensure_social_components,
                start_conversations,
                join_conversations,
                run_conversations,
                render_conversation_bubbles,
            )
                .chain()
                .run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_traits_raise_compatibility_clashes_lower_it() {
        let base = trait_compatibility(&[Trait::Cheerful], &[Trait::Genius]);
        let shared = trait_compatibility(&[Trait::Cheerful], &[Trait::Cheerful]);
        let clash = trait_compatibility(&[Trait::Cheerful], &[Trait::Gloomy]);
        assert!(shared > base);
        assert!(clash < base);
    }

    #[test]
    fn context_follows_warmth_and_romance() {
        assert_eq!(derive_context(0.0, 0.0), ConversationContext::Friendly);
        assert_eq!(derive_context(-15.0, 0.0), ConversationContext::Tense);
        assert_eq!(derive_context(5.0, 20.0), ConversationContext::Romantic);
    }

    #[test]
    fn compatibility_scales_exchange_effect() {
        let action = SocialAction {
            name: "Chat",
            category: InteractionCategory::Friendly,
            friendship: 5.0,
            romance: 0.0,
            min_friendship: 0.0,
            min_romance: 0.0,
        };
        let (warm, _) = exchange_delta(&action, 1.5);
        assert_eq!(warm, 7.5);
        let (cold, _) = exchange_delta(&action, 0.5);
        assert_eq!(cold, 2.5);
    }

    #[test]
    fn friendly_context_picks_available_friendly_actions() {
        let rel = RelationshipData::default();
        let action = choose_action(ConversationContext::Friendly, &rel, 0);
        assert_eq!(action.category, InteractionCategory::Friendly);
    }

    #[test]
    fn romantic_context_falls_back_to_chat_when_locked() {
        // Strangers can't perform gated romantic actions, so it falls back.
        let rel = RelationshipData::default();
        let action = choose_action(ConversationContext::Romantic, &rel, 0);
        assert!(action.is_available(&rel));
    }

    #[test]
    fn mood_scales_outcome_and_embarrassment_withdraws() {
        assert!(mood_multiplier(Mood::Happy) > 1.0);
        assert!(mood_multiplier(Mood::Angry) < 1.0);
        assert!(avoids_social(Mood::Embarrassed));
        assert!(!avoids_social(Mood::Happy));
    }

    #[test]
    fn mood_overrides_action_category() {
        let rel = RelationshipData::default();
        // Angry sims argue regardless of a friendly context.
        let angry = pick_exchange_action(ConversationContext::Friendly, Mood::Angry, &rel, 0);
        assert_eq!(angry.category, InteractionCategory::Mean);
        // Sad sims reach for comfort (Console).
        let sad = pick_exchange_action(ConversationContext::Friendly, Mood::Sad, &rel, 0);
        assert_eq!(sad.name, "Console");
        // A neutral mood leaves the context's choice intact.
        let fine = pick_exchange_action(ConversationContext::Friendly, Mood::Fine, &rel, 0);
        assert_eq!(fine.category, InteractionCategory::Friendly);
    }

    #[test]
    fn group_join_respects_withdrawal_and_capacity() {
        // A happy sim can join a small group...
        assert!(can_join(Mood::Happy, 2));
        // ...but not a full one (exclusion by capacity).
        assert!(!can_join(Mood::Happy, MAX_GROUP));
        // Embarrassed sims are left out (exclusion by mood).
        assert!(!can_join(Mood::Embarrassed, 2));
    }

    #[test]
    fn group_activities_cycle() {
        // Activities advance every 3 exchanges and wrap around.
        let first = group_activity_for(2);
        let second = group_activity_for(5);
        assert_ne!(first, second);
        assert_eq!(group_activity_for(2), group_activity_for(0));
    }
}
