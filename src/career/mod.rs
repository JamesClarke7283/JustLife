use bevy::prelude::*;

pub struct CareerPlugin;

impl Plugin for CareerPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CareerDatabase>()
            .register_type::<Career>()
            .register_type::<JobPerformance>()
            .register_type::<Skills>();
    }
}

#[derive(Resource, Default, Debug)]
pub struct CareerDatabase {
    pub careers: Vec<CareerDefinition>,
}

#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct CareerDefinition {
    pub name: String,
    pub levels: Vec<CareerLevel>,
}

#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct CareerLevel {
    pub title: String,
    pub salary: u32,
    pub work_days: Vec<u8>,
    pub start_hour: u8,
    pub end_hour: u8,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Career {
    pub name: String,
    pub level: u8,
    pub daily_performance: f32,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct JobPerformance {
    pub score: f32,
    pub days_missed: u32,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Skills {
    pub levels: bevy::utils::HashMap<SkillType, u8>,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect)]
#[reflect]
pub enum SkillType {
    #[default]
    Cooking,
    Handiness,
    Charisma,
    Fitness,
    Logic,
    Creativity,
    Gardening,
    Fishing,
    Programming,
}
