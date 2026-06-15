use bevy::prelude::*;

use crate::render::primitives::MeshGenerator;
use crate::world::wall::{Wall, WallFace, WallMeshChild, WallVisualDirty};

/// Rebuild visual meshes for any wall marked as dirty.
pub fn update_wall_visuals(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
    walls: Query<(Entity, &Wall, &WallVisualDirty)>,
    existing: Query<Entity, With<WallMeshChild>>,
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
        for child in existing.iter() {
            commands.entity(child).despawn_recursive();
        }

        let mid = wall.midpoint().extend(0.0);
        let delta = wall.end - wall.start;
        let length = delta.length();
        let angle = delta.y.atan2(delta.x);
        let rotation = Quat::from_rotation_y(-angle);

        let interior_mesh = meshes.add(MeshGenerator::wall(length, wall.height, wall.thickness));
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

        commands
            .entity(entity)
            .push_children(&[interior, exterior])
            .remove::<WallVisualDirty>();
    }
}
