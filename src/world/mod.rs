use bevy::prelude::*;

use crate::render::camera::{CameraRig, IsometricCamera};
use crate::render::primitives::MeshGenerator;

pub mod catalog;
pub mod door;
pub mod placed;
pub mod room;
pub mod terrain;
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

/// Spawn a single coloured box at `pos` (Y is the box centre height) sized `size`.
fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    size: Vec3,
    pos: Vec3,
    color: Color,
    name: &'static str,
) {
    commands.spawn((
        PbrBundle {
            mesh: meshes.add(Cuboid::new(size.x, size.y, size.z)),
            material: materials.add(StandardMaterial {
                base_color: color,
                perceptual_roughness: 0.8,
                ..default()
            }),
            transform: Transform::from_translation(pos),
            ..default()
        },
        Name::new(name),
    ));
}

/// Spawn a single textured box at `pos` (Y is the box centre height) sized `size`.
#[allow(clippy::too_many_arguments)]
fn spawn_textured_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    asset_server: &AssetServer,
    size: Vec3,
    pos: Vec3,
    texture_path: &'static str,
    name: &'static str,
) {
    let texture: Handle<Image> = asset_server.load(texture_path);
    commands.spawn((
        PbrBundle {
            mesh: meshes.add(Cuboid::new(size.x, size.y, size.z)),
            material: materials.add(StandardMaterial {
                base_color_texture: Some(texture),
                perceptual_roughness: 0.8,
                ..default()
            }),
            transform: Transform::from_translation(pos),
            ..default()
        },
        Name::new(name),
    ));
}

/// Furnish the starter room with simple primitive furniture so the lot reads as
/// a lived-in home. The room interior spans roughly -4.5..4.5 on X and Z.
fn spawn_demo_objects(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    let m = &mut *meshes;
    let mat = &mut *materials;
    let assets = &*asset_server;

    let wood = Color::srgb(0.45, 0.30, 0.18);
    let wood_light = Color::srgb(0.55, 0.38, 0.22);
    let metal = Color::srgb(0.82, 0.84, 0.87);

    // Area rug centred in the room.
    spawn_textured_box(
        &mut commands,
        m,
        mat,
        assets,
        Vec3::new(4.0, 0.02, 3.0),
        Vec3::new(0.0, 0.05, 0.0),
        "textures/rug_pattern.png",
        "Rug",
    );

    // --- Bedroom corner (-X, -Z) ---
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(2.0, 0.4, 3.0),
        Vec3::new(-3.2, 0.2, -3.0),
        wood,
        "Bed Frame",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(1.8, 0.25, 2.8),
        Vec3::new(-3.2, 0.5, -3.0),
        Color::srgb(0.90, 0.92, 0.96),
        "Mattress",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(1.6, 0.18, 0.6),
        Vec3::new(-3.2, 0.7, -4.0),
        Color::srgb(0.95, 0.85, 0.55),
        "Pillow",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(0.7, 0.7, 0.7),
        Vec3::new(-1.8, 0.35, -4.2),
        wood_light,
        "Nightstand",
    );

    // --- Kitchen run (-X wall, +Z) ---
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(1.0, 1.8, 0.9),
        Vec3::new(-4.0, 0.9, 4.0),
        metal,
        "Fridge",
    );
    spawn_textured_box(
        &mut commands,
        m,
        mat,
        assets,
        Vec3::new(2.4, 0.9, 0.9),
        Vec3::new(-2.4, 0.45, 4.1),
        "textures/counter_granite.png",
        "Counter",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(0.6, 0.6, 0.6),
        Vec3::new(-2.0, 1.2, 4.1),
        Color::srgb(0.15, 0.15, 0.18),
        "Microwave",
    );

    // --- Dining set (+X, +Z) ---
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(1.8, 0.12, 1.0),
        Vec3::new(3.0, 0.75, 3.0),
        wood_light,
        "Table Top",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(0.4, 0.75, 0.4),
        Vec3::new(3.0, 0.375, 3.0),
        wood,
        "Table Pedestal",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(0.5, 0.9, 0.5),
        Vec3::new(3.0, 0.45, 2.0),
        wood_light,
        "Chair A",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(0.5, 0.9, 0.5),
        Vec3::new(3.0, 0.45, 4.0),
        wood_light,
        "Chair B",
    );

    // --- Living area (+X, -Z) ---
    spawn_textured_box(
        &mut commands,
        m,
        mat,
        assets,
        Vec3::new(2.8, 0.5, 1.0),
        Vec3::new(2.6, 0.3, -2.2),
        "textures/fabric_sofa_blue.png",
        "Sofa Seat",
    );
    spawn_textured_box(
        &mut commands,
        m,
        mat,
        assets,
        Vec3::new(2.8, 0.7, 0.25),
        Vec3::new(2.6, 0.6, -1.6),
        "textures/fabric_sofa_blue.png",
        "Sofa Back",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(2.0, 0.5, 0.5),
        Vec3::new(2.6, 0.25, -4.0),
        Color::srgb(0.30, 0.22, 0.18),
        "TV Stand",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(1.8, 1.0, 0.12),
        Vec3::new(2.6, 1.0, -4.1),
        Color::srgb(0.04, 0.04, 0.07),
        "TV Screen",
    );
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(1.2, 0.1, 0.7),
        Vec3::new(2.6, 0.45, -3.0),
        wood_light,
        "Coffee Table",
    );

    // --- Bookshelf along +X area ---
    spawn_textured_box(
        &mut commands,
        m,
        mat,
        assets,
        Vec3::new(0.4, 2.0, 1.4),
        Vec3::new(4.2, 1.0, 0.0),
        "textures/bookshelf_books.png",
        "Bookshelf",
    );

    // Floor lamp: pole + glowing shade.
    spawn_box(
        &mut commands,
        m,
        mat,
        Vec3::new(0.1, 1.6, 0.1),
        Vec3::new(4.0, 0.8, -3.8),
        Color::srgb(0.2, 0.2, 0.2),
        "Lamp Pole",
    );
    commands.spawn((
        PbrBundle {
            mesh: m.add(MeshGenerator::cone(0.35, 0.4, 16)),
            material: mat.add(StandardMaterial {
                base_color: Color::srgb(1.0, 0.95, 0.7),
                emissive: LinearRgba::rgb(0.8, 0.7, 0.4),
                ..default()
            }),
            transform: Transform::from_xyz(4.0, 1.7, -3.8),
            ..default()
        },
        Name::new("Lamp Shade"),
    ));

    // Indoor point lights so the room is well lit at night.
    crate::render::lighting::spawn_indoor_light(
        &mut commands,
        Vec3::new(0.0, 2.8, 0.0),
        Color::srgb(1.0, 0.95, 0.8),
        1_500.0,
    );
    crate::render::lighting::spawn_indoor_light(
        &mut commands,
        Vec3::new(4.0, 1.8, -3.8),
        Color::srgb(1.0, 0.92, 0.7),
        600.0,
    );
}

