use bevy::prelude::*;

use crate::render::primitives::MeshGenerator;
use crate::world::door::Door;
use crate::world::wall::{Wall, WallFace, WallMeshChild, WallVisualDirty};
use crate::world::window::Window;

/// Rebuild visual meshes for any wall marked as dirty.
#[allow(clippy::too_many_arguments)]
pub fn update_wall_visuals(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
    walls: Query<(Entity, &Wall, &WallVisualDirty)>,
    existing: Query<Entity, With<WallMeshChild>>,
    doors: Query<(Entity, &Door)>,
    windows: Query<(Entity, &Window)>,
) {
    let interior_texture: Handle<Image> = asset_server.load("textures/wall_plaster_light.png");
    let exterior_texture: Handle<Image> = asset_server.load("textures/wall_brick_red.png");

    let interior_material = materials.add(StandardMaterial {
        base_color_texture: Some(interior_texture),
        perceptual_roughness: 0.9,
        ..default()
    });
    let exterior_material = materials.add(StandardMaterial {
        base_color_texture: Some(exterior_texture),
        perceptual_roughness: 0.9,
        ..default()
    });

    for (entity, wall, _) in walls.iter() {
        // Remove only the children belonging to this wall, not all wall meshes in the world.
        for child in existing.iter() {
            commands.entity(child).despawn_recursive();
        }

        let mid = wall.midpoint().extend(0.0);
        let delta = wall.end - wall.start;
        let length = delta.length();
        let angle = delta.y.atan2(delta.x);
        let rotation = Quat::from_rotation_y(-angle);

        let wall_direction = wall.direction();
        // Collect openings that belong to this wall segment.
        let mut openings: Vec<Opening> = Vec::new();
        for (_, door) in doors.iter() {
            if let Some(parent) = door.wall_segment
                && parent == entity
            {
                openings.push(Opening::Door {
                    position: door.position,
                    width: door.width,
                });
            }
        }
        for (_, window) in windows.iter() {
            if let Some(parent) = window.wall_segment
                && parent == entity
            {
                openings.push(Opening::Window {
                    position: window.position,
                    width: window.width,
                });
            }
        }

        // If no openings, spawn a simple full wall as before.
        if openings.is_empty() {
            let interior_mesh =
                meshes.add(MeshGenerator::wall(length, wall.height, wall.thickness));
            let interior = commands
                .spawn((
                    PbrBundle {
                        mesh: interior_mesh,
                        material: interior_material.clone(),
                        transform: Transform {
                            translation: mid + Vec3::new(0.0, wall.height / 2.0, 0.0),
                            rotation,
                            scale: Vec3::ONE,
                        },
                        ..default()
                    },
                    WallMeshChild {
                        parent_wall: entity,
                        face: WallFace::Interior,
                    },
                ))
                .id();

            let exterior = commands
                .spawn((
                    PbrBundle {
                        mesh: meshes.add(MeshGenerator::wall(length, wall.height, wall.thickness)),
                        material: exterior_material.clone(),
                        transform: Transform {
                            translation: mid + Vec3::new(0.0, wall.height / 2.0, 0.0),
                            rotation,
                            scale: Vec3::new(1.0, 1.0, 1.02),
                        },
                        ..default()
                    },
                    WallMeshChild {
                        parent_wall: entity,
                        face: WallFace::Exterior,
                    },
                ))
                .id();

            commands.entity(entity).push_children(&[interior, exterior]);
        } else {
            // Sort openings along the wall from start to end.
            openings.sort_by(|a, b| {
                let pa = a.position();
                let pb = b.position();
                let ta = (pa - wall.start).dot(wall_direction);
                let tb = (pb - wall.start).dot(wall_direction);
                ta.partial_cmp(&tb).unwrap_or(std::cmp::Ordering::Equal)
            });

            // Clip out the opening regions and spawn wall pieces in between.
            let mut cursor = 0.0_f32;
            for opening in &openings {
                let position = (opening.position() - wall.start).dot(wall_direction);
                let half_width = opening.width() * 0.5;
                let start = (position - half_width).max(0.0);
                let end = (position + half_width).min(length);
                if start > cursor {
                    spawn_wall_piece(
                        &mut commands,
                        &mut meshes,
                        &interior_material,
                        &exterior_material,
                        wall,
                        entity,
                        rotation,
                        cursor,
                        start,
                    );
                }
                cursor = cursor.max(end);
            }
            if cursor < length {
                spawn_wall_piece(
                    &mut commands,
                    &mut meshes,
                    &interior_material,
                    &exterior_material,
                    wall,
                    entity,
                    rotation,
                    cursor,
                    length,
                );
            }
        }

        commands.entity(entity).remove::<WallVisualDirty>();
    }
}

#[derive(Debug, Clone, Copy)]
enum Opening {
    Door { position: Vec2, width: f32 },
    Window { position: Vec2, width: f32 },
}

impl Opening {
    fn position(&self) -> Vec2 {
        match self {
            Opening::Door { position, .. } => *position,
            Opening::Window { position, .. } => *position,
        }
    }

    fn width(&self) -> f32 {
        match self {
            Opening::Door { width, .. } => *width,
            Opening::Window { width, .. } => *width,
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn spawn_wall_piece(
    commands: &mut Commands<'_, '_>,
    meshes: &mut ResMut<'_, Assets<Mesh>>,
    interior_material: &Handle<StandardMaterial>,
    exterior_material: &Handle<StandardMaterial>,
    wall: &Wall,
    parent_wall: Entity,
    wall_rotation: Quat,
    start_dist: f32,
    end_dist: f32,
) {
    let length = end_dist - start_dist;
    if length <= 0.0 {
        return;
    }
    let direction = wall.direction();
    let start_world = wall.start + direction * start_dist;
    let end_world = wall.start + direction * end_dist;
    let piece_mid = ((start_world + end_world) * 0.5).extend(0.0);

    let interior_mesh = meshes.add(MeshGenerator::wall(length, wall.height, wall.thickness));
    let interior = commands
        .spawn((
            PbrBundle {
                mesh: interior_mesh,
                material: interior_material.clone(),
                transform: Transform {
                    translation: piece_mid + Vec3::new(0.0, wall.height / 2.0, 0.0),
                    rotation: wall_rotation,
                    scale: Vec3::ONE,
                },
                ..default()
            },
            WallMeshChild {
                parent_wall,
                face: WallFace::Interior,
            },
        ))
        .id();

    let exterior = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(MeshGenerator::wall(length, wall.height, wall.thickness)),
                material: exterior_material.clone(),
                transform: Transform {
                    translation: piece_mid + Vec3::new(0.0, wall.height / 2.0, 0.0),
                    rotation: wall_rotation,
                    scale: Vec3::new(1.0, 1.0, 1.02),
                },
                ..default()
            },
            WallMeshChild {
                parent_wall,
                face: WallFace::Exterior,
            },
        ))
        .id();

    commands
        .entity(parent_wall)
        .push_children(&[interior, exterior]);
}
