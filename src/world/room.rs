use bevy::prelude::*;
use std::collections::HashSet;

use crate::render::primitives::MeshGenerator;
use crate::world::wall::{Wall, snap_to_grid};

/// A rectangular floor tile placed inside a room.
#[derive(Component, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct RoomFloor {
    pub parent_room: Entity,
    pub material: String,
}

impl Default for RoomFloor {
    fn default() -> Self {
        Self {
            parent_room: Entity::PLACEHOLDER,
            material: "oak".to_string(),
        }
    }
}

/// A floor cell in the buildable grid.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FloorCell {
    pub x: i32,
    pub z: i32,
}

impl FloorCell {
    /// Build a cell from a world XZ point snapped to the nearest grid unit.
    pub fn from_world(point: Vec2) -> Self {
        let snapped = snap_to_grid(point);
        Self {
            x: snapped.x as i32,
            z: snapped.y as i32,
        }
    }

    /// World-space center of this cell.
    pub fn center(&self) -> Vec2 {
        Vec2::new(self.x as f32, self.z as f32)
    }
}

/// Build a set of grid cells that are not blocked by a wall using an iterator.
pub fn compute_walkable_cells_from_iter<'a>(
    walls: impl Iterator<Item = &'a Wall>,
    bounds_min: Vec2,
    bounds_max: Vec2,
) -> HashSet<FloorCell> {
    let mut walkable: HashSet<FloorCell> = HashSet::new();
    let min = FloorCell::from_world(bounds_min);
    let max = FloorCell::from_world(bounds_max);

    for x in min.x..=max.x {
        for z in min.z..=max.z {
            walkable.insert(FloorCell { x, z });
        }
    }

    for wall in walls {
        mark_wall_cells(&mut walkable, wall);
    }

    walkable
}

/// Compute indoor cells from a set of walkable cells.
pub fn compute_indoor_cells(walkable: &HashSet<FloorCell>) -> HashSet<FloorCell> {
    let mut indoor: HashSet<FloorCell> = HashSet::new();
    for cell in walkable.iter() {
        let neighbors = [
            FloorCell {
                x: cell.x - 1,
                z: cell.z,
            },
            FloorCell {
                x: cell.x + 1,
                z: cell.z,
            },
            FloorCell {
                x: cell.x,
                z: cell.z - 1,
            },
            FloorCell {
                x: cell.x,
                z: cell.z + 1,
            },
        ];
        let enclosed = neighbors.iter().all(|n| walkable.contains(n));
        if enclosed {
            indoor.insert(*cell);
        }
    }
    indoor
}

/// Group adjacent cells into contiguous regions using flood fill.
pub fn flood_fill_regions(cells: &HashSet<FloorCell>) -> Vec<Vec<FloorCell>> {
    let mut remaining: HashSet<FloorCell> = cells.clone();
    let mut regions: Vec<Vec<FloorCell>> = Vec::new();

    while let Some(start) = remaining.iter().copied().next() {
        let mut region: Vec<FloorCell> = Vec::new();
        let mut stack = vec![start];
        remaining.remove(&start);

        while let Some(current) = stack.pop() {
            region.push(current);
            let neighbors = [
                FloorCell {
                    x: current.x - 1,
                    z: current.z,
                },
                FloorCell {
                    x: current.x + 1,
                    z: current.z,
                },
                FloorCell {
                    x: current.x,
                    z: current.z - 1,
                },
                FloorCell {
                    x: current.x,
                    z: current.z + 1,
                },
            ];
            for neighbor in neighbors {
                if remaining.remove(&neighbor) {
                    stack.push(neighbor);
                }
            }
        }

        regions.push(region);
    }

    regions
}

/// Mark cells covered by a wall as non-walkable.
fn mark_wall_cells(walkable: &mut HashSet<FloorCell>, wall: &Wall) {
    let start = FloorCell::from_world(wall.start);
    let end = FloorCell::from_world(wall.end);

    if start.x == end.x {
        let z0 = start.z.min(end.z);
        let z1 = start.z.max(end.z);
        for z in z0..=z1 {
            walkable.remove(&FloorCell { x: start.x, z });
        }
    } else if start.z == end.z {
        let x0 = start.x.min(end.x);
        let x1 = start.x.max(end.x);
        for x in x0..=x1 {
            walkable.remove(&FloorCell { x, z: start.z });
        }
    }
}

/// Compute the bounding box of a set of cells.
fn cell_bounds(cells: &[FloorCell]) -> (FloorCell, FloorCell) {
    let mut min = FloorCell {
        x: i32::MAX,
        z: i32::MAX,
    };
    let mut max = FloorCell {
        x: i32::MIN,
        z: i32::MIN,
    };
    for cell in cells {
        min.x = min.x.min(cell.x);
        min.z = min.z.min(cell.z);
        max.x = max.x.max(cell.x);
        max.z = max.z.max(cell.z);
    }
    (min, max)
}

