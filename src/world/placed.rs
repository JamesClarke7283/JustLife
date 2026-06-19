use bevy::prelude::*;
use bevy::utils::HashMap;

use crate::core::components::Sellable;
use crate::world::catalog::CatalogDatabase;
use crate::world::{ObjectCondition, PlacedObject};

/// Maps occupied grid cells to the placed object occupying them. Used by build
/// mode to validate placement and by sims to locate objects.
#[derive(Resource, Default, Debug)]
pub struct ObjectGrid {
    pub occupied: HashMap<(i32, i32), Entity>,
}

impl ObjectGrid {
    /// Is the given cell unoccupied?
    pub fn is_free(&self, cell: (i32, i32)) -> bool {
        !self.occupied.contains_key(&cell)
    }

    /// Are all of the given cells unoccupied?
    pub fn area_free(&self, cells: &[(i32, i32)]) -> bool {
        cells.iter().all(|c| self.is_free(*c))
    }

    /// Mark every cell as occupied by `entity`.
    pub fn occupy(&mut self, cells: &[(i32, i32)], entity: Entity) {
        for cell in cells {
            self.occupied.insert(*cell, entity);
        }
    }

    /// Free every cell currently held by `entity`.
    pub fn release(&mut self, entity: Entity) {
        self.occupied.retain(|_, e| *e != entity);
    }

    /// Distinct entities occupying cells within `radius` cells of `center`
    /// (Chebyshev distance). Grid-based spatial partitioning for range queries
    /// (Phase 11.7) - O(radius^2) instead of scanning every placed object.
    pub fn entities_within(&self, center: (i32, i32), radius: i32) -> Vec<Entity> {
        let mut found = Vec::new();
        for dx in -radius..=radius {
            for dy in -radius..=radius {
                if let Some(&entity) = self.occupied.get(&(center.0 + dx, center.1 + dy))
                    && !found.contains(&entity)
                {
                    found.push(entity);
                }
            }
        }
        found
    }
}

/// Grid cells covered by an object at `position` with the given `footprint`
/// (width, depth) and a quarter-turn `rotation`. The object's position is the
/// centre of its footprint.
pub fn footprint_cells(position: Vec3, footprint: (u32, u32), rotation: Quat) -> Vec<(i32, i32)> {
    let (mut w, mut d) = (footprint.0.max(1) as i32, footprint.1.max(1) as i32);
    // Swap dimensions on odd quarter-turns (90 / 270 degrees).
    let yaw = rotation.to_euler(EulerRot::YXZ).0;
    let quarter = (yaw / std::f32::consts::FRAC_PI_2).round().rem_euclid(4.0) as i32;
    if quarter % 2 == 1 {
        std::mem::swap(&mut w, &mut d);
    }
    let cx = position.x.round() as i32;
    let cz = position.z.round() as i32;
    let x_start = cx - w / 2;
    let z_start = cz - d / 2;
    let mut cells = Vec::with_capacity((w * d) as usize);
    for dx in 0..w {
        for dz in 0..d {
            cells.push((x_start + dx, z_start + dz));
        }
    }
    cells
}

/// Register newly placed objects' footprints in the occupancy grid.
fn register_placed_objects(
    mut grid: ResMut<ObjectGrid>,
    query: Query<(Entity, &PlacedObject), Added<PlacedObject>>,
) {
    for (entity, obj) in &query {
        let cells = footprint_cells(obj.position, obj.footprint, obj.rotation);
        grid.occupy(&cells, entity);
    }
}

/// Free grid cells when a placed object is removed.
fn release_removed_objects(
    mut grid: ResMut<ObjectGrid>,
    mut removed: RemovedComponents<PlacedObject>,
) {
    for entity in removed.read() {
        grid.release(entity);
    }
}

/// How often placed objects lose value.
#[derive(Resource, Debug)]
pub struct DepreciationTimer(pub Timer);

impl Default for DepreciationTimer {
    fn default() -> Self {
        // Roughly once per in-game day at the default time scale.
        Self(Timer::from_seconds(120.0, TimerMode::Repeating))
    }
}

