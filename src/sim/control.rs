//! Direct player control of sims (Sims-style):
//! - left-click a sim to select it (the controlled sim),
//! - left-click an object to send the active sim to go use it,
//! - right-click empty ground to send the selected sim walking there,
//! - right-click a sim/object still opens its interaction menu (pie menu).
//!
//! A glowing ring marks the selected sim. (Pointer input is only deliverable by
//! a real mouse, not the headless harness, so this is verified by unit tests +
//! real play; the selection math is factored out for testing.)

use bevy::prelude::*;

use crate::core::components::RouteTo;
use crate::core::events::ToastEvent;
use crate::core::resources::SelectionResource;
use crate::core::state::GameState;
use crate::render::camera::IsometricCamera;
use crate::sim::interaction::{ActiveInteraction, InteractionQueue, QueuedInteraction};
use crate::sim::movement::MoveTo;
use crate::sim::{AnimationState, SimManager, SimName};
use crate::social::conversation::InConversation;
use crate::ui::pie_menu::PieMenuState;
use crate::world::PlacedObject;
use crate::world::catalog::CatalogDatabase;
use crate::world::placed::ObjectGrid;
use crate::world::wall::snap_to_grid;
use crate::world::wall_tool::cursor_ground_xz;

/// How close (world units) the cursor must be to a sim to pick/consider it.
const SELECT_RADIUS: f32 = 1.5;

/// Marks the glowing ring drawn under the selected sim.
#[derive(Component)]
struct SelectionRing;

/// The nearest sim to `point` within `SELECT_RADIUS`, if any.
fn nearest_sim<'a>(
    point: Vec3,
    sims: impl IntoIterator<Item = (Entity, &'a Transform)>,
) -> Option<Entity> {
    let mut best: Option<(f32, Entity)> = None;
    for (entity, transform) in sims {
        let d = transform.translation.distance(point);
        if d < SELECT_RADIUS && best.is_none_or(|(bd, _)| d < bd) {
            best = Some((d, entity));
        }
    }
    best.map(|(_, e)| e)
}

/// Left-click selects a sim, or - when an object is clicked - sends the
/// active sim to go use it (queues the object's primary interaction).
#[allow(clippy::too_many_arguments)]
fn select_or_interact(
    mouse: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    pie: Res<PieMenuState>,
    grid: Res<ObjectGrid>,
    catalog: Res<CatalogDatabase>,
    manager: Res<SimManager>,
    sims: Query<(Entity, &Transform), With<SimName>>,
    objects: Query<&PlacedObject>,
    mut queues: Query<&mut InteractionQueue>,
    mut selection: ResMut<SelectionResource>,
    mut toasts: EventWriter<ToastEvent>,
    mut commands: Commands,
) {
    if pie.open || !mouse.just_pressed(MouseButton::Left) {
        return;
    }
    let Some(ground) = cursor_ground_xz(&windows, &cameras) else {
        return;
    };
    let point = Vec3::new(ground.x, 0.0, ground.y);

    // Clicking a sim selects it.
    if let Some(entity) = nearest_sim(point, sims.iter()) {
        selection.selected = Some(entity);
        return;
    }

    // Clicking an object sends the active sim (selected, or the player's) to use it.
    let cell = snap_to_grid(ground);
    let Some(&object) = grid.occupied.get(&(cell.x as i32, cell.y as i32)) else {
        return;
    };
    let Ok(obj) = objects.get(object) else {
        return;
    };
    let Some(action) = catalog.get(&obj.catalog_id).and_then(|i| i.actions.first()) else {
        return;
    };
    let Some(sim) = selection.selected.or_else(|| manager.sims.first().copied()) else {
        return;
    };
    if let Ok(mut queue) = queues.get_mut(sim) {
        queue.queue_player_command(QueuedInteraction {
            target: object,
            action: action.name.clone(),
            need: action.need,
            rate: action.rate,
            source: crate::sim::interaction::InteractionSource::Player,
        });
        // Interrupt whatever the sim was doing so it re-routes to the click.
        commands
            .entity(sim)
            .remove::<ActiveInteraction>()
            .remove::<RouteTo>()
            .remove::<MoveTo>()
            .remove::<InConversation>();
        toasts.send(ToastEvent::info(format!("Going to: {}", action.name)));
    }
}

