use bevy::prelude::*;

use crate::render::primitives::MeshGenerator;

/// A window placed in a wall segment.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Window {
    pub position: Vec2,
    pub rotation: f32,
    pub wall_segment: Option<Entity>,
    pub allows_light: bool,
    pub width: f32,
    pub height: f32,
}

impl Window {
    /// Create a new window at a position along a wall.
    pub fn new(position: Vec2, rotation: f32) -> Self {
        Self {
            position,
            rotation,
            wall_segment: None,
            allows_light: true,
            width: 1.2,
            height: 1.5,
        }
    }

    /// Snap the window position to the nearest grid unit.
    pub fn snapped(position: Vec2, rotation: f32) -> Self {
        Self::new(crate::world::wall::snap_to_grid(position), rotation)
    }
}

/// Marker for a visual window mesh child.
#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct WindowMeshChild {
    pub parent_window: Entity,
}

/// Marker that a window needs its visual mesh rebuilt.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct WindowVisualDirty;

/// Rebuild visual meshes for any window marked as dirty.
#[allow(clippy::too_many_arguments)]
pub fn update_window_visuals(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
    windows: Query<(Entity, &Window, &WindowVisualDirty)>,
    existing: Query<Entity, With<WindowMeshChild>>,
) {
    for (entity, window, _) in windows.iter() {
        // Despawn old visual children for this window.
        for child in existing.iter() {
            commands.entity(child).despawn_recursive();
        }

        build_window_visuals(
            &mut commands,
            &mut meshes,
            &mut materials,
            &asset_server,
            entity,
            window,
        );

        commands.entity(entity).remove::<WindowVisualDirty>();
    }
}

/// Build or rebuild the visual meshes for a window entity.
pub fn build_window_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    asset_server: &AssetServer,
    window_entity: Entity,
    window: &Window,
) {
    let frame_texture: Handle<Image> = asset_server.load("textures/door_frame_white.png");
    let glass_texture: Handle<Image> = asset_server.load("textures/window_glass.png");

    let frame_material = materials.add(StandardMaterial {
        base_color_texture: Some(frame_texture),
        perceptual_roughness: 0.85,
        ..default()
    });
    let glass_material = materials.add(StandardMaterial {
        base_color_texture: Some(glass_texture),
        perceptual_roughness: 0.1,
        metallic: 0.0,
        alpha_mode: AlphaMode::Blend,
        base_color: Color::srgba(0.85, 0.92, 1.0, 0.5),
        ..default()
    });

    let frame_thickness = 0.06;
    let frame_depth = 0.15;
    let glass_thickness = 0.02;

    let frame_width = window.width + frame_thickness * 2.0;
    let frame_height = window.height + frame_thickness * 2.0;

    let position_3d = Vec3::new(window.position.x, 0.0, window.position.y);
    let yaw = Quat::from_rotation_y(-window.rotation);

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
            WindowMeshChild {
                parent_window: window_entity,
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
            WindowMeshChild {
                parent_window: window_entity,
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
                        -window.width / 2.0 - frame_thickness / 2.0,
                        window.height / 2.0 + frame_thickness / 2.0,
                        0.0,
                    ),
                    rotation: Quat::IDENTITY,
                    scale: Vec3::new(frame_thickness, window.height, frame_depth),
                },
                ..default()
            },
            WindowMeshChild {
                parent_window: window_entity,
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
                        window.width / 2.0 + frame_thickness / 2.0,
                        window.height / 2.0 + frame_thickness / 2.0,
                        0.0,
                    ),
                    rotation: Quat::IDENTITY,
                    scale: Vec3::new(frame_thickness, window.height, frame_depth),
                },
                ..default()
            },
            WindowMeshChild {
                parent_window: window_entity,
            },
        ))
        .id();

    let glass = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(MeshGenerator::cube(1.0)),
                material: glass_material,
                transform: Transform {
                    translation: Vec3::new(0.0, window.height / 2.0 + frame_thickness / 2.0, 0.0),
                    rotation: Quat::IDENTITY,
                    scale: Vec3::new(window.width, window.height, glass_thickness),
                },
                ..default()
            },
            WindowMeshChild {
                parent_window: window_entity,
            },
        ))
        .id();

    commands
        .entity(window_entity)
        // SpatialBundle (not bare Transform) so the parent has GlobalTransform +
        // visibility components; otherwise its mesh children never render (B0004).
        .insert(SpatialBundle::from_transform(Transform {
            translation: position_3d,
            rotation: yaw,
            scale: Vec3::ONE,
        }))
        .push_children(&[top, bottom, left, right, glass]);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn window_defaults() {
        let window = Window::new(Vec2::new(1.0, 2.0), 0.0);
        assert!(window.allows_light);
        assert_eq!(window.width, 1.2);
        assert_eq!(window.height, 1.5);
    }
}