/// Placed objects slowly lose value, down to a salvage floor of 10% of the
/// original catalog price.
fn depreciate_objects(
    time: Res<Time>,
    mut timer: ResMut<DepreciationTimer>,
    catalog: Res<CatalogDatabase>,
    mut query: Query<(&PlacedObject, &mut Sellable)>,
) {
    if !timer.0.tick(time.delta()).just_finished() {
        return;
    }
    for (obj, mut sellable) in &mut query {
        let floor = catalog
            .get(&obj.catalog_id)
            .map(|item| item.price / 10)
            .unwrap_or(0);
        let depreciated = sellable.value.saturating_sub(sellable.value / 20);
        sellable.value = depreciated.max(floor);
    }
}

impl ObjectCondition {
    /// Whether a sim can currently use the object (broken objects can't).
    pub fn is_usable(&self) -> bool {
        matches!(self, ObjectCondition::Clean | ObjectCondition::Dirty)
    }

    /// Advance the wear state: Clean -> Dirty -> Broken.
    pub fn degrade(self) -> Self {
        match self {
            ObjectCondition::Clean => ObjectCondition::Dirty,
            ObjectCondition::Dirty => ObjectCondition::Broken,
            ObjectCondition::Broken => ObjectCondition::Broken,
        }
    }
}

/// Wires up object occupancy tracking and depreciation.
pub struct PlacedObjectPlugin;

impl Plugin for PlacedObjectPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<ObjectGrid>()
            .init_resource::<DepreciationTimer>()
            .add_systems(
                Update,
                (
                    register_placed_objects,
                    release_removed_objects,
                    depreciate_objects,
                ),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn footprint_1x1_is_single_cell() {
        let cells = footprint_cells(Vec3::new(3.0, 0.0, -2.0), (1, 1), Quat::IDENTITY);
        assert_eq!(cells, vec![(3, -2)]);
    }

    #[test]
    fn entities_within_finds_only_nearby_distinct_entities() {
        let mut grid = ObjectGrid::default();
        let a = Entity::from_raw(1);
        let b = Entity::from_raw(2);
        let far = Entity::from_raw(3);
        grid.occupy(&[(0, 0), (0, 1)], a); // a spans two cells near center
        grid.occupy(&[(1, 0)], b);
        grid.occupy(&[(9, 9)], far);
        let near = grid.entities_within((0, 0), 1);
        assert!(near.contains(&a) && near.contains(&b));
        assert!(!near.contains(&far));
        // `a` occupies two in-range cells but appears once.
        assert_eq!(near.iter().filter(|&&e| e == a).count(), 1);
    }

    #[test]
    fn footprint_2x3_covers_six_cells() {
        let cells = footprint_cells(Vec3::ZERO, (2, 3), Quat::IDENTITY);
        assert_eq!(cells.len(), 6);
    }

    #[test]
    fn rotation_swaps_dimensions() {
        let straight = footprint_cells(Vec3::ZERO, (3, 1), Quat::IDENTITY);
        let turned = footprint_cells(
            Vec3::ZERO,
            (3, 1),
            Quat::from_rotation_y(std::f32::consts::FRAC_PI_2),
        );
        assert_eq!(straight.len(), 3);
        assert_eq!(turned.len(), 3);
        // Straight spans X; turned spans Z.
        assert!(straight.iter().any(|c| c.0 != 0));
        assert!(turned.iter().any(|c| c.1 != 0));
    }

    #[test]
    fn grid_occupancy_and_release() {
        let mut grid = ObjectGrid::default();
        let e = Entity::from_raw(7);
        grid.occupy(&[(0, 0), (1, 0)], e);
        assert!(!grid.is_free((0, 0)));
        assert!(grid.is_free((2, 0)));
        assert!(!grid.area_free(&[(0, 0), (2, 0)]));
        grid.release(e);
        assert!(grid.is_free((0, 0)));
    }

    #[test]
    fn condition_state_machine() {
        assert!(ObjectCondition::Clean.is_usable());
        assert!(!ObjectCondition::Broken.is_usable());
        assert_eq!(ObjectCondition::Clean.degrade(), ObjectCondition::Dirty);
        assert_eq!(ObjectCondition::Dirty.degrade(), ObjectCondition::Broken);
        assert_eq!(ObjectCondition::Broken.degrade(), ObjectCondition::Broken);
    }
}
