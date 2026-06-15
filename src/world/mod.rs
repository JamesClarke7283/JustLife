use bevy::prelude::*;

use crate::render::primitives::MeshGenerator;

pub struct WorldPlugin;

impl Plugin for WorldPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<LotManager>()
            .register_type::<Lot>()
            .register_type::<Wall>()
            .register_type::<Door>()
            .register_type::<Window>()
            .register_type::<Room>()
            .register_type::<PlacedObject>()
            .add_systems(Startup, spawn_demo_walls)
            .add_systems(Update, (update_wall_visuals, wall_cutaway));
    }
}

#[derive(Resource, Default, Debug)]
pub struct LotManager {
    pub lots: Vec<Entity>,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Lot {
    pub name: String,
    pub position: Vec2,
    pub width: f32,
    pub depth: f32,
    pub value: u32,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Wall {
    pub start: Vec2,
    pub end: Vec2,
    pub height: f32,
    pub thickness: f32,
}

/// Marker that a wall needs its visual mesh rebuilt.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct WallVisualDirty;

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Door {
    pub locked: bool,
    pub connected_rooms: [Option<Entity>; 2],
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Window {
    pub wall_segment: Option<Entity>,
    pub allows_light: bool,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Room {
    pub name: String,
    pub area: f32,
    pub indoor: bool,
    pub floor_material: String,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct PlacedObject {
    pub catalog_id: String,
    pub position: Vec3,
    pub rotation: Quat,
    pub condition: ObjectCondition,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum ObjectCondition {
    #[default]
    Clean,
    Dirty,
    Broken,
}

fn spawn_demo_walls(
    mut commands: Commands,
) {
    let wall_specs = [
        (Vec2::new(-5.0, -5.0), Vec2::new(5.0, -5.0)),
        (Vec2::new(5.0, -5.0), Vec2::new(5.0, 5.0)),
        (Vec2::new(5.0, 5.0), Vec2::new(-5.0, 5.0)),
        (Vec2::new(-5.0, 5.0), Vec2::new(-5.0, -5.0)),
    ];

    for (start, end) in wall_specs {
        commands.spawn((
            Wall {
                start,
                end,
                height: 3.0,
                thickness: 0.15,
            },
            WallVisualDirty,
        ));
    }
}

fn update_wall_visuals(
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
        // Remove previous child meshes if any.
        for child in existing.iter() {
            commands.entity(child).despawn_recursive();
        }

        let mid = (wall.start + wall.end).extend(0.0) / 2.0;
        let delta = wall.end - wall.start;
        let length = delta.length();
        let angle = delta.y.atan2(delta.x);
        let rotation = Quat::from_rotation_y(-angle);

        // Interior face.
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
                WallMeshChild { parent_wall: entity, face: WallFace::Interior },
            ))
            .id();

        // Exterior face (slightly offset outward so it doesn't z-fight).
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
                WallMeshChild { parent_wall: entity, face: WallFace::Exterior },
            ))
            .id();

        commands
            .entity(entity)
            .push_children(&[interior, exterior])
            .remove::<WallVisualDirty>();
    }
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
struct WallMeshChild {
    parent_wall: Entity,
    face: WallFace,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
enum WallFace {
    Interior,
    Exterior,
}

/// Simple wall cutaway: fade out walls between camera and focal point when camera is close.
fn wall_cutaway(
    mut wall_children: Query<(&mut Visibility,
        &WallMeshChild,
        &GlobalTransform,
    )>,
    camera_query: Query<&Transform, With<crate::render::camera::IsometricCamera>>,
    walls: Query<&Wall>,
) {
    let Ok(camera_transform) = camera_query.get_single() else {
        return;
    };

    let camera_pos = camera_transform.translation;

    for (mut visibility, child, _transform) in wall_children.iter_mut() {
        let Ok(wall) = walls.get(child.parent_wall) else {
            continue;
        };

        // Use the wall segment midpoint in XZ as a rough test point.
        let mid = (wall.start + wall.end).extend(0.0) / 2.0;
        let distance = (camera_pos.xz() - mid.xz()).length();

        // Hide walls that are very close to the camera.
        if distance < 2.0 {
            *visibility = Visibility::Hidden;
        } else {
            *visibility = Visibility::Visible;
        }
    }
}
