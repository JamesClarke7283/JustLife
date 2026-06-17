use std::collections::VecDeque;

use bevy::prelude::*;

use crate::core::components::RouteTo;
use crate::core::resources::GameSpeed;
use crate::core::state::GameState;
use crate::sim::AnimationState;
use crate::sim::moodlet::{ActiveMoodlets, Mood, Moodlet};
use crate::sim::needs::{NeedType, Needs};
use crate::world::catalog::ObjectAction;

/// Where a queued interaction came from. Player commands take precedence over
/// autonomy and are never silently dropped.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InteractionSource {
    #[default]
    Autonomy,
    Player,
}

/// An interaction a sim intends to perform on a target object.
#[derive(Debug, Clone, PartialEq)]
pub struct QueuedInteraction {
    pub target: Entity,
    pub action: String,
    pub need: NeedType,
    pub rate: f32,
    pub source: InteractionSource,
}

/// Ordered FIFO of interactions a sim plans to perform. The front is the one
/// currently being routed-to / executed.
#[derive(Component, Default)]
pub struct InteractionQueue {
    items: VecDeque<QueuedInteraction>,
}

impl InteractionQueue {
    /// Add to the back of the queue.
    pub fn enqueue(&mut self, interaction: QueuedInteraction) {
        self.items.push_back(interaction);
    }

    /// Insert at the front (used for urgent / critical-need interactions).
    pub fn enqueue_urgent(&mut self, interaction: QueuedInteraction) {
        self.items.push_front(interaction);
    }

    /// The interaction currently being performed (front of the queue).
    pub fn current(&self) -> Option<&QueuedInteraction> {
        self.items.front()
    }

    /// Finish the current interaction and move to the next.
    pub fn advance(&mut self) -> Option<QueuedInteraction> {
        self.items.pop_front()
    }

    /// Cancel everything.
    pub fn clear(&mut self) {
        self.items.clear();
    }

    /// Drop only autonomy-queued interactions (player commands survive).
    pub fn clear_autonomy(&mut self) {
        self.items.retain(|i| i.source == InteractionSource::Player);
    }

    /// A new player command supersedes the autonomy plan and runs next.
    pub fn queue_player_command(&mut self, mut interaction: QueuedInteraction) {
        interaction.source = InteractionSource::Player;
        self.clear_autonomy();
        self.items.push_front(interaction);
    }

    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }
}

/// The most critical need (lowest value below the critical threshold), if any.
pub fn critical_need(needs: &Needs) -> Option<NeedType> {
    const CRITICAL: f32 = 20.0;
    [
        (NeedType::Hunger, needs.hunger),
        (NeedType::Energy, needs.energy),
        (NeedType::Social, needs.social),
        (NeedType::Fun, needs.fun),
        (NeedType::Hygiene, needs.hygiene),
        (NeedType::Bladder, needs.bladder),
    ]
    .into_iter()
    .filter(|(_, v)| *v < CRITICAL)
    .min_by(|a, b| a.1.total_cmp(&b.1))
    .map(|(need, _)| need)
}

/// If a sim has a critical need that its current (autonomy) plan isn't
/// addressing, drop the autonomy plan so the decision engine re-picks the
/// now-most-urgent need next tick.
fn critical_need_override(mut sims: Query<(&Needs, &mut InteractionQueue)>) {
    for (needs, mut queue) in &mut sims {
        let Some(crit) = critical_need(needs) else {
            continue;
        };
        let addressing = queue.current().is_some_and(|c| c.need == crit);
        let player_driven = queue
            .current()
            .is_some_and(|c| c.source == InteractionSource::Player);
        if !addressing && !player_driven {
            queue.clear_autonomy();
        }
    }
}

/// Wires the interaction-queue maintenance systems.
pub struct InteractionQueuePlugin;

impl Plugin for InteractionQueuePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            Update,
            (
                critical_need_override,
                start_interaction,
                execute_interaction,
            )
                .run_if(in_state(GameState::LiveMode)),
        );
    }
}

/// A need change an interaction applies over its duration (points per minute).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NeedEffect {
    pub need: NeedType,
    pub per_minute: f32,
}

/// Whether an interaction acts on an object or another sim.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InteractionKind {
    Object,
    Social,
}

/// A fully specified interaction (object use or social), ready to execute.
#[derive(Debug, Clone, PartialEq)]
pub struct Interaction {
    pub name: String,
    pub kind: InteractionKind,
    /// In-game minutes to perform.
    pub duration: f32,
    pub effects: Vec<NeedEffect>,
    pub animation: AnimationState,
    /// Moodlet awarded on completion, if any.
    pub moodlet: Option<&'static str>,
}

