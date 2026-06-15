use bevy::prelude::*;

use crate::render::camera::{CameraRig, IsometricCamera};
use crate::render::primitives::MeshGenerator;

pub mod door;
pub mod wall;
pub mod wall_tool;
pub mod wall_visuals;
pub mod window;

pub struct WorldPlugin;

/// A neighborhood is a collection of lots. Only one is active at a time.
#[derive(Resource, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct Neighborhood {
    pub lots: Vec<Entity>,
    pub active_lot: Option<Entity>,
}

impl Neighborhood {
    /// Register a lot entity and optionally activate it.
    pub fn register_lot(&mut self, entity: Entity, make_active: bool) {
        self.lots.push(entity);
        if make_active || self.active_lot.is_none() {
            self.active_lot = Some(entity);
        }
    }

    /// Activate an already-registered lot.
    pub fn set_active(&mut self, entity: Entity) {
        if self.lots.contains(&entity) {
            self.active_lot = Some(entity);
        }
    }
}

/// Spawn a simple textured demo object so textures-on-primitives can be verified.
fn spawn_demo_objects(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    let texture: Handle<Image> = asset_server.load("textures/furniture_wood_oak.png");
    commands.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::cube(0.5)),
        material: materials.add(StandardMaterial {
            base_color_texture: Some(texture),
            perceptual_roughness: 0.85,
            ..default()
        }),
        transform: Transform::from_xyz(2.0, 0.25, 2.0),
        ..default()
    });

    // Add a demo indoor point light so the point-light path can be verified.
    crate::render::lighting::spawn_indoor_light(
        &mut commands,
        Vec3::new(0.0, 2.5, 0.0),
        Color::srgb(1.0, 0.95, 0.8),
        1_000.0,
    );
}

impl Plugin for WorldPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<LotManager>()
            .init_resource::<Neighborhood>()
            .init_resource::<wall_tool::WallToolState>()
            .register_type::<Lot>()
            .register_type::<LotId>()
            .register_type::<LotBoundary>()
            .register_type::<Neighborhood>()
            .register_type::<wall::Wall>()
            .register_type::<door::Door>()
            .register_type::<window::Window>()
            .register_type::<Room>()
            .register_type::<PlacedObject>()
            .add_systems(
                Startup,
                (spawn_demo_lots, spawn_demo_walls, spawn_demo_objects),
            )
            .add_systems(
                Update,
                (wall_visuals::update_wall_visuals, wall_cutaway, select_lot),
            );
    }
}

/// Global manager for all placed lots in the active save.
#[derive(Resource, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct LotManager {
    pub lots: Vec<Entity>,
    pub active: Option<Entity>,
}

impl LotManager {
    /// Register a lot entity and optionally make it the active lot.
    pub fn register_lot(&mut self, entity: Entity, make_active: bool) {
        self.lots.push(entity);
        if make_active {
            self.active = Some(entity);
        }
    }

    /// Set the active lot if the entity is known.
    pub fn set_active(&mut self, entity: Entity) {
        if self.lots.contains(&entity) {
            self.active = Some(entity);
        }
    }
}

/// A buildable lot in the neighborhood.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect)]
#[reflect(Component)]
pub struct LotId(pub u32);

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Lot {
    pub lot_id: LotId,
    pub name: String,
    pub position: Vec2,
    pub width: f32,
    pub depth: f32,
    pub value: u32,
    pub owner: Option<String>,
}

impl Lot {
    /// Create a new lot descriptor.
    pub fn new(
        lot_id: u32,
        name: &str,
        position: Vec2,
        width: f32,
        depth: f32,
        value: u32,
    ) -> Self {
        Self {
            lot_id: LotId(lot_id),
            name: name.to_string(),
            position,
            width,
            depth,
            value,
            owner: None,
        }
    }

    /// Axis-aligned bounding rectangle in world space.
    pub fn bounds(&self) -> (Vec2, Vec2) {
        let half = Vec2::new(self.width / 2.0, self.depth / 2.0);
        (self.position - half, self.position + half)
    }

    /// Returns true if the given world XZ point lies inside the lot.
    pub fn contains(&self, point: Vec2) -> bool {
        let (min, max) = self.bounds();
        point.x >= min.x && point.x <= max.x && point.y >= min.y && point.y <= max.y
    }

