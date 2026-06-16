use bevy::prelude::*;
use std::f32::consts::FRAC_PI_2;

use crate::build::buy_mode::BuyCatalogState;
use crate::core::resources::MoneyResource;
use crate::core::state::GameState;
use crate::render::camera::IsometricCamera;
use crate::render::primitives::MeshGenerator;
use crate::world::catalog::{CatalogDatabase, CatalogItem, PrimitiveShape, spawn_catalog_item};
use crate::world::placed::{ObjectGrid, footprint_cells};
use crate::world::wall::{Wall, snap_to_grid};
use crate::world::wall_tool::{cursor_ground_xz, point_segment_distance};

/// Width of the buy-mode catalog panel; clicks over it must not place objects.
const PANEL_WIDTH: f32 = 335.0;

/// Object placement: with a catalog item selected, preview a ghost at the cursor
/// and left-click to place it (rotation with R, free placement with Alt).
pub struct PlacementPlugin;

impl Plugin for PlacementPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PlacementState>()
            .add_systems(Update, placement_tool.run_if(in_state(GameState::BuyMode)));
    }
}

#[derive(Resource, Default)]
struct PlacementState {
    /// Current rotation in quarter turns (0-3).
    quarters: u8,
}

#[derive(Component)]
struct PlacementGhost;

/// A footprint is placeable if every cell is free of objects and clear of walls.
fn footprint_ok(cells: &[(i32, i32)], grid: &ObjectGrid, walls: &Query<&Wall>) -> bool {
    if !grid.area_free(cells) {
        return false;
    }
    for &(x, z) in cells {
        let center = Vec2::new(x as f32, z as f32);
        for wall in walls {
            if point_segment_distance(center, wall.start, wall.end) < 0.4 {
                return false;
            }
        }
    }
    true
}

/// Spawn a translucent ghost of `item` (green if valid to place, red if not).
fn spawn_ghost(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    item: &CatalogItem,
    pos: Vec3,
    rotation: Quat,
    valid: bool,
) {
    let color = if valid {
        Color::srgba(0.3, 0.9, 0.4, 0.5)
    } else {
        Color::srgba(0.95, 0.3, 0.3, 0.5)
    };
    let material = materials.add(StandardMaterial {
        base_color: color,
        alpha_mode: AlphaMode::Blend,
        unlit: true,
        ..default()
    });
    let parent = commands
        .spawn((
            SpatialBundle::from_transform(Transform::from_translation(pos).with_rotation(rotation)),
            PlacementGhost,
            Name::new("Placement Ghost"),
        ))
        .id();
    for part in &item.parts {
        let (sx, sy, sz) = part.size;
        let mesh = match part.shape {
            PrimitiveShape::Cuboid => meshes.add(Cuboid::new(sx, sy, sz)),
            PrimitiveShape::Cylinder => meshes.add(Cylinder::new(sx * 0.5, sy)),
            PrimitiveShape::Sphere => meshes.add(Sphere::new(sx * 0.5)),
            PrimitiveShape::Cone => meshes.add(MeshGenerator::cone(sx * 0.5, sy, 16)),
        };
        let child = commands
            .spawn(PbrBundle {
                mesh,
                material: material.clone(),
                transform: Transform::from_translation(Vec3::new(
                    part.offset.0,
                    part.offset.1,
                    part.offset.2,
                )),
                ..default()
            })
            .id();
        commands.entity(parent).add_child(child);
    }
}

#[allow(clippy::too_many_arguments)]
fn placement_tool(
    mouse: Res<ButtonInput<MouseButton>>,
    keyboard: Res<ButtonInput<KeyCode>>,
    buy: Res<BuyCatalogState>,
    catalog: Res<CatalogDatabase>,
    grid: Res<ObjectGrid>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    walls: Query<&Wall>,
    ghosts: Query<Entity, With<PlacementGhost>>,
    mut money: ResMut<MoneyResource>,
    mut state: ResMut<PlacementState>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // Clear last frame's ghost; it is re-spawned below if still applicable.
    for ghost in &ghosts {
        commands.entity(ghost).despawn_recursive();
    }

    let Some(id) = buy.selected.as_deref() else {
        return;
    };
    let Some(item) = catalog.get(id) else {
        return;
    };

    // Rotate the pending object with R.
    if keyboard.just_pressed(KeyCode::KeyR) {
        state.quarters = (state.quarters + 1) % 4;
    }
    let rotation = Quat::from_rotation_y(state.quarters as f32 * FRAC_PI_2);

    let Ok(window) = windows.get_single() else {
        return;
    };
    let Some(cursor) = window.cursor_position() else {
        return;
    };
    // Don't preview/place while the cursor is over the catalog panel.
    if cursor.x > window.width() - PANEL_WIDTH {
        return;
    }

    let Some(ground) = cursor_ground_xz(&windows, &cameras) else {
        return;
    };
    let alt = keyboard.pressed(KeyCode::AltLeft) || keyboard.pressed(KeyCode::AltRight);
    let ground = if alt { ground } else { snap_to_grid(ground) };
    let pos = Vec3::new(ground.x, 0.0, ground.y);

    let cells = footprint_cells(pos, item.footprint, rotation);
    let affordable = money.amount >= item.price as i64;
    let valid = affordable && footprint_ok(&cells, &grid, &walls);

    spawn_ghost(
        &mut commands,
        &mut meshes,
        &mut materials,
        item,
        pos,
        rotation,
        valid,
    );

    if mouse.just_pressed(MouseButton::Left) && valid {
        spawn_catalog_item(
            &mut commands,
            &mut meshes,
            &mut materials,
            item,
            pos,
            rotation,
        );
        money.amount -= item.price as i64;
    }
}
