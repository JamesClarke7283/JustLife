use bevy::prelude::*;

use crate::render::primitives::MeshGenerator;

/// A door placed in a wall segment.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Door {
    pub position: Vec2,
    pub rotation: f32,
    pub locked: bool,
    pub open: bool,
    pub wall_segment: Option<Entity>,
    pub connected_rooms: [Option<Entity>; 2],
    pub width: f32,
    pub height: f32,
}

impl Door {
    /// Create a new door at a position along a wall.
    pub fn new(position: Vec2, rotation: f32) -> Self {
        Self {
            position,
            rotation,
            locked: false,
            open: false,
            wall_segment: None,
            connected_rooms: [None, None],
            width: 1.0,
            height: 2.2,
        }
    }

    /// Snap the door position to the nearest grid unit.
    pub fn snapped(position: Vec2, rotation: f32) -> Self {
        Self::new(crate::world::wall::snap_to_grid(position), rotation)
    }

    /// Toggle the open/closed state. Locked doors cannot be opened.
    pub fn toggle(&mut self) -> bool {
        if self.locked && !self.open {
            return false;
        }
        self.open = !self.open;
        true
    }
}

/// Marker for a visual door mesh child so it can be rebuilt/updated.
#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct DoorMeshChild {
    pub parent_door: Entity,
}

/// Marker that a door needs its visual mesh rebuilt.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct DoorVisualDirty;

/// Rebuild visual meshes for any door marked as dirty.
#[allow(clippy::too_many_arguments)]
pub fn update_door_visuals(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
    doors: Query<(Entity, &Door, &DoorVisualDirty)>,
    existing: Query<Entity, With<DoorMeshChild>>,
) {
    for (entity, door, _) in doors.iter() {
        // Despawn old visual children for this door.
        for child in existing.iter() {
            commands.entity(child).despawn_recursive();
        }

        build_door_visuals(
            &mut commands,
            &mut meshes,
            &mut materials,
            &asset_server,
            entity,
            door,
        );

        commands.entity(entity).remove::<DoorVisualDirty>();
    }
}

/// Build or rebuild the visual meshes for a door entity.
pub fn build_door_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    asset_server: &AssetServer,
    door_entity: Entity,
    door: &Door,
) {
    let frame_texture: Handle<Image> = asset_server.load("textures/door_frame_white.png");
    let panel_texture: Handle<Image> = asset_server.load("textures/door_wood_oak.png");

    let frame_material = materials.add(StandardMaterial {
        base_color_texture: Some(frame_texture),
        perceptual_roughness: 0.85,
        ..default()
    });
    let panel_material = materials.add(StandardMaterial {
        base_color_texture: Some(panel_texture),
        perceptual_roughness: 0.7,
        ..default()
    });

    let frame_thickness = 0.08;
    let frame_depth = 0.2;
    let panel_thickness = 0.04;

    let frame_width = door.width + frame_thickness * 2.0;
    let frame_height = door.height + frame_thickness * 2.0;

    let position_3d = door.position.extend(0.0);
    let yaw = Quat::from_rotation_y(-door.rotation);

    // Door frame (top, bottom, left, right) built from thin boxes.
    let top = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(MeshGenerator::cube(1.0)),
                material: frame_material.clone(),
                transform: Transform {
                    translation: Vec3::new(0.0, frame_height / 2.0 - frame_thickness / 2.0, 0.0),
                    rotation: Quat::IDENTITY,
                    scale: Vec3::new(frame_width, frame_thickness, frame_depth),
                },
                ..default()
            },
            DoorMeshChild {
                parent_door: door_entity,
            },
        ))
        .id();

    let bottom = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(MeshGenerator::cube(1.0)),
                material: frame_material.clone(),
                transform: Transform {
                    translation: Vec3::new(0.0, frame_thickness / 2.0, 0.0),
                    rotation: Quat::IDENTITY,
                    scale: Vec3::new(frame_width, frame_thickness, frame_depth),
                },
                ..default()
            },
            DoorMeshChild {
                parent_door: door_entity,
            },
        ))
        .id();

    let left = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(MeshGenerator::cube(1.0)),
                material: frame_material.clone(),
                transform: Transform {
                    translation: Vec3::new(
                        -door.width / 2.0 - frame_thickness / 2.0,
                        door.height / 2.0 + frame_thickness / 2.0,
                        0.0,
                    ),
                    rotation: Quat::IDENTITY,
                    scale: Vec3::new(frame_thickness, door.height, frame_depth),
                },
                ..default()
            },
            DoorMeshChild {
                parent_door: door_entity,
            },
        ))
        .id();

    let right = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(MeshGenerator::cube(1.0)),
                material: frame_material.clone(),
                transform: Transform {
                    translation: Vec3::new(
                        door.width / 2.0 + frame_thickness / 2.0,
                        door.height / 2.0 + frame_thickness / 2.0,
                        0.0,
                    ),
                    rotation: Quat::IDENTITY,
                    scale: Vec3::new(frame_thickness, door.height, frame_depth),
                },
                ..default()
            },
            DoorMeshChild {
                parent_door: door_entity,
            },
        ))
        .id();

    // Door panel (swings open/closed around one side).
    let panel = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(MeshGenerator::cube(1.0)),
                material: panel_material,
                transform: Transform {
                    translation: Vec3::new(-door.width / 2.0, door.height / 2.0, 0.0),
                    rotation: Quat::IDENTITY,
                    scale: Vec3::new(door.width, door.height, panel_thickness),
                },
                ..default()
            },
            DoorMeshChild {
                parent_door: door_entity,
            },
        ))
        .id();

    commands
        .entity(door_entity)
        // SpatialBundle (not bare Transform) so the parent has GlobalTransform +
        // visibility components; otherwise its mesh children never render (B0004).
        .insert(SpatialBundle::from_transform(Transform {
            translation: position_3d + Vec3::new(0.0, 0.0, 0.0),
            rotation: yaw,
            scale: Vec3::ONE,
        }))
        .push_children(&[top, bottom, left, right, panel]);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn door_defaults() {
        let door = Door::new(Vec2::new(1.0, 2.0), 0.0);
        assert!(!door.locked);
        assert!(!door.open);
        assert_eq!(door.width, 1.0);
        assert_eq!(door.height, 2.2);
    }

    #[test]
    fn locked_door_cannot_open() {
        let mut door = Door::new(Vec2::ZERO, 0.0);
        door.locked = true;
        assert!(!door.toggle());
        assert!(!door.open);
    }

    #[test]
    fn unlocked_door_toggles() {
        let mut door = Door::new(Vec2::ZERO, 0.0);
        assert!(door.toggle());
        assert!(door.open);
        assert!(door.toggle());
        assert!(!door.open);
    }
}
