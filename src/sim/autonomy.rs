use bevy::prelude::*;

use crate::core::state::GameState;
use crate::sim::needs::{NeedType, Needs};
use crate::sim::{AnimationState, SimTraits, Trait};
use crate::world::PlacedObject;
use crate::world::catalog::CatalogDatabase;

/// An interaction a sim intends to perform on a target object.
#[derive(Debug, Clone, PartialEq)]
pub struct QueuedInteraction {
    pub target: Entity,
    pub action: String,
    pub need: NeedType,
    pub rate: f32,
}

/// Ordered list of interactions a sim plans to perform (autonomy or player).
#[derive(Component, Default)]
pub struct InteractionQueue {
    pub items: Vec<QueuedInteraction>,
}

/// Needs in the canonical order used by the weight array.
const NEED_ORDER: [NeedType; 6] = [
    NeedType::Hunger,
    NeedType::Energy,
    NeedType::Social,
    NeedType::Fun,
    NeedType::Hygiene,
    NeedType::Bladder,
];

/// Need priority: emptier needs are more urgent; the trait weight scales it.
pub fn need_priority(value: f32, weight: f32) -> f32 {
    (100.0 - value).max(0.0) * weight
}

/// Per-need autonomy weights derived from a sim's traits (in `NEED_ORDER`).
pub fn need_weights(traits: &[Trait]) -> [f32; 6] {
    let mut w = [1.0f32; 6];
    for t in traits {
        match t {
            Trait::Foodie | Trait::Glutton => w[0] *= 1.5,
            Trait::Lazy => w[1] *= 1.3,
            Trait::Active => w[3] *= 1.2,
            Trait::Outgoing | Trait::SocialButterfly => w[2] *= 1.4,
            Trait::Loner | Trait::Introvert => w[2] *= 0.6,
            Trait::Neat => w[4] *= 1.4,
            Trait::Slob => w[4] *= 0.6,
            _ => {}
        }
    }
    w
}

/// Pick the most urgent need, returning it with its priority value.
pub fn pick_top_need(needs: &Needs, weights: &[f32; 6]) -> (NeedType, f32) {
    let mut best = (NeedType::Hunger, f32::MIN);
    for (i, need) in NEED_ORDER.iter().enumerate() {
        let priority = need_priority(needs.get(*need), weights[i]);
        if priority > best.1 {
            best = (*need, priority);
        }
    }
    best
}

/// Score an interaction candidate: effectiveness * proximity * trait modifier.
pub fn score_candidate(rate: f32, distance: f32, trait_mod: f32) -> f32 {
    let proximity = 1.0 / (1.0 + distance.max(0.0));
    rate * proximity * trait_mod
}

/// The decision engine: each idle sim with an empty queue evaluates its needs,
/// finds the best object satisfying its most urgent need, and queues it.
fn autonomy_system(
    catalog: Res<CatalogDatabase>,
    objects: Query<(Entity, &PlacedObject, &Transform)>,
    mut sims: Query<(
        &Needs,
        &SimTraits,
        &AnimationState,
        &Transform,
        &mut InteractionQueue,
    )>,
) {
    for (needs, traits, anim, sim_tf, mut queue) in &mut sims {
        if *anim != AnimationState::Idle || !queue.items.is_empty() {
            continue;
        }
        let weights = need_weights(&traits.traits);
        let (top, priority) = pick_top_need(needs, &weights);
        // Don't act on nearly-satisfied needs.
        if priority < 15.0 {
            continue;
        }

        let sim_pos = sim_tf.translation;
        let mut best: Option<(Entity, String, f32, f32)> = None;
        for (entity, obj, obj_tf) in &objects {
            let Some(item) = catalog.get(&obj.catalog_id) else {
                continue;
            };
            for action in &item.actions {
                if action.need != top {
                    continue;
                }
                let score = score_candidate(action.rate, sim_pos.distance(obj_tf.translation), 1.0);
                if best.as_ref().is_none_or(|(_, _, _, bs)| score > *bs) {
                    best = Some((entity, action.name.clone(), action.rate, score));
                }
            }
        }

        if let Some((target, action, rate, _)) = best {
            queue.items.push(QueuedInteraction {
                target,
                action,
                need: top,
                rate,
            });
        }
    }
}

/// Registers the autonomy decision engine (runs in live mode).
pub struct AutonomyPlugin;

impl Plugin for AutonomyPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            Update,
            autonomy_system.run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn priority_grows_as_need_empties() {
        assert_eq!(need_priority(100.0, 1.0), 0.0);
        assert_eq!(need_priority(40.0, 1.0), 60.0);
        assert_eq!(need_priority(40.0, 1.5), 90.0);
        // Never negative even if value overshoots.
        assert_eq!(need_priority(120.0, 1.0), 0.0);
    }

    #[test]
    fn picks_the_emptiest_need() {
        let needs = Needs {
            hunger: 80.0,
            energy: 20.0,
            social: 90.0,
            fun: 60.0,
            hygiene: 95.0,
            bladder: 70.0,
        };
        let (need, _) = pick_top_need(&needs, &[1.0; 6]);
        assert_eq!(need, NeedType::Energy);
    }

    #[test]
    fn trait_weight_can_flip_priority() {
        let needs = Needs {
            hunger: 60.0, // priority 40 base
            energy: 55.0, // priority 45 base -> would win without traits
            social: 100.0,
            fun: 100.0,
            hygiene: 100.0,
            bladder: 100.0,
        };
        // A glutton weights hunger 1.5x -> 40*1.5 = 60 > 45.
        let weights = need_weights(&[Trait::Glutton]);
        let (need, _) = pick_top_need(&needs, &weights);
        assert_eq!(need, NeedType::Hunger);
    }

    #[test]
    fn closer_and_stronger_scores_higher() {
        // Same rate, closer wins.
        assert!(score_candidate(10.0, 1.0, 1.0) > score_candidate(10.0, 5.0, 1.0));
        // Same distance, higher rate wins.
        assert!(score_candidate(20.0, 2.0, 1.0) > score_candidate(10.0, 2.0, 1.0));
    }
}
