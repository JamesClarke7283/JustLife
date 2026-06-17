//! Need-based desperation behaviours (Phase 7.6).
//!
//! When a need bottoms out the sim stops behaving normally: it passes out from
//! exhaustion or hunger, has a bladder accident, or shows desperate social/fun
//! flavour moodlets. These layer on top of the autonomy decision engine, which
//! already escalates critical needs via `critical_need_override`.

use bevy::prelude::*;

use crate::core::components::RouteTo;
use crate::core::resources::{GameConfig, GameSpeed};
use crate::core::state::GameState;
use crate::sim::AnimationState;
use crate::sim::interaction::InteractionQueue;
use crate::sim::moodlet::{ActiveMoodlets, Mood, Moodlet};
use crate::sim::movement::MoveTo;
use crate::sim::needs::{NeedType, Needs};

/// At/below this value a sim collapses (passes out) from the offending need.
pub const COLLAPSE_THRESHOLD: f32 = 5.0;
/// A passed-out (exhausted) sim wakes once energy recovers to this level.
pub const WAKE_ENERGY: f32 = 35.0;
/// Bladder value at/below which the sim has an accident.
pub const ACCIDENT_THRESHOLD: f32 = 1.0;
/// At/below this a sim shows desperate social/fun flavour behaviour.
pub const DESPERATE_THRESHOLD: f32 = 10.0;
/// Energy regained per in-game minute while passed out from exhaustion.
pub const COLLAPSE_RECOVERY: f32 = 1.2;
/// How long (in-game minutes) a hunger faint lasts before the sim gets back up.
pub const FAINT_MINUTES: f32 = 60.0;
/// Hard cap (in-game minutes) an exhaustion collapse lasts, as a soft-lock guard.
pub const MAX_COLLAPSE_MINUTES: f32 = 480.0;

/// Marks a sim that has passed out and cannot act until it recovers.
#[derive(Component, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Collapsed {
    /// The need that caused the collapse.
    pub cause: NeedType,
    /// In-game minutes spent collapsed so far (drives the safety/faint timers).
    pub elapsed: f32,
}

/// The need (energy first, then hunger) that should make a sim collapse, if any.
pub fn collapse_cause(needs: &Needs) -> Option<NeedType> {
    if needs.energy <= COLLAPSE_THRESHOLD {
        Some(NeedType::Energy)
    } else if needs.hunger <= COLLAPSE_THRESHOLD {
        Some(NeedType::Hunger)
    } else {
        None
    }
}

/// Whether a passed-out sim should wake. Exhaustion ends when energy recovers
/// (or the safety cap is hit); a hunger faint is brief and ends on a short timer
/// (or once the sim is no longer critically hungry, e.g. it was fed).
pub fn should_wake(cause: NeedType, needs: &Needs, elapsed: f32) -> bool {
    match cause {
        NeedType::Energy => needs.energy >= WAKE_ENERGY || elapsed >= MAX_COLLAPSE_MINUTES,
        _ => needs.get(cause) > COLLAPSE_THRESHOLD || elapsed >= FAINT_MINUTES,
    }
}

/// Resolve a bladder accident: relief resets the bladder, hygiene tanks, and the
/// sim earns a mortifying embarrassed moodlet. Self-limiting because the reset
/// pushes the bladder back above the trigger.
fn bladder_accident_system(mut sims: Query<(&mut Needs, &mut ActiveMoodlets), Without<Collapsed>>) {
    for (mut needs, mut moodlets) in &mut sims {
        if needs.bladder <= ACCIDENT_THRESHOLD {
            needs.modify(NeedType::Bladder, 60.0);
            needs.modify(NeedType::Hygiene, -45.0);
            moodlets.add(Moodlet::new(
                "Had an Accident",
                "Wet themselves - mortifying.",
                Mood::Embarrassed,
                -40,
                600.0,
                "bladder_accident",
            ));
        }
    }
}