/// Default animation for an object interaction serving a given need.
pub fn animation_for_need(need: NeedType) -> AnimationState {
    match need {
        NeedType::Hunger => AnimationState::Eating,
        NeedType::Energy => AnimationState::Sleeping,
        NeedType::Fun => AnimationState::Playing,
        NeedType::Social => AnimationState::Talking,
        NeedType::Hygiene | NeedType::Bladder => AnimationState::UsingObject,
    }
}

/// Build a single-need object interaction from raw parts. The duration is chosen
/// so it restores roughly 40 need points at the given rate.
pub fn interaction_from_parts(name: String, need: NeedType, rate: f32) -> Interaction {
    let duration = (40.0 / rate.max(0.1)).clamp(10.0, 120.0);
    Interaction {
        name,
        kind: InteractionKind::Object,
        duration,
        effects: vec![NeedEffect {
            need,
            per_minute: rate,
        }],
        animation: animation_for_need(need),
        moodlet: None,
    }
}

/// Build an object interaction from a catalog [`ObjectAction`].
pub fn object_interaction(action: &ObjectAction) -> Interaction {
    interaction_from_parts(action.name.clone(), action.need, action.rate)
}

/// A currently-executing interaction on a sim.
#[derive(Component, Debug, Clone)]
pub struct ActiveInteraction {
    pub interaction: Interaction,
    /// In-game minutes elapsed so far.
    pub elapsed: f32,
}

/// Advance an active interaction by `dt` in-game minutes, applying its need
/// effects. Returns true once the interaction has completed.
pub fn tick_interaction(active: &mut ActiveInteraction, needs: &mut Needs, dt: f32) -> bool {
    active.elapsed += dt;
    for effect in &active.interaction.effects {
        needs.modify(effect.need, effect.per_minute * dt);
    }
    active.elapsed >= active.interaction.duration
}

/// Map a completion-moodlet name to a mood and impact.
fn mood_for(name: &str) -> (Mood, i32) {
    match name {
        "Angry" => (Mood::Angry, -8),
        "Flirty" => (Mood::Flirty, 6),
        _ => (Mood::Happy, 8),
    }
}

/// Begin the queued interaction for sims that have arrived (no `RouteTo`) and
/// aren't already mid-interaction.
#[allow(clippy::type_complexity)]
fn start_interaction(
    mut commands: Commands,
    mut sims: Query<
        (Entity, &InteractionQueue, &mut AnimationState),
        (Without<ActiveInteraction>, Without<RouteTo>),
    >,
) {
    for (entity, queue, mut anim) in &mut sims {
        if let Some(qi) = queue.current() {
            let interaction = interaction_from_parts(qi.action.clone(), qi.need, qi.rate);
            *anim = interaction.animation;
            commands.entity(entity).insert(ActiveInteraction {
                interaction,
                elapsed: 0.0,
            });
        }
    }
}

/// Progress active interactions; apply effects and, on completion, award the
/// moodlet, advance the queue, and return the sim to idle.
#[allow(clippy::type_complexity)]
fn execute_interaction(
    time: Res<Time>,
    game_speed: Res<GameSpeed>,
    mut commands: Commands,
    mut sims: Query<(
        Entity,
        &mut Needs,
        &mut AnimationState,
        &mut ActiveInteraction,
        &mut ActiveMoodlets,
        &mut InteractionQueue,
    )>,
) {
    let speed = game_speed.multiplier();
    if speed == 0.0 {
        return;
    }
    let dt = time.delta_seconds() * speed; // in-game minutes
    for (entity, mut needs, mut anim, mut active, mut moodlets, mut queue) in &mut sims {
        if tick_interaction(&mut active, &mut needs, dt) {
            if let Some(moodlet_name) = active.interaction.moodlet {
                let (mood, impact) = mood_for(moodlet_name);
                moodlets.add(Moodlet::new(
                    moodlet_name,
                    moodlet_name,
                    mood,
                    impact,
                    300.0,
                    &active.interaction.name,
                ));
            }
            queue.advance();
            commands.entity(entity).remove::<ActiveInteraction>();
            *anim = AnimationState::Idle;
        }
    }
}

