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
use crate::sim::movement::MoveTo;
use crate::sim::needs::Needs;
use crate::sim::{AnimationState, SimId, SimTraits, Trait};
use crate::social::catalog::{SocialAction, actions_in_category};
use crate::social::{
    Conversation, ConversationContext, RelationshipData, Relationships, Sentiments,
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
        (Entity, &Transform, &Needs),
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
        .filter(|(_, _, needs)| needs.social < SOCIAL_GATE)
        .map(|(e, t, _)| (e, t.translation))
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
) {
    let speed = game_speed.multiplier();
    if speed == 0.0 {
        return;
    }
    let game_minutes = time.delta_seconds() * speed / game_config.real_seconds_per_game_minute;

    for (convo_entity, mut convo) in &mut convos {
        let [a, b] = match convo.participants.as_slice() {
            [a, b] => [*a, *b],
            _ => continue,
        };

        // End if a participant vanished or they have drifted apart.
        let apart = match (transforms.get(a), transforms.get(b)) {
            (Ok(ta), Ok(tb)) => ta.translation.distance(tb.translation) > BREAK_RANGE,
            _ => true,
        };
        let finished = convo.exchanges >= MAX_EXCHANGES || apart;

        if finished {
            for sim in [a, b] {
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

        // Hold both sims in the conversation: talking, no solo plan.
        for sim in [a, b] {
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

        // Resolve one exchange (a speaks to b), scaled by trait compatibility.
        let compatibility = match (traits.get(a), traits.get(b)) {
            (Ok(ta), Ok(tb)) => trait_compatibility(&ta.traits, &tb.traits),
            _ => 1.0,
        };
        let rel_snapshot = rels
            .get(a)
            .ok()
            .and_then(|r| r.get(b).cloned())
            .unwrap_or_default();
        let action = choose_action(convo.context, &rel_snapshot, convo.exchanges);
        let (df, dr) = exchange_delta(&action, compatibility);

        // Both sims feel the interaction (applied to each direction).
        if let Ok([mut ra, mut rb]) = rels.get_many_mut([a, b]) {
            ra.record(b, df, dr);
            rb.record(a, df, dr);
        }

        convo.exchanges += 1;
        convo.warmth += df;
        convo.romance += dr.max(0.0);
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
}
