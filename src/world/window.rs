use bevy::prelude::*;

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
