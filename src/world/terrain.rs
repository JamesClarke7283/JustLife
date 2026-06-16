use bevy::prelude::*;
use bevy::utils::HashMap;

/// Ground surface types that can be painted over the base grass terrain.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect, Default)]
pub enum TerrainType {
    #[default]
    Grass,
    Dirt,
    Concrete,
    PoolTile,
}

impl TerrainType {
    /// Every paintable surface, for build-mode tool buttons.
    pub const ALL: [TerrainType; 4] = [
        TerrainType::Grass,
        TerrainType::Dirt,
        TerrainType::Concrete,
        TerrainType::PoolTile,
    ];

    /// Texture used to render this surface.
    pub fn texture_path(&self) -> &'static str {
        match self {
            TerrainType::Grass => "textures/terrain_grass.png",
            TerrainType::Dirt => "textures/terrain_dirt.png",
            TerrainType::Concrete => "textures/terrain_concrete.png",
            TerrainType::PoolTile => "textures/terrain_pool_tile.png",
        }
    }

    /// Display label for UI.
    pub fn label(&self) -> &'static str {
        match self {
            TerrainType::Grass => "Grass",
            TerrainType::Dirt => "Dirt",
            TerrainType::Concrete => "Concrete",
            TerrainType::PoolTile => "Pool Tile",
        }
    }
}

/// Per-cell terrain overrides painted over the base grass ground. Grass cells
/// are the implicit default and are never stored.
#[derive(Resource, Default, Debug)]
pub struct TerrainGrid {
    cells: HashMap<(i32, i32), TerrainType>,
    /// Set when the grid changes so the render system rebuilds tiles.
    dirty: bool,
}

impl TerrainGrid {
    /// Paint a single cell. Painting `Grass` clears any override.
    pub fn paint(&mut self, cell: (i32, i32), terrain: TerrainType) {
        if terrain == TerrainType::Grass {
            self.cells.remove(&cell);
        } else {
            self.cells.insert(cell, terrain);
        }
        self.dirty = true;
    }

    /// Paint an inclusive rectangle of cells.
    pub fn paint_rect(&mut self, min: (i32, i32), max: (i32, i32), terrain: TerrainType) {
        for x in min.0..=max.0 {
            for z in min.1..=max.1 {
                self.paint((x, z), terrain);
            }
        }
    }

    /// The terrain at a cell (Grass if unpainted).
    pub fn get(&self, cell: (i32, i32)) -> TerrainType {
        self.cells.get(&cell).copied().unwrap_or(TerrainType::Grass)
    }

    /// Number of painted (non-grass) cells.
    pub fn painted_count(&self) -> usize {
        self.cells.len()
    }
}

/// Marker for spawned terrain override tile entities.
#[derive(Component)]
struct TerrainTile;

/// Rebuild the terrain override tiles whenever the grid is marked dirty.
fn render_terrain(
    mut commands: Commands,
    mut grid: ResMut<TerrainGrid>,
    existing: Query<Entity, With<TerrainTile>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    if !grid.dirty {
        return;
    }
    grid.dirty = false;

    for entity in &existing {
        commands.entity(entity).despawn();
    }

    // One shared 1x1 tile mesh and one material per terrain type.
    let tile_mesh = meshes.add(Plane3d::default().mesh().size(1.0, 1.0));
    let mut mats: HashMap<TerrainType, Handle<StandardMaterial>> = HashMap::new();

    for (cell, terrain) in grid.cells.iter() {
        let material = mats
            .entry(*terrain)
            .or_insert_with(|| {
                materials.add(StandardMaterial {
                    base_color_texture: Some(asset_server.load(terrain.texture_path())),
                    perceptual_roughness: 0.9,
                    ..default()
                })
            })
            .clone();
        commands.spawn((
            PbrBundle {
                mesh: tile_mesh.clone(),
                material,
                // Just above the base grass plane (y=0), below room floors (0.02).
                transform: Transform::from_xyz(cell.0 as f32, 0.012, cell.1 as f32),
                ..default()
            },
            TerrainTile,
            Name::new("Terrain Tile"),
        ));
    }
}

/// Paint some demo landscaping outside the starter house.
fn paint_demo_terrain(mut grid: ResMut<TerrainGrid>) {
    // Concrete walkway leading south from the front door.
    grid.paint_rect((-1, 6), (1, 9), TerrainType::Concrete);
    // Concrete patio on the east side.
    grid.paint_rect((6, -3), (9, 3), TerrainType::Concrete);
    // A small pool on the west side.
    grid.paint_rect((-10, -3), (-7, 2), TerrainType::PoolTile);
    // A dirt garden patch out back.
    grid.paint_rect((6, 5), (9, 8), TerrainType::Dirt);
    // Neighborhood road running past the lots (visible in the overhead map view).
    grid.paint_rect((-12, -11), (22, -10), TerrainType::Concrete);
}

/// Wires up terrain painting and rendering.
pub struct TerrainPlugin;

impl Plugin for TerrainPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<TerrainGrid>()
            .register_type::<TerrainType>()
            .add_systems(Startup, paint_demo_terrain)
            .add_systems(Update, render_terrain);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paint_and_get() {
        let mut grid = TerrainGrid::default();
        assert_eq!(grid.get((0, 0)), TerrainType::Grass);
        grid.paint((0, 0), TerrainType::Concrete);
        assert_eq!(grid.get((0, 0)), TerrainType::Concrete);
        // Painting grass clears the override.
        grid.paint((0, 0), TerrainType::Grass);
        assert_eq!(grid.get((0, 0)), TerrainType::Grass);
        assert_eq!(grid.painted_count(), 0);
    }

    #[test]
    fn paint_rect_covers_area() {
        let mut grid = TerrainGrid::default();
        grid.paint_rect((0, 0), (2, 1), TerrainType::Dirt);
        assert_eq!(grid.painted_count(), 6);
        assert_eq!(grid.get((2, 1)), TerrainType::Dirt);
        assert_eq!(grid.get((3, 1)), TerrainType::Grass);
    }
}
