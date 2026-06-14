use bevy::prelude::*;

#[derive(Component)]
pub struct Interactable;

#[derive(Component)]
pub struct SimControlled;

#[derive(Component)]
pub struct Named(pub String);

#[derive(Component)]
pub struct Describable(pub String);

#[derive(Component)]
pub struct Sellable {
    pub value: u32,
}

#[derive(Component)]
pub struct RouteTo {
    pub target: Vec3,
}

#[derive(Component)]
pub struct Occupied;
