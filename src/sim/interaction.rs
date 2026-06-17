use std::collections::VecDeque;

use bevy::prelude::*;

use crate::core::state::GameState;
use crate::sim::needs::{NeedType, Needs};

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
            critical_need_override.run_if(in_state(GameState::LiveMode)),
        );
    }
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
}