/// Right-click empty ground to send the selected sim walking there, overriding
/// its autonomy plan / conversation. Right-clicks on a sim/object are left to
/// the pie menu's context handler.
#[allow(clippy::too_many_arguments)]
fn move_selected_sim(
    mouse: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    grid: Res<ObjectGrid>,
    selection: Res<SelectionResource>,
    objects: Query<(), With<PlacedObject>>,
    sims: Query<&Transform, With<SimName>>,
    mut anims: Query<&mut AnimationState>,
    mut queues: Query<&mut InteractionQueue>,
    mut commands: Commands,
) {
    if !mouse.just_pressed(MouseButton::Right) {
        return;
    }
    let Some(selected) = selection.selected else {
        return;
    };
    let Some(ground) = cursor_ground_xz(&windows, &cameras) else {
        return;
    };
    let point = Vec3::new(ground.x, 0.0, ground.y);

    // If an object or sim sits under the cursor, that's a context-menu click.
    let cell = snap_to_grid(ground);
    let on_object = grid
        .occupied
        .get(&(cell.x as i32, cell.y as i32))
        .is_some_and(|e| objects.get(*e).is_ok());
    let on_sim = sims
        .iter()
        .any(|t| t.translation.distance(point) < SELECT_RADIUS);
    if on_object || on_sim {
        return;
    }

    // Walk command: override any autonomy plan / conversation.
    commands
        .entity(selected)
        .insert(MoveTo::new(point))
        .remove::<RouteTo>()
        .remove::<ActiveInteraction>()
        .remove::<InConversation>();
    if let Ok(mut queue) = queues.get_mut(selected) {
        queue.clear();
    }
    if let Ok(mut anim) = anims.get_mut(selected) {
        *anim = AnimationState::Walking;
    }
}

/// Draw a glowing ring under the selected sim (immediate-mode).
fn selection_ring(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut cache: Local<Option<(Handle<Mesh>, Handle<StandardMaterial>)>>,
    selection: Res<SelectionResource>,
    rings: Query<Entity, With<SelectionRing>>,
    sims: Query<&Transform, With<SimName>>,
) {
    for ring in &rings {
        commands.entity(ring).despawn_recursive();
    }
    let Some(selected) = selection.selected else {
        return;
    };
    let Ok(transform) = sims.get(selected) else {
        return;
    };
    if transform.translation.y < -1.0 {
        return; // off-lot (e.g. at work)
    }
    let (mesh, material) = cache.get_or_insert_with(|| {
        (
            meshes.add(Cylinder::new(0.6, 0.04)),
            materials.add(StandardMaterial {
                base_color: Color::srgba(0.3, 0.95, 0.4, 0.8),
                emissive: LinearRgba::new(0.2, 0.8, 0.3, 1.0),
                unlit: true,
                ..default()
            }),
        )
    });
    let mut pos = transform.translation;
    pos.y = 0.05;
    commands.spawn((
        PbrBundle {
            mesh: mesh.clone(),
            material: material.clone(),
            transform: Transform::from_translation(pos),
            ..default()
        },
        SelectionRing,
        Name::new("Selection Ring"),
    ));
}

/// Registers direct sim control (live mode only).
pub struct SimControlPlugin;

impl Plugin for SimControlPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            Update,
            (select_or_interact, move_selected_sim, selection_ring)
                .run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(x: f32, z: f32) -> Transform {
        Transform::from_xyz(x, 0.0, z)
    }

    #[test]
    fn picks_the_closest_sim_in_range() {
        let a = Entity::from_raw(1);
        let b = Entity::from_raw(2);
        let ta = at(0.2, 0.0);
        let tb = at(1.0, 0.0);
        // Click near A -> A; both within radius but A is closer.
        let picked = nearest_sim(Vec3::new(0.0, 0.0, 0.0), [(a, &ta), (b, &tb)]);
        assert_eq!(picked, Some(a));
    }

    #[test]
    fn ignores_sims_out_of_range() {
        let a = Entity::from_raw(1);
        let ta = at(10.0, 10.0);
        assert_eq!(nearest_sim(Vec3::ZERO, [(a, &ta)]), None);
    }
}
