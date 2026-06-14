use bevy::prelude::*;

#[derive(Event)]
pub struct NeedChangeEvent {
    pub entity: Entity,
    pub need: String,
    pub value: f32,
}

#[derive(Event)]
pub struct InteractionEvent {
    pub entity: Entity,
    pub interaction: String,
}

#[derive(Event)]
pub struct TimeTickEvent;

#[derive(Event)]
pub struct SocialEvent {
    pub source: Entity,
    pub target: Entity,
    pub interaction: String,
}

#[derive(Event)]
pub struct CareerEvent {
    pub entity: Entity,
    pub change: String,
}

#[derive(Event)]
pub struct BuildModeEvent;

#[derive(Event)]
pub struct SimSpawnEvent {
    pub entity: Entity,
}

#[derive(Event)]
pub struct SimDeathEvent {
    pub entity: Entity,
}
