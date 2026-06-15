use bevy::prelude::*;

use crate::world::wall::{Wall, WallVisualDirty};

/// Tracks the wall-building interaction state.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq)]
pub enum WallToolState {
    #[default]
    Inactive,
    Placing,
    Deleting,
}

/// Spawns a wall segment between two grid-snapped points.
pub fn spawn_wall_segment(commands: &mut Commands, start: Vec2, end: Vec2) -> Entity {
    commands
        .spawn((
            Wall::snapped(start, end),
            WallVisualDirty,
            Name::new("Wall"),
        ))
        .id()
}

/// Delete a wall entity and its children.
pub fn delete_wall(commands: &mut Commands, wall_entity: Entity) {
    commands.entity(wall_entity).despawn_recursive();
}

/// Validate that a new wall segment doesn't overlap an existing one.
pub fn validate_wall_placement(new_wall: &Wall, existing_walls: &Query<'_, '_, &Wall>) -> bool {
    for wall in existing_walls.iter() {
        if new_wall.overlaps(wall) {
            return false;
        }
    }
    true
}