/// The multi-sim social interactions available between two nearby sims.
pub fn social_interactions() -> Vec<Interaction> {
    let social = |name: &str, dur: f32, effects: &[(NeedType, f32)], moodlet| Interaction {
        name: name.to_string(),
        kind: InteractionKind::Social,
        duration: dur,
        effects: effects
            .iter()
            .map(|(n, r)| NeedEffect {
                need: *n,
                per_minute: *r,
            })
            .collect(),
        animation: AnimationState::Socializing,
        moodlet,
    };
    vec![
        social("Chat", 20.0, &[(NeedType::Social, 4.0)], None),
        social(
            "Joke",
            15.0,
            &[(NeedType::Social, 3.0), (NeedType::Fun, 3.0)],
            Some("Amused"),
        ),
        social("Hug", 10.0, &[(NeedType::Social, 6.0)], Some("Warm Fuzzy")),
        social(
            "Flirt",
            15.0,
            &[(NeedType::Social, 4.0), (NeedType::Fun, 2.0)],
            Some("Flirty"),
        ),
        social("Fight", 12.0, &[(NeedType::Fun, -2.0)], Some("Angry")),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(need: NeedType, source: InteractionSource) -> QueuedInteraction {
        QueuedInteraction {
            target: Entity::from_raw(1),
            action: "Test".into(),
            need,
            rate: 5.0,
            source,
        }
    }

    #[test]
    fn fifo_order_and_advance() {
        let mut q = InteractionQueue::default();
        assert!(q.is_empty());
        q.enqueue(sample(NeedType::Hunger, InteractionSource::Autonomy));
        q.enqueue(sample(NeedType::Energy, InteractionSource::Autonomy));
        assert_eq!(q.len(), 2);
        assert_eq!(q.current().unwrap().need, NeedType::Hunger);
        q.advance();
        assert_eq!(q.current().unwrap().need, NeedType::Energy);
    }

    #[test]
    fn urgent_jumps_to_front() {
        let mut q = InteractionQueue::default();
        q.enqueue(sample(NeedType::Fun, InteractionSource::Autonomy));
        q.enqueue_urgent(sample(NeedType::Bladder, InteractionSource::Autonomy));
        assert_eq!(q.current().unwrap().need, NeedType::Bladder);
    }

    #[test]
    fn player_command_supersedes_autonomy() {
        let mut q = InteractionQueue::default();
        q.enqueue(sample(NeedType::Fun, InteractionSource::Autonomy));
        q.enqueue(sample(NeedType::Energy, InteractionSource::Autonomy));
        q.queue_player_command(sample(NeedType::Social, InteractionSource::Autonomy));
        // Autonomy items dropped; the player command is current.
        assert_eq!(q.len(), 1);
        let cur = q.current().unwrap();
        assert_eq!(cur.need, NeedType::Social);
        assert_eq!(cur.source, InteractionSource::Player);
    }

    #[test]
    fn critical_need_detected() {
        let mut needs = Needs::new();
        assert_eq!(critical_need(&needs), None);
        needs.bladder = 10.0;
        needs.hunger = 5.0;
        // Hunger is lower, so it's the most critical.
        assert_eq!(critical_need(&needs), Some(NeedType::Hunger));
    }

    #[test]
    fn object_interaction_from_action() {
        let action = ObjectAction {
            name: "Sleep".into(),
            need: NeedType::Energy,
            rate: 12.0,
        };
        let i = object_interaction(&action);
        assert_eq!(i.kind, InteractionKind::Object);
        assert_eq!(i.animation, AnimationState::Sleeping);
        assert_eq!(i.effects.len(), 1);
        assert_eq!(i.effects[0].need, NeedType::Energy);
        assert!(i.duration > 0.0);
    }

    #[test]
    fn social_table_populated_and_social_kind() {
        let socials = social_interactions();
        assert!(socials.iter().any(|s| s.name == "Hug"));
        assert!(socials.iter().all(|s| s.kind == InteractionKind::Social));
    }

    #[test]
    fn interaction_applies_effects_and_completes() {
        let interaction = interaction_from_parts("Sleep".into(), NeedType::Energy, 12.0);
        let duration = interaction.duration;
        let mut active = ActiveInteraction {
            interaction,
            elapsed: 0.0,
        };
        let mut needs = Needs {
            energy: 30.0,
            ..Needs::new()
        };
        // Halfway: not finished, but energy has risen.
        assert!(!tick_interaction(&mut active, &mut needs, duration / 2.0));
        assert!(needs.energy > 30.0);
        // Finishing tick completes it; needs stay clamped to 100.
        assert!(tick_interaction(
            &mut active,
            &mut needs,
            duration / 2.0 + 0.1
        ));
        assert!(needs.energy <= 100.0);
    }
}