    /// Assign an owner to this lot.
    pub fn set_owner(&mut self, owner: &str) {
        self.owner = Some(owner.to_string());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lot_bounds_centered_on_position() {
        let lot = Lot::new(0, "Test", Vec2::new(5.0, 5.0), 4.0, 6.0, 1_000);
        let (min, max) = lot.bounds();
        assert!((min - Vec2::new(3.0, 2.0)).length() < 0.0001);
        assert!((max - Vec2::new(7.0, 8.0)).length() < 0.0001);
    }

    #[test]
    fn lot_contains_inside_and_outside() {
        let lot = Lot::new(1, "Test", Vec2::ZERO, 4.0, 4.0, 1_000);
        assert!(lot.contains(Vec2::new(0.0, 0.0)));
        assert!(lot.contains(Vec2::new(1.9, 1.9)));
        assert!(!lot.contains(Vec2::new(2.1, 0.0)));
        assert!(!lot.contains(Vec2::new(0.0, 2.1)));
    }

    #[test]
    fn lot_owner_can_be_set() {
        let mut lot = Lot::new(2, "Owned", Vec2::ZERO, 10.0, 10.0, 5_000);
        assert!(lot.owner.is_none());
        lot.set_owner("The Johnsons");
        assert_eq!(lot.owner.as_deref(), Some("The Johnsons"));
    }

    #[test]
    fn neighborhood_tracks_active_lot() {
        let mut neighborhood = Neighborhood::default();
        let dummy_a = Entity::from_raw(1);
        let dummy_b = Entity::from_raw(2);
        neighborhood.register_lot(dummy_a, false);
        neighborhood.register_lot(dummy_b, false);
        assert_eq!(neighborhood.active_lot, Some(dummy_a));
        neighborhood.set_active(dummy_b);
        assert_eq!(neighborhood.active_lot, Some(dummy_b));
    }

    #[test]
    fn neighborhood_rejects_unknown_lot() {
        let mut neighborhood = Neighborhood::default();
        neighborhood.register_lot(Entity::from_raw(1), false);
        neighborhood.set_active(Entity::from_raw(99));
        assert_ne!(neighborhood.active_lot, Some(Entity::from_raw(99)));
    }
}

/// Marker for the visible boundary outline of a lot.
#[derive(Component, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct LotBoundary {
    pub parent_lot: Entity,
}

impl Default for LotBoundary {
    fn default() -> Self {
        Self {
            parent_lot: Entity::PLACEHOLDER,
        }
    }
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

fn spawn_demo_lots(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut lot_manager: ResMut<LotManager>,
    mut neighborhood: ResMut<Neighborhood>,
) {
    let lot_specs = [
        Lot::new(0, "Starter Lot", Vec2::new(0.0, 0.0), 10.0, 10.0, 5_000),
        Lot::new(1, "Empty Lot", Vec2::new(15.0, 0.0), 10.0, 10.0, 3_000),
    ];

    for lot in lot_specs {
        let entity = spawn_lot(&mut commands, &mut meshes, &mut materials, lot);
        let make_active = neighborhood.active_lot.is_none();
        lot_manager.register_lot(entity, make_active);
        neighborhood.register_lot(entity, make_active);
    }
}

/// Spawn a lot entity and its visible boundary outline.
pub fn spawn_lot(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    lot: Lot,
) -> Entity {
    let (min, max) = lot.bounds();
    let corners = [
        Vec3::new(min.x, 0.05, min.y),
        Vec3::new(max.x, 0.05, min.y),
        Vec3::new(max.x, 0.05, max.y),
        Vec3::new(min.x, 0.05, max.y),
        Vec3::new(min.x, 0.05, min.y),
    ];

    let mut positions = Vec::with_capacity(corners.len() * 3);
    for corner in corners {
        positions.push([corner.x, corner.y, corner.z]);
    }

    let mut mesh = Mesh::new(
        bevy::render::mesh::PrimitiveTopology::LineStrip,
        bevy::render::render_asset::RenderAssetUsages::all(),
    );
    mesh.insert_attribute(Mesh::ATTRIBUTE_POSITION, positions);

    let boundary_entity = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(mesh),
                material: materials.add(StandardMaterial {
                    base_color: Color::srgb(0.9, 0.7, 0.2),
                    unlit: true,
                    ..default()
                }),
                ..default()
            },
            LotBoundary {
                parent_lot: Entity::PLACEHOLDER,
            },
            Name::new(format!("{} Boundary", lot.name)),
        ))
        .id();

    let position = lot.position.extend(0.0);
    let lot_entity = commands
        .spawn((
            lot,
            Transform::from_translation(position),
            GlobalTransform::default(),
        ))
        .push_children(&[boundary_entity])
        .id();

    commands.entity(boundary_entity).insert(LotBoundary {
        parent_lot: lot_entity,
    });

    lot_entity
}

