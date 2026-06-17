//! Sim death system (Phase 7.7).
//!
//! Starvation is the first fatal cause: a sim whose hunger sits at zero past a
//! grace period dies, leaving a tombstone on the lot. Surviving household
//! members react with a long grief moodlet. (Energy never kills directly - that
//! only triggers a collapse in [`crate::sim::desperation`].)

use bevy::prelude::*;

use crate::core::events::{DeathCause, SimDeathEvent};
use crate::core::resources::{GameConfig, GameSpeed};
use crate::core::state::GameState;
use crate::sim::SimManager;
use crate::sim::moodlet::{ActiveMoodlets, Mood, Moodlet};
use crate::sim::needs::Needs;

/// Hunger at/below which starvation accrues toward death.
pub const DEATH_HUNGER: f32 = 1.0;
/// In-game minutes a sim can sit at zero hunger before dying (~half a day).
pub const STARVATION_GRACE_MINUTES: f32 = 720.0;

/// Tracks how long a sim has been critically starving.
#[derive(Component, Debug, Clone, Copy, PartialEq, Default, Reflect)]
#[reflect(Component)]
pub struct Starving {
    /// Accumulated in-game minutes spent at/below [`DEATH_HUNGER`].
    pub elapsed: f32,
}

/// Marks the tombstone left behind when a sim dies.
#[derive(Component, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Tombstone;

/// Whether accumulated starvation time has reached the fatal threshold.
pub fn is_fatal(elapsed: f32) -> bool {
    elapsed >= STARVATION_GRACE_MINUTES
}

/// Advance a sim's starvation timer for this tick. Returns the new accumulated
/// time while starving, or `None` once the sim is no longer critically hungry
/// (signalling the timer should be cleared).
pub fn next_starvation(hunger: f32, elapsed: f32, game_minutes: f32) -> Option<f32> {
    if hunger <= DEATH_HUNGER {
        Some(elapsed + game_minutes)
    } else {
        None
    }
}

/// Accrue starvation, and when the grace period lapses kill the sim: fire a
/// [`SimDeathEvent`], drop a tombstone, and remove it from the simulation.
#[allow(clippy::too_many_arguments)]
fn starvation_death_system(
    mut commands: Commands,
    game_config: Res<GameConfig>,
    game_speed: Res<GameSpeed>,
    time: Res<Time>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut deaths: EventWriter<SimDeathEvent>,
    mut manager: ResMut<SimManager>,
    sims: Query<(Entity, &Needs, &Transform, Option<&Starving>)>,
) {
    let speed = game_speed.multiplier();
    if speed == 0.0 {
        return;
    }
    let game_minutes = time.delta_seconds() * speed / game_config.real_seconds_per_game_minute;

    for (entity, needs, transform, starving) in &sims {
        let elapsed = starving.map_or(0.0, |s| s.elapsed);
        match next_starvation(needs.hunger, elapsed, game_minutes) {
            Some(new_elapsed) if is_fatal(new_elapsed) => {
                deaths.send(SimDeathEvent {
                    entity,
                    cause: DeathCause::Starvation,
                });
                spawn_tombstone(
                    &mut commands,
                    &mut meshes,
                    &mut materials,
                    transform.translation,
                );
                manager.sims.retain(|&e| e != entity);
                commands.entity(entity).despawn_recursive();
            }
            Some(new_elapsed) => {
                commands.entity(entity).insert(Starving {
                    elapsed: new_elapsed,
                });
            }
            None => {
                if starving.is_some() {
                    commands.entity(entity).remove::<Starving>();
                }
            }
        }
    }
}

/// Spawn a simple stone slab tombstone at the given lot position.
fn spawn_tombstone(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    position: Vec3,
) {
    let mesh = meshes.add(Cuboid::new(0.6, 0.9, 0.15));
    let material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.35, 0.35, 0.38),
        perceptual_roughness: 0.9,
        ..default()
    });
    commands.spawn((
        PbrBundle {
            mesh,
            material,
            transform: Transform::from_xyz(position.x, 0.45, position.z),
            ..default()
        },
        Tombstone,
        Name::new("Tombstone"),
    ));
}

/// Surviving sims mourn the dead with a lasting grief moodlet.
fn grief_system(
    mut deaths: EventReader<SimDeathEvent>,
    mut survivors: Query<(Entity, &mut ActiveMoodlets)>,
) {
    for death in deaths.read() {
        for (entity, mut moodlets) in &mut survivors {
            if entity == death.entity {
                continue;
            }
            moodlets.add(Moodlet::new(
                "Mourning",
                "Grieving the loss of a loved one.",
                Mood::Sad,
                -40,
                1800.0,
                "grief",
            ));
        }
    }
}

/// Registers the death and grief systems (runs in live mode).
pub struct DeathPlugin;

impl Plugin for DeathPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<Starving>()
            .register_type::<Tombstone>()
            .add_systems(
                Update,
                (starvation_death_system, grief_system)
                    .chain()
                    .run_if(in_state(GameState::LiveMode)),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fatal_only_past_grace_period() {
        assert!(!is_fatal(0.0));
        assert!(!is_fatal(STARVATION_GRACE_MINUTES - 1.0));
        assert!(is_fatal(STARVATION_GRACE_MINUTES));
        assert!(is_fatal(STARVATION_GRACE_MINUTES + 100.0));
    }

    #[test]
    fn timer_accrues_while_starving_and_clears_when_fed() {
        // Critically hungry -> accrues from current elapsed.
        assert_eq!(next_starvation(0.0, 10.0, 5.0), Some(15.0));
        assert_eq!(next_starvation(DEATH_HUNGER, 0.0, 2.0), Some(2.0));
        // Fed above the death threshold -> timer clears.
        assert_eq!(next_starvation(20.0, 100.0, 5.0), None);
        assert_eq!(next_starvation(DEATH_HUNGER + 0.5, 50.0, 5.0), None);
    }
}