/// Place a few objects straight from the data-driven catalog, exercising the
/// catalog -> primitive builder end to end.
fn spawn_demo_catalog_props(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    catalog: Res<catalog::CatalogDatabase>,
) {
    let placements = [
        ("plant_potted", Vec3::new(3.9, 0.0, 3.6)),
        ("plant_potted", Vec3::new(-4.0, 0.0, 1.6)),
        ("floor_lamp", Vec3::new(-4.2, 0.0, -1.2)),
        // Outdoor landscaping around the lot.
        ("tree_oak", Vec3::new(8.0, 0.0, 7.0)),
        ("tree_oak", Vec3::new(-8.0, 0.0, 6.0)),
        ("bush_round", Vec3::new(-3.0, 0.0, 7.0)),
        ("bush_round", Vec3::new(3.0, 0.0, 7.0)),
        ("bush_round", Vec3::new(7.0, 0.0, -4.0)),
        ("bush_round", Vec3::new(8.0, 0.0, -4.0)),
        ("pool_small", Vec3::new(-8.5, 0.0, -0.5)),
    ];
    for (id, pos) in placements {
        if let Some(item) = catalog.get(id) {
            catalog::spawn_catalog_item(
                &mut commands,
                &mut meshes,
                &mut materials,
                item,
                pos,
                Quat::IDENTITY,
            );
        }
    }
}

