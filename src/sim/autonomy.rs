use bevy::prelude::*;

use crate::core::resources::GameTime;
use crate::core::state::GameState;
use crate::sim::interaction::{InteractionQueue, InteractionSource, QueuedInteraction};
use crate::sim::needs::{NeedType, Needs};
use crate::sim::{AnimationState, SimTraits, Trait};
use crate::world::PlacedObject;
use crate::world::catalog::CatalogDatabase;

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

/// Time-of-day need multipliers (in `NEED_ORDER`) that bias an approximate
/// daily routine: sleep at night, meals morning/midday/evening, hygiene after
/// waking, and winding down with fun/social in the evening.
pub fn schedule_multipliers(hour: u32) -> [f32; 6] {
    // [hunger, energy, social, fun, hygiene, bladder]
    let mut m = [1.0f32; 6];
    match hour {
        // Night: strongly prefer sleep; little interest in fun/social.
        22..=23 | 0..=5 => {
            m[1] = 2.0; // energy
            m[2] = 0.6; // social
            m[3] = 0.5; // fun
        }
        // Early morning: breakfast and freshening up.
        6..=9 => {
            m[0] = 1.4; // hunger
            m[4] = 1.3; // hygiene
        }
        // Midday: lunch.
        11..=13 => {
            m[0] = 1.4; // hunger
        }
        // Evening: dinner, then unwind with fun and company.
        17..=20 => {
            m[0] = 1.3; // hunger
            m[2] = 1.2; // social
            m[3] = 1.3; // fun
        }
        _ => {}
    }
    m
}

/// Full autonomy weights for the current hour: trait weights modulated by the
/// daily schedule, plus trait-driven routine bias (e.g. Active sims seek
/// exercise/fun during the day).
pub fn routine_weights(hour: u32, traits: &[Trait]) -> [f32; 6] {
    let mut w = need_weights(traits);
    let schedule = schedule_multipliers(hour);
    for (weight, mult) in w.iter_mut().zip(schedule) {
        *weight *= mult;
    }
    if traits.contains(&Trait::Active) && (8..20).contains(&hour) {
        w[3] *= 1.3; // daytime exercise/fun
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
    time: Res<GameTime>,
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
        if *anim != AnimationState::Idle || !queue.is_empty() {
            continue;
        }
        let weights = routine_weights(time.hour, &traits.traits);
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
            queue.enqueue(QueuedInteraction {
                target,
                action,
                need: top,
                rate,
                source: InteractionSource::Autonomy,
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

    #[test]
    fn schedule_prefers_sleep_at_night_and_meals_in_morning() {
        let night = schedule_multipliers(2);
        assert_eq!(night[1], 2.0); // energy boosted
        assert!(night[3] < 1.0); // fun suppressed

        let morning = schedule_multipliers(7);
        assert_eq!(morning[0], 1.4); // hunger boosted
        assert!(morning[4] > 1.0); // hygiene boosted

        // Mid-afternoon is a neutral routine window.
        assert_eq!(schedule_multipliers(15), [1.0; 6]);
    }

    #[test]
    fn night_routine_flips_a_tie_toward_sleep() {
        // Fun is slightly more depleted than energy. In the afternoon fun wins;
        // at night the sleep boost flips the choice to energy.
        let needs = Needs {
            hunger: 100.0,
            energy: 50.0,
            social: 100.0,
            fun: 45.0,
            hygiene: 100.0,
            bladder: 100.0,
        };
        let (day_need, _) = pick_top_need(&needs, &routine_weights(15, &[]));
        assert_eq!(day_need, NeedType::Fun);
        let (night_need, _) = pick_top_need(&needs, &routine_weights(2, &[]));
        assert_eq!(night_need, NeedType::Energy);
    }

    #[test]
    fn active_trait_boosts_daytime_fun() {
        let with = routine_weights(12, &[Trait::Active]);
        let without = routine_weights(12, &[]);
        assert!(with[3] > without[3]);
    }
}