/// Spawn a textured floor plane covering every cell in a region.
pub fn spawn_room_floor(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    asset_server: &AssetServer,
    cells: &[FloorCell],
) -> Entity {
    let (min, max) = cell_bounds(cells);
    let width = (max.x - min.x + 1) as f32;
    let depth = (max.z - min.z + 1) as f32;
    let center = Vec3::new(
        (min.x as f32 + max.x as f32) / 2.0,
        // Lift the floor a hair above the terrain plane (y=0) to avoid z-fighting.
        0.02,
        (min.z as f32 + max.z as f32) / 2.0,
    );

    let texture_path = "textures/floor_hardwood_oak.png";
    let texture: Handle<Image> = asset_server.load(texture_path);
    let material = materials.add(StandardMaterial {
        base_color_texture: Some(texture),
        perceptual_roughness: 0.85,
        ..default()
    });

    let uv_scale = (width + depth) * 0.5;
    let mesh = meshes.add(MeshGenerator::plane(width, depth, uv_scale));

    let area = width * depth;
    commands
        .spawn((
            PbrBundle {
                mesh,
                material,
                transform: Transform::from_translation(center),
                ..default()
            },
            super::Room {
                name: "Room".to_string(),
                area,
                indoor: true,
                floor_material: "oak".to_string(),
            },
            RoomFloor {
                parent_room: Entity::PLACEHOLDER,
                material: "oak".to_string(),
            },
            Name::new("Room Floor"),
        ))
        .id()
}

/// Queue one room floor tile as a deferred command that handles its own World borrows.
pub fn spawn_room_floor_command(cells: Vec<FloorCell>) -> impl bevy::ecs::world::Command {
    move |world: &mut World| {
        let asset_server = world.get_resource::<AssetServer>().unwrap().clone();
        world.resource_scope(|world, mut meshes: Mut<Assets<Mesh>>| {
            world.resource_scope(|world, mut materials: Mut<Assets<StandardMaterial>>| {
                let mut commands = world.commands();
                spawn_room_floor(
                    &mut commands,
                    &mut meshes,
                    &mut materials,
                    &asset_server,
                    &cells,
                );
            });
        });
    }
}

/// Detect enclosed rooms from a wall layout and spawn floor entities for them.
#[allow(clippy::too_many_arguments)]
pub fn detect_and_spawn_rooms(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    asset_server: &AssetServer,
    walls: &mut QueryState<&Wall>,
    world: &World,
    bounds_min: Vec2,
    bounds_max: Vec2,
) -> Vec<Entity> {
    let walkable = compute_walkable_cells(walls, world, bounds_min, bounds_max);
    let indoor = compute_indoor_cells(&walkable);
    let regions = flood_fill_regions(&indoor);

    let mut room_entities = Vec::with_capacity(regions.len());
    for region in regions {
        let entity = spawn_room_floor(commands, meshes, materials, asset_server, &region);
        room_entities.push(entity);
    }
    room_entities
}

/// Build a set of grid cells that are not blocked by a wall.
fn compute_walkable_cells(
    walls: &mut QueryState<&Wall>,
    world: &World,
    bounds_min: Vec2,
    bounds_max: Vec2,
) -> HashSet<FloorCell> {
    compute_walkable_cells_from_iter(walls.iter(world), bounds_min, bounds_max)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cell_from_world_snaps_to_grid() {
        assert_eq!(
            FloorCell::from_world(Vec2::new(0.4, 0.6)),
            FloorCell { x: 0, z: 1 }
        );
        assert_eq!(
            FloorCell::from_world(Vec2::new(-0.6, -0.4)),
            FloorCell { x: -1, z: 0 }
        );
    }

    #[test]
    fn cell_center_matches_grid() {
        let cell = FloorCell { x: 2, z: -3 };
        assert_eq!(cell.center(), Vec2::new(2.0, -3.0));
    }

    #[test]
    fn wall_blocks_cells() {
        let wall = Wall::new(Vec2::new(-2.0, -2.0), Vec2::new(2.0, -2.0));
        let mut walkable = HashSet::new();
        for x in -2..=2 {
            for z in -2..=2 {
                walkable.insert(FloorCell { x, z });
            }
        }
        mark_wall_cells(&mut walkable, &wall);
        for x in -2..=2 {
            assert!(!walkable.contains(&FloorCell { x, z: -2 }));
        }
    }

    #[test]
    fn enclosed_region_detected() {
        let walls: Vec<Wall> = vec![
            Wall::new(Vec2::new(-2.0, -2.0), Vec2::new(2.0, -2.0)),
            Wall::new(Vec2::new(2.0, -2.0), Vec2::new(2.0, 2.0)),
            Wall::new(Vec2::new(2.0, 2.0), Vec2::new(-2.0, 2.0)),
            Wall::new(Vec2::new(-2.0, 2.0), Vec2::new(-2.0, -2.0)),
        ];

        let walkable = compute_walkable_cells_from_iter(
            walls.iter(),
            Vec2::new(-1.0, -1.0),
            Vec2::new(1.0, 1.0),
        );
        let indoor = compute_indoor_cells(&walkable);
        let regions = flood_fill_regions(&indoor);
        assert_eq!(regions.len(), 1);
        assert_eq!(regions[0].len(), 1);
        assert_eq!(regions[0][0], FloorCell { x: 0, z: 0 });
    }
}
