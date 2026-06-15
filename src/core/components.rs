use bevy::prelude::*;

/// Marks entities that sims can interact with.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct Interactable;

/// Marks the sim that is currently under player control.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct SimControlled;

/// Entity has a display name.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Named {
    pub name: String,
}

/// Entity has a description text.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Describable {
    pub description: String,
}

/// Entity has a monetary value (for buy/sell mode).
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Sellable {
    pub value: u32,
}

/// Pathfinding target position.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct RouteTo {
    pub target: Vec3,
    pub arrival_distance: f32,
}

impl RouteTo {
    pub fn new(target: Vec3) -> Self {
        Self {
            target,
            arrival_distance: 0.1,
        }
    }
}

/// Marker that an object is currently being used by a sim.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct Occupied {
    pub user: Option<Entity>,
}