/// Drive collapse and recovery: passed-out sims stay down (recovering energy if
/// exhausted) until they wake; healthy sims collapse when a need bottoms out.
#[allow(clippy::type_complexity)]
fn collapse_system(
    mut commands: Commands,
    game_config: Res<GameConfig>,
    game_speed: Res<GameSpeed>,
    time: Res<Time>,
    mut sims: Query<(
        Entity,
        &mut Needs,
        &mut AnimationState,
        &mut ActiveMoodlets,
        &mut InteractionQueue,
        Option<&mut Collapsed>,
    )>,
) {
    let speed = game_speed.multiplier();
    if speed == 0.0 {
        return;
    }
    let game_minutes = time.delta_seconds() * speed / game_config.real_seconds_per_game_minute;

    for (entity, mut needs, mut anim, mut moodlets, mut queue, collapsed) in &mut sims {
        match collapsed {
            Some(mut state) => {
                if state.cause == NeedType::Energy {
                    needs.modify(NeedType::Energy, COLLAPSE_RECOVERY * game_minutes);
                }
                state.elapsed += game_minutes;
                if should_wake(state.cause, &needs, state.elapsed) {
                    commands.entity(entity).remove::<Collapsed>();
                    moodlets.moodlets.retain(|m| m.source != "collapse");
                    *anim = AnimationState::Idle;
                } else {
                    *anim = AnimationState::Sleeping;
                }
            }
            None => {
                if let Some(cause) = collapse_cause(&needs) {
                    // Drop everything in progress and slump where they stand.
                    queue.clear();
                    commands
                        .entity(entity)
                        .remove::<RouteTo>()
                        .remove::<MoveTo>();
                    *anim = AnimationState::Sleeping;
                    let (name, desc) = match cause {
                        NeedType::Energy => ("Passed Out", "Collapsed from total exhaustion."),
                        _ => ("Faint with Hunger", "Fainted from severe hunger."),
                    };
                    moodlets.add(Moodlet::new(
                        name,
                        desc,
                        Mood::Uncomfortable,
                        -50,
                        f32::MAX,
                        "collapse",
                    ));
                    commands.entity(entity).insert(Collapsed {
                        cause,
                        elapsed: 0.0,
                    });
                }
            }
        }
    }
}

/// Desperate social/fun flavour: lonely sims mutter to themselves and bored sims
/// go stir crazy. The real fix (route to a phone/TV) is the autonomy engine's
/// job; these are short, self-expiring mood penalties.
fn desperation_flavour_system(mut sims: Query<(&Needs, &mut ActiveMoodlets), Without<Collapsed>>) {
    for (needs, mut moodlets) in &mut sims {
        if needs.social <= DESPERATE_THRESHOLD {
            moodlets.add(Moodlet::new(
                "Talking to Self",
                "So lonely they've started talking to themselves.",
                Mood::Sad,
                -15,
                240.0,
                "desperation",
            ));
        }
        if needs.fun <= DESPERATE_THRESHOLD {
            moodlets.add(Moodlet::new(
                "Stir Crazy",
                "Desperate for anything fun to do.",
                Mood::Tense,
                -15,
                240.0,
                "desperation",
            ));
        }
    }
}

/// Registers the desperation behaviours (runs in live mode).
pub struct DesperationPlugin;

impl Plugin for DesperationPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<Collapsed>().add_systems(
            Update,
            (
                bladder_accident_system,
                collapse_system,
                desperation_flavour_system,
            )
                .run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn full_needs() -> Needs {
        Needs::new()
    }

    #[test]
    fn collapses_on_empty_energy_then_hunger() {
        let mut needs = full_needs();
        assert_eq!(collapse_cause(&needs), None);

        needs.energy = 4.0;
        assert_eq!(collapse_cause(&needs), Some(NeedType::Energy));

        // Energy ok but hunger empty -> hunger collapse.
        needs.energy = 50.0;
        needs.hunger = 3.0;
        assert_eq!(collapse_cause(&needs), Some(NeedType::Hunger));

        // Both empty -> energy takes priority.
        needs.energy = 2.0;
        assert_eq!(collapse_cause(&needs), Some(NeedType::Energy));
    }

    #[test]
    fn exhaustion_wakes_on_energy_or_safety_cap() {
        let mut needs = full_needs();
        needs.energy = 40.0;
        assert!(should_wake(NeedType::Energy, &needs, 0.0));

        needs.energy = 20.0;
        assert!(!should_wake(NeedType::Energy, &needs, 10.0));
        // Safety cap forces a wake even if still low.
        assert!(should_wake(NeedType::Energy, &needs, MAX_COLLAPSE_MINUTES));
    }

    #[test]
    fn hunger_faint_is_brief() {
        let mut needs = full_needs();
        needs.hunger = 3.0;
        // Still hungry and only just fainted -> stay down.
        assert!(!should_wake(NeedType::Hunger, &needs, 5.0));
        // Short timer elapsed -> get back up.
        assert!(should_wake(NeedType::Hunger, &needs, FAINT_MINUTES));
        // Fed back above critical -> wake immediately.
        needs.hunger = 30.0;
        assert!(should_wake(NeedType::Hunger, &needs, 0.0));
    }
}