impl Plugin for WorldPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((placed::PlacedObjectPlugin, terrain::TerrainPlugin))
            .init_resource::<LotManager>()
            .init_resource::<Neighborhood>()
            .init_resource::<wall_tool::WallToolState>()
            .init_resource::<catalog::CatalogDatabase>()
            .register_type::<Lot>()
            .register_type::<LotId>()
            .register_type::<LotBoundary>()
            .register_type::<Neighborhood>()
            .register_type::<wall::Wall>()
            .register_type::<door::Door>()
            .register_type::<door::DoorVisualDirty>()
            .register_type::<door::DoorMeshChild>()
            .register_type::<window::Window>()
            .register_type::<window::WindowVisualDirty>()
            .register_type::<window::WindowMeshChild>()
            .register_type::<Room>()
            .register_type::<PlacedObject>()
            .register_type::<room::RoomFloor>()
            .register_type::<catalog::CatalogCategory>()
            .register_type::<catalog::PrimitiveShape>()
            .register_type::<catalog::PrimitivePart>()
            .register_type::<catalog::ObjectAction>()
            .register_type::<catalog::CatalogItem>()
            .add_systems(
                Startup,
                (
                    spawn_demo_lots,
                    spawn_demo_walls,
                    spawn_demo_openings,
                    spawn_demo_objects,
                ),
            )
            // Room detection must run after the Startup commands that spawn the
            // lots and walls have been applied, otherwise its queries see nothing
            // and no floor is created.
            .add_systems(PostStartup, (spawn_demo_rooms, spawn_demo_catalog_props))
            .add_systems(
                Update,
                (
                    wall_visuals::update_wall_visuals,
                    door::update_door_visuals,
                    window::update_window_visuals,
                    wall_cutaway,
                    select_lot,
                ),
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
    /// Grid footprint in cells (width, depth) from the catalog item.
    pub footprint: (u32, u32),
    /// Power state for electronics/appliances (ignored by passive objects).
    pub powered: bool,
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

    let position = Vec3::new(lot.position.x, 0.0, lot.position.y);
    let lot_entity = commands
        .spawn((
            lot,
            // SpatialBundle (Transform + GlobalTransform + visibility) so the
            // boundary mesh child renders (avoids B0004).
            SpatialBundle::from_transform(Transform::from_translation(position)),
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
            // Parent needs GlobalTransform + visibility so its mesh children
            // (spawned by update_wall_visuals) render (avoids B0004).
            SpatialBundle::default(),
        ));
    }
}

fn spawn_demo_openings(mut commands: Commands, walls: Query<(Entity, &wall::Wall)>) {
    // Place a door in the front wall (-5,-5) -> (5,-5) and a window in the right wall.
    for (wall_entity, wall) in walls.iter() {
        if wall.start == Vec2::new(-5.0, -5.0) && wall.end == Vec2::new(5.0, -5.0) {
            let mut door = door::Door::new(Vec2::new(0.0, -5.0), 0.0);
            door.wall_segment = Some(wall_entity);
            commands.spawn((door, door::DoorVisualDirty, Name::new("Door")));
            commands.entity(wall_entity).insert(wall::WallVisualDirty);
        } else if wall.start == Vec2::new(5.0, -5.0) && wall.end == Vec2::new(5.0, 5.0) {
            let mut window = window::Window::new(Vec2::new(5.0, 0.0), std::f32::consts::FRAC_PI_2);
            window.wall_segment = Some(wall_entity);
            commands.spawn((window, window::WindowVisualDirty, Name::new("Window")));
            commands.entity(wall_entity).insert(wall::WallVisualDirty);
        }
    }
}

/// After walls are spawned, auto-detect rooms on the active lot and create floor meshes.
fn spawn_demo_rooms(
    mut commands: Commands,
    walls: Query<&wall::Wall>,
    lots: Query<&Lot>,
    lot_manager: Res<LotManager>,
) {
    let Some(active_lot) = lot_manager.active else {
        return;
    };
    let Ok(lot) = lots.get(active_lot) else {
        return;
    };
    let (min, max) = lot.bounds();

    let wall_data: Vec<wall::Wall> = walls.iter().cloned().collect();
    commands.add(move |w: &mut World| {
        let walkable = room::compute_walkable_cells_from_iter(wall_data.iter(), min, max);
        let indoor = room::compute_indoor_cells(&walkable);
        let regions = room::flood_fill_regions(&indoor);

        for region in regions {
            let mut cmds = w.commands();
            cmds.add(room::spawn_room_floor_command(region));
        }
    });
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
                rig.target = Vec3::new(lot.position.x, 0.0, lot.position.y);
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

        let mp = (wall.start + wall.end) * 0.5;
        let mid = Vec3::new(mp.x, 0.0, mp.y);
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
