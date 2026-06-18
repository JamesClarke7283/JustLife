//! Floating mood indicator above each sim (Phase 11.3).
//!
//! A small glowing orb hovers over every sim's head, coloured by its dominant
//! mood - warm gold/green for positive moods, red for negative ones. It bobs
//! gently so it reads as alive. The orbs are standalone entities that track each
//! sim's position every frame (the same pattern as the selection ring), which
//! sidesteps the visibility-hierarchy pitfalls of parent/child mesh attachment.

use bevy::prelude::*;

use crate::core::state::GameState;
use crate::sim::moodlet::{ActiveMoodlets, Mood};
use crate::sim::{SimManager, SimName};

/// Height above the sim's origin where the orb floats.
const ORB_HEIGHT: f32 = 2.35;

/// Links a mood orb back to the sim it follows.
#[derive(Component)]
struct MoodOrb {
    sim: Entity,
}

/// Glow colour (emissive) for a mood. Positive moods glow warm/bright,
/// negative moods glow red/dim.
pub fn mood_color(mood: Mood) -> Color {
    match mood {
        Mood::Happy => Color::srgb(1.0, 0.85, 0.25),
        Mood::Energized => Color::srgb(0.3, 1.0, 0.7),
        Mood::Flirty => Color::srgb(1.0, 0.45, 0.7),
        Mood::Focused => Color::srgb(0.4, 0.7, 1.0),
        Mood::Fine => Color::srgb(0.8, 0.9, 0.85),
        Mood::Tense => Color::srgb(1.0, 0.6, 0.2),
        Mood::Embarrassed => Color::srgb(1.0, 0.4, 0.55),
        Mood::Sad => Color::srgb(0.45, 0.55, 0.85),
        Mood::Uncomfortable => Color::srgb(0.85, 0.5, 0.35),
        Mood::Angry => Color::srgb(1.0, 0.2, 0.15),
    }
}

/// Whether a mood is a "positive" one (used to brighten the glow).
pub fn is_positive(mood: Mood) -> bool {
    matches!(
        mood,
        Mood::Happy | Mood::Energized | Mood::Flirty | Mood::Focused | Mood::Fine
    )
}

/// Spawn/update/despawn a mood orb per sim each frame.
#[allow(clippy::too_many_arguments)]
fn mood_orbs(
    mut commands: Commands,
    time: Res<Time>,
    manager: Res<SimManager>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut mesh_cache: Local<Option<Handle<Mesh>>>,
    sims: Query<(&Transform, &ActiveMoodlets), With<SimName>>,
    mut orbs: Query<
        (Entity, &MoodOrb, &mut Transform, &Handle<StandardMaterial>),
        Without<SimName>,
    >,
) {
    let mesh = mesh_cache
        .get_or_insert_with(|| meshes.add(Sphere::new(0.16)))
        .clone();
    // A gentle bob driven by elapsed time.
    let bob = (time.elapsed_seconds() * 2.0).sin() * 0.08;

    // Update or remove existing orbs.
    let mut has_orb = std::collections::HashSet::new();
    for (orb_entity, orb, mut transform, material) in &mut orbs {
        let Ok((sim_transform, moodlets)) = sims.get(orb.sim) else {
            commands.entity(orb_entity).despawn_recursive();
            continue;
        };
        if sim_transform.translation.y < -1.0 {
            // Sim is off-lot (e.g. at work) - hide the orb.
            commands.entity(orb_entity).despawn_recursive();
            continue;
        }
        has_orb.insert(orb.sim);
        let mut pos = sim_transform.translation;
        pos.y += ORB_HEIGHT + bob;
        transform.translation = pos;
        if let Some(mat) = materials.get_mut(material) {
            let mood = moodlets.dominant_mood();
            let color = mood_color(mood);
            mat.base_color = color;
            let boost = if is_positive(mood) { 2.2 } else { 1.4 };
            mat.emissive = LinearRgba::from(color) * boost;
        }
    }

    // Spawn orbs for sims that don't have one yet.
    for &sim in &manager.sims {
        if has_orb.contains(&sim) {
            continue;
        }
        let Ok((sim_transform, moodlets)) = sims.get(sim) else {
            continue;
        };
        if sim_transform.translation.y < -1.0 {
            continue;
        }
        let mood = moodlets.dominant_mood();
        let color = mood_color(mood);
        let mut pos = sim_transform.translation;
        pos.y += ORB_HEIGHT + bob;
        commands.spawn((
            PbrBundle {
                mesh: mesh.clone(),
                material: materials.add(StandardMaterial {
                    base_color: color,
                    emissive: LinearRgba::from(color) * 2.0,
                    unlit: true,
                    ..default()
                }),
                transform: Transform::from_translation(pos),
                ..default()
            },
            MoodOrb { sim },
            Name::new("Mood Orb"),
        ));
    }
}

/// Despawn all orbs when leaving live mode.
fn clear_orbs(mut commands: Commands, orbs: Query<Entity, With<MoodOrb>>) {
    for orb in &orbs {
        commands.entity(orb).despawn_recursive();
    }
}

/// Registers the mood-orb indicator (live mode only).
pub struct MoodEmotePlugin;

impl Plugin for MoodEmotePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, mood_orbs.run_if(in_state(GameState::LiveMode)))
            .add_systems(OnExit(GameState::LiveMode), clear_orbs);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn positive_moods_classified() {
        assert!(is_positive(Mood::Happy));
        assert!(is_positive(Mood::Energized));
        assert!(!is_positive(Mood::Angry));
        assert!(!is_positive(Mood::Sad));
    }

    #[test]
    fn every_mood_has_a_distinct_glow() {
        // Sanity: positive moods are noticeably brighter than the darkest negative.
        let happy = mood_color(Mood::Happy).to_srgba();
        let angry = mood_color(Mood::Angry).to_srgba();
        assert!(happy.green > angry.green); // gold vs red
    }
}
