use bevy::prelude::*;

/// A door placed in a wall segment.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Door {
    pub position: Vec2,
    pub rotation: f32,
    pub locked: bool,
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
            connected_rooms: [None, None],
            width: 1.0,
            height: 2.2,
        }
    }

    /// Snap the door position to the nearest grid unit.
    pub fn snapped(position: Vec2, rotation: f32) -> Self {
        Self::new(crate::world::wall::snap_to_grid(position), rotation)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn door_defaults() {
        let door = Door::new(Vec2::new(1.0, 2.0), 0.0);
        assert!(!door.locked);
        assert_eq!(door.width, 1.0);
        assert_eq!(door.height, 2.2);
    }
}
