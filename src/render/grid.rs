use bevy::prelude::*;

pub struct GridPlugin;

impl Plugin for GridPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<GridOverlay>()
            .register_type::<GroundPlane>()
            .add_systems(Startup, (spawn_ground_plane, spawn_grid_overlay))
            .add_systems(Update, toggle_grid_visibility);
    }
}

/// Marker for the ground plane entity.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct GroundPlane;

/// The buildable grid overlay.
#[derive(Component, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct GridOverlay {
    pub visible: bool,
    pub cell_size: f32,
    pub half_extents: f32,
}

impl Default for GridOverlay {
    fn default() -> Self {
        Self {
            visible: true,
            cell_size: 1.0,
            half_extents: 20.0,
        }
    }
}

fn spawn_ground_plane(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    let texture: Handle<Image> = asset_server.load("textures/terrain_grass.png");
    let size = 40.0;
    commands.spawn((
        PbrBundle {
            mesh: meshes.add(Plane3d::default().mesh().size(size, size)),
            material: materials.add(StandardMaterial {
                base_color_texture: Some(texture),
                perceptual_roughness: 0.85,
                ..default()
            }),
            transform: Transform::from_translation(Vec3::new(size / 2.0, 0.0, size / 2.0)),
            ..default()
        },
        GroundPlane,
    ));
}

fn spawn_grid_overlay(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let grid = GridOverlay::default();
    let half = grid.half_extents;
    let mut positions = Vec::new();

    // Vertical lines along the X axis.
    for i in 0..=(half as i32 * 2) {
        let x = i as f32 - half;
        positions.push([x, 0.01, -half]);
        positions.push([x, 0.01, half]);
    }

    // Horizontal lines along the Z axis.
    for i in 0..=(half as i32 * 2) {
        let z = i as f32 - half;
        positions.push([-half, 0.01, z]);
        positions.push([half, 0.01, z]);
    }

    let mut mesh = Mesh::new(
        bevy::render::mesh::PrimitiveTopology::LineList,
        bevy::render::render_asset::RenderAssetUsages::all(),
    );
    mesh.insert_attribute(Mesh::ATTRIBUTE_POSITION, positions);

    commands.spawn((
        PbrBundle {
            mesh: meshes.add(mesh),
            material: materials.add(StandardMaterial {
                base_color: Color::srgb(0.15, 0.25, 0.15),
                unlit: true,
                ..default()
            }),
            ..default()
        },
        grid,
    ));
}

fn toggle_grid_visibility(
    mut grid_query: Query<(&mut GridOverlay, &mut Visibility)>,
    keyboard: Res<ButtonInput<KeyCode>>,
) {
    if keyboard.just_pressed(KeyCode::KeyG) {
        for (mut grid, mut visibility) in grid_query.iter_mut() {
            grid.visible = !grid.visible;
            *visibility = if grid.visible {
                Visibility::Visible
            } else {
                Visibility::Hidden
            };
        }
    }
}
