use bevy::prelude::*;

use crate::core::state::GameState;
use crate::render::camera::IsometricCamera;
use crate::render::primitives::MeshGenerator;
use crate::world::wall::{Wall, WallVisualDirty, snap_to_grid};

/// Tracks which wall sub-tool is active.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq)]
pub enum WallToolState {
    #[default]
    Inactive,
    Placing,
    Deleting,
}

/// Drag state for the click-and-drag wall builder.
#[derive(Resource, Default)]
pub struct WallDragState {
    /// Grid-snapped start point of the current drag, if any.
    start: Option<Vec2>,
}

/// Marker for the translucent ghost wall shown while dragging.
#[derive(Component)]
struct WallGhost;

/// Wires the interactive wall-building tool. Systems only run in build mode.
pub struct WallToolPlugin;

impl Plugin for WallToolPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<WallDragState>()
            .init_resource::<WallToolState>()
            .add_systems(
                Update,
                wall_building_tool.run_if(in_state(GameState::BuildMode)),
            );
    }
}

/// Spawns a wall segment between two grid-snapped points. Includes a
/// `SpatialBundle` so the wall's child meshes render (see B0004).
pub fn spawn_wall_segment(commands: &mut Commands, start: Vec2, end: Vec2) -> Entity {
    commands
        .spawn((
            Wall::snapped(start, end),
            WallVisualDirty,
            Name::new("Wall"),
            SpatialBundle::default(),
        ))
        .id()
}

/// Delete a wall entity and its children.
pub fn delete_wall(commands: &mut Commands, wall_entity: Entity) {
    commands.entity(wall_entity).despawn_recursive();
}

/// Validate that a new wall segment doesn't coincide with an existing one.
pub fn validate_wall_placement(new_wall: &Wall, existing_walls: &Query<'_, '_, &Wall>) -> bool {
    !existing_walls.iter().any(|wall| new_wall.overlaps(wall))
}

/// Raycast the cursor onto the ground plane (y=0), returning the XZ point.
fn cursor_ground_xz(
    windows: &Query<&Window>,
    cameras: &Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
) -> Option<Vec2> {
    let window = windows.get_single().ok()?;
    let cursor = window.cursor_position()?;
    let (camera, cam_tf) = cameras.get_single().ok()?;
    let ray = camera.viewport_to_world(cam_tf, cursor)?;
    let dist = ray.intersect_plane(Vec3::ZERO, InfinitePlane3d::new(Vec3::Y))?;
    Some(ray.get_point(dist).xz())
}

/// Snap `end` so the segment from `start` is axis-aligned (straight walls only),
/// keeping whichever axis the drag is longer along.
pub fn axis_align(start: Vec2, end: Vec2) -> Vec2 {
    let dx = (end.x - start.x).abs();
    let dz = (end.y - start.y).abs();
    if dx >= dz {
        Vec2::new(end.x, start.y)
    } else {
        Vec2::new(start.x, end.y)
    }
}

/// Shortest distance from `p` to the segment `a`-`b` (used for click-to-delete).
pub fn point_segment_distance(p: Vec2, a: Vec2, b: Vec2) -> f32 {
    let ab = b - a;
    let len_sq = ab.length_squared();
    if len_sq < 1e-6 {
        return p.distance(a);
    }
    let t = ((p - a).dot(ab) / len_sq).clamp(0.0, 1.0);
    p.distance(a + ab * t)
}

/// Spawn the translucent ghost preview wall.
fn spawn_ghost(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    start: Vec2,
    end: Vec2,
) {
    let delta = end - start;
    let length = delta.length();
    if length < 0.01 {
        return;
    }
    let mid = (start + end) * 0.5;
    let angle = delta.y.atan2(delta.x);
    let height = 3.0;
    let mesh = meshes.add(MeshGenerator::wall(length, height, 0.2));
    let material = materials.add(StandardMaterial {
        base_color: Color::srgba(0.35, 0.9, 0.45, 0.45),
        alpha_mode: AlphaMode::Blend,
        unlit: true,
        ..default()
    });
    commands.spawn((
        PbrBundle {
            mesh,
            material,
            transform: Transform {
                translation: Vec3::new(mid.x, height / 2.0, mid.y),
                rotation: Quat::from_rotation_y(-angle),
                scale: Vec3::ONE,
            },
            ..default()
        },
        WallGhost,
        Name::new("Wall Ghost"),
    ));
}

/// Click-and-drag to place walls; right-click a wall to delete it.
#[allow(clippy::too_many_arguments)]
fn wall_building_tool(
    mouse: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    walls: Query<(Entity, &Wall)>,
    ghosts: Query<Entity, With<WallGhost>>,
    mut drag: ResMut<WallDragState>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let Some(ground) = cursor_ground_xz(&windows, &cameras) else {
        return;
    };
    let snapped = snap_to_grid(ground);

    // Right-click deletes the nearest wall under the cursor.
    if mouse.just_pressed(MouseButton::Right) {
        let mut best: Option<(Entity, f32)> = None;
        for (entity, wall) in &walls {
            let d = point_segment_distance(snapped, wall.start, wall.end);
            if d <= 0.6 && best.is_none_or(|(_, bd)| d < bd) {
                best = Some((entity, d));
            }
        }
        if let Some((entity, _)) = best {
            delete_wall(&mut commands, entity);
        }
        return;
    }

    if mouse.just_pressed(MouseButton::Left) {
        drag.start = Some(snapped);
    }

    // Refresh the ghost preview every frame while dragging.
    for ghost in &ghosts {
        commands.entity(ghost).despawn();
    }
    if let Some(start) = drag.start {
        let end = axis_align(start, snapped);
        spawn_ghost(&mut commands, &mut meshes, &mut materials, start, end);
    }

    if mouse.just_released(MouseButton::Left)
        && let Some(start) = drag.start.take()
    {
        let end = axis_align(start, snapped);
        if start.distance(end) >= 1.0 {
            let new_wall = Wall::snapped(start, end);
            if !walls.iter().any(|(_, w)| new_wall.overlaps(w)) {
                spawn_wall_segment(&mut commands, start, end);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn axis_align_picks_longer_axis() {
        // Mostly-horizontal drag -> flat wall along X.
        let e = axis_align(Vec2::new(0.0, 0.0), Vec2::new(4.0, 1.0));
        assert_eq!(e, Vec2::new(4.0, 0.0));
        // Mostly-vertical drag -> wall along Z.
        let e = axis_align(Vec2::new(0.0, 0.0), Vec2::new(1.0, 5.0));
        assert_eq!(e, Vec2::new(0.0, 5.0));
    }

    #[test]
    fn point_segment_distance_basics() {
        // Point on the segment.
        let d = point_segment_distance(Vec2::new(2.0, 0.0), Vec2::ZERO, Vec2::new(4.0, 0.0));
        assert!(d < 1e-5);
        // Point offset perpendicular.
        let d = point_segment_distance(Vec2::new(2.0, 1.0), Vec2::ZERO, Vec2::new(4.0, 0.0));
        assert!((d - 1.0).abs() < 1e-5);
        // Point beyond the end clamps to the endpoint.
        let d = point_segment_distance(Vec2::new(6.0, 0.0), Vec2::ZERO, Vec2::new(4.0, 0.0));
        assert!((d - 2.0).abs() < 1e-5);
    }
}
