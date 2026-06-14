use bevy::prelude::*;

pub struct InteractionPlugin;

impl Plugin for InteractionPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<InteractionQueue>()
            .register_type::<ActiveInteraction>()
            .register_type::<RouteTo>();
    }
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct InteractionQueue {
    pub queue: Vec<QueuedInteraction>,
}

#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct QueuedInteraction {
    pub name: String,
    pub target: Option<Entity>,
    pub category: InteractionCategory,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum InteractionCategory {
    #[default]
    Friendly,
    Romantic,
    Mean,
    Funny,
    Special,
    Object,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct ActiveInteraction {
    pub name: String,
    pub start_time: f32,
    pub duration: f32,
}

#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct RouteTo {
    pub target: Vec3,
}