fn spawn_demo_walls(mut commands: Commands) {
    let wall_specs = [
        (Vec2::new(-5.0, -5.0), Vec2::new(5.0, -5.0)),
        (Vec2::new(5.0, -5.0), Vec2::new(5.0, 5.0)),
        (Vec2::new(5.0, 5.0), Vec2::new(-5.0, 5.0)),
        (Vec2::new(-5.0, 5.0), Vec2::new(-5.0, -5.0)),
    ];

    for (start, end) in wall_specs {
        commands.spawn((
            wall::Wall::new(start, end),
            wall::WallVisualDirty,
            Name::new("Wall"),
        ));
    }
}

/// Select a lot when the player clicks inside its boundary or on its outline.
/// This is the world-view entry point for entering a lot.
fn select_lot(
    mouse_button: Res<ButtonInput<MouseButton>>,
    windows: Query<&bevy::window::Window>,
    cameras: Query<(&Camera, &GlobalTransform)>,
    lots: Query<(Entity, &Lot, &GlobalTransform)>,
    mut lot_manager: ResMut<LotManager>,
    mut neighborhood: ResMut<Neighborhood>,
    mut camera_rigs: Query<&mut CameraRig, With<IsometricCamera>>,
) {
    if !mouse_button.just_pressed(MouseButton::Left) {
        return;
    }
    let Ok(window) = windows.get_single() else {
        return;
    };
    let Some(cursor) = window.cursor_position() else {
        return;
    };
    let Ok((camera, camera_transform)) = cameras.get_single() else {
        return;
    };

    // Use the existing raycast from the camera to find a point on the ground plane (Y=0).
    let Some(ray) = camera.viewport_to_world(camera_transform, cursor) else {
        return;
    };

    // Intersect the ray with the ground plane y=0.
    let Some(distance) = ray.intersect_plane(Vec3::ZERO, InfinitePlane3d::new(Vec3::Y)) else {
        return;
    };
    let hit = ray.get_point(distance);
    let point2 = hit.xz();

    // Prefer clicking directly on a boundary mesh; otherwise fall back to the lot bounds.
    for (entity, lot, _global) in lots.iter() {
        if lot.contains(point2) {
            lot_manager.set_active(entity);
            neighborhood.set_active(entity);

            // Move the camera focus to the selected lot so the player "enters" it.
            if let Ok(mut rig) = camera_rigs.get_single_mut() {
                rig.follow_mode = false;
                let target = lot.position.extend(0.0);
                rig.target = target;
            }
            break;
        }
    }
}

/// Wall cutaway: walls between the camera and the focal target become transparent
/// when the camera is inside a room, simulating classic isometric interior views.
fn wall_cutaway(
    mut wall_children: Query<(
        &mut Visibility,
        &mut Handle<StandardMaterial>,
        &wall::WallMeshChild,
        &GlobalTransform,
    )>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    camera_query: Query<
        (&Transform, &crate::render::camera::CameraRig),
        With<crate::render::camera::IsometricCamera>,
    >,
    walls: Query<&wall::Wall>,
) {
    let Ok((camera_transform, rig)) = camera_query.get_single() else {
        return;
    };

    let camera_pos = camera_transform.translation;
    let target_pos = rig.target;
    let camera_inside = camera_pos.y < 3.0 && (target_pos - camera_pos).length() < 8.0;

    for (mut visibility, material_handle, child, _transform) in wall_children.iter_mut() {
        let Ok(wall) = walls.get(child.parent_wall) else {
            continue;
        };

        let mid = (wall.start + wall.end).extend(0.0) / 2.0;
        let wall_to_camera = camera_pos.xz() - mid.xz();
        let distance = wall_to_camera.length();

        // Hide walls very close to the camera (full walls down).
        if distance < 1.5 {
            *visibility = Visibility::Hidden;
            continue;
        }

        // Cutaway: fade or hide walls between the camera and focal point.
        if camera_inside {
            let wall_to_target = target_pos.xz() - mid.xz();
            let same_side = wall_to_camera.dot(wall_to_target) > 0.0;
            if same_side && distance < 6.0 {
                if let Some(material) = materials.get_mut(&*material_handle) {
                    material.base_color.set_alpha(0.25);
                }
                *visibility = Visibility::Visible;
                continue;
            }
        }

        if let Some(material) = materials.get_mut(&*material_handle) {
            material.base_color.set_alpha(1.0);
        }
        *visibility = Visibility::Visible;
    }
}
