use bevy::prelude::*;

use crate::build::BuildTool;
use crate::core::state::GameState;
use crate::render::camera::IsometricCamera;
use crate::world::room::{self, FloorCell};
use crate::world::wall::snap_to_grid;
use crate::world::wall_tool::{cursor_ground_xz, spawn_wall_segment};

/// Wires the room tool: drag a rectangle to build a room (walls + floor).
pub struct RoomToolPlugin;

impl Plugin for RoomToolPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Rooms>()
            .init_resource::<RoomDragState>()
            .add_systems(
                Update,
                room_building_tool.run_if(in_state(GameState::BuildMode)),
            );
    }
}

/// Registry of tool-created rooms so a room can be deleted as a unit.
#[derive(Resource, Default)]
struct Rooms {
    records: Vec<RoomRecord>,
}

struct RoomRecord {
    min: Vec2,
    max: Vec2,
    members: Vec<Entity>,
}

#[derive(Resource, Default)]
struct RoomDragState {
    start: Option<Vec2>,
}

#[derive(Component)]
struct RoomGhost;

/// Normalize two drag corners into (min, max).
fn rect_bounds(a: Vec2, b: Vec2) -> (Vec2, Vec2) {
    (
        Vec2::new(a.x.min(b.x), a.y.min(b.y)),
        Vec2::new(a.x.max(b.x), a.y.max(b.y)),
    )
}

/// Is `p` inside the inclusive rectangle [min, max]?
fn point_in_rect(p: Vec2, min: Vec2, max: Vec2) -> bool {
    p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y
}

/// Spawn a translucent floor quad previewing the room being dragged.
fn spawn_room_ghost(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    min: Vec2,
    max: Vec2,
) {
    let size = max - min;
    if size.x < 0.5 || size.y < 0.5 {
        return;
    }
    let center = (min + max) * 0.5;
    let mesh = meshes.add(Plane3d::default().mesh().size(size.x, size.y));
    let material = materials.add(StandardMaterial {
        base_color: Color::srgba(0.35, 0.9, 0.45, 0.4),
        alpha_mode: AlphaMode::Blend,
        unlit: true,
        ..default()
    });
    commands.spawn((
        PbrBundle {
            mesh,
            material,
            transform: Transform::from_xyz(center.x, 0.03, center.y),
            ..default()
        },
        RoomGhost,
        Name::new("Room Ghost"),
    ));
}

/// Build a room: four perimeter walls plus a floor. Returns its member entities.
fn spawn_room(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    asset_server: &AssetServer,
    min: Vec2,
    max: Vec2,
) -> Vec<Entity> {
    let mut members = vec![
        spawn_wall_segment(commands, Vec2::new(min.x, min.y), Vec2::new(max.x, min.y)),
        spawn_wall_segment(commands, Vec2::new(max.x, min.y), Vec2::new(max.x, max.y)),
        spawn_wall_segment(commands, Vec2::new(max.x, max.y), Vec2::new(min.x, max.y)),
        spawn_wall_segment(commands, Vec2::new(min.x, max.y), Vec2::new(min.x, min.y)),
    ];
    // Two corner cells establish the floor's bounding box.
    let cells = vec![FloorCell::from_world(min), FloorCell::from_world(max)];
    members.push(room::spawn_room_floor(
        commands,
        meshes,
        materials,
        asset_server,
        &cells,
    ));
    members
}

/// Drag a rectangle to build a room; right-click inside a room to delete it.
#[allow(clippy::too_many_arguments)]
fn room_building_tool(
    mouse: Res<ButtonInput<MouseButton>>,
    build_tool: Res<BuildTool>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    ghosts: Query<Entity, With<RoomGhost>>,
    mut drag: ResMut<RoomDragState>,
    mut rooms: ResMut<Rooms>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    if *build_tool != BuildTool::Room {
        for ghost in &ghosts {
            commands.entity(ghost).despawn();
        }
        return;
    }
    let Some(ground) = cursor_ground_xz(&windows, &cameras) else {
        return;
    };
    let snapped = snap_to_grid(ground);

    // Right-click deletes the room under the cursor (walls + floor).
    if mouse.just_pressed(MouseButton::Right) {
        if let Some(idx) = rooms
            .records
            .iter()
            .position(|r| point_in_rect(snapped, r.min, r.max))
        {
            let record = rooms.records.remove(idx);
            for entity in record.members {
                commands.entity(entity).despawn_recursive();
            }
        }
        return;
    }

    if mouse.just_pressed(MouseButton::Left) {
        drag.start = Some(snapped);
    }

    // Refresh the ghost rectangle each frame while dragging.
    for ghost in &ghosts {
        commands.entity(ghost).despawn();
    }
    if let Some(start) = drag.start {
        let (min, max) = rect_bounds(start, snapped);
        spawn_room_ghost(&mut commands, &mut meshes, &mut materials, min, max);
    }

    if mouse.just_released(MouseButton::Left)
        && let Some(start) = drag.start.take()
    {
        let (min, max) = rect_bounds(start, snapped);
        // Minimum room size: 2x2 cells.
        if (max.x - min.x) >= 2.0 && (max.y - min.y) >= 2.0 {
            let members = spawn_room(
                &mut commands,
                &mut meshes,
                &mut materials,
                &asset_server,
                min,
                max,
            );
            rooms.records.push(RoomRecord { min, max, members });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rect_bounds_normalizes() {
        let (min, max) = rect_bounds(Vec2::new(4.0, 1.0), Vec2::new(0.0, 5.0));
        assert_eq!(min, Vec2::new(0.0, 1.0));
        assert_eq!(max, Vec2::new(4.0, 5.0));
    }

    #[test]
    fn point_in_rect_works() {
        assert!(point_in_rect(
            Vec2::new(2.0, 2.0),
            Vec2::ZERO,
            Vec2::new(4.0, 4.0)
        ));
        assert!(!point_in_rect(
            Vec2::new(5.0, 2.0),
            Vec2::ZERO,
            Vec2::new(4.0, 4.0)
        ));
    }
}
