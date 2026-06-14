use bevy::prelude::*;

pub struct SimPlugin;

impl Plugin for SimPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<SimManager>()
            .register_type::<Needs>()
            .register_type::<Moodlet>()
            .register_type::<ActiveMoodlets>()
            .register_type::<SimIdentity>()
            .register_type::<SimAge>()
            .register_type::<SimGender>()
            .register_type::<SimTraits>()
            .register_type::<SimAppearance>()
            .register_type::<AnimationState>();
    }
}

#[derive(Resource, Default, Debug)]
pub struct SimManager {
    pub sims: Vec<Entity>,
}

#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub enum SimGender {
    #[default]
    Male,
    Female,
    Custom,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct SimIdentity {
    pub first_name: String,
    pub last_name: String,
}

impl SimIdentity {
    pub fn full_name(&self) -> String {
        format!("{} {}", self.first_name, self.last_name)
    }
}

#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub enum SimAge {
    #[default]
    Baby,
    Toddler,
    Child,
    Teen,
    YoungAdult,
    Adult,
    Elder,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct SimTraits {
    pub traits: Vec<Trait>,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct SimAppearance {
    pub skin_tone: Color,
    pub hair_color: Color,
    pub shirt_color: Color,
    pub pants_color: Color,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Needs {
    pub hunger: f32,
    pub energy: f32,
    pub social: f32,
    pub fun: f32,
    pub hygiene: f32,
    pub bladder: f32,
}

impl Needs {
    pub const fn new() -> Self {
        Self {
            hunger: 100.0,
            energy: 100.0,
            social: 100.0,
            fun: 100.0,
            hygiene: 100.0,
            bladder: 100.0,
        }
    }
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Moodlet {
    pub name: String,
    pub description: String,
    pub mood_impact: i32,
    pub duration: f32,
    pub source: String,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct ActiveMoodlets {
    pub moodlets: Vec<Moodlet>,
}

#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub enum AnimationState {
    #[default]
    Idle,
    Walking,
    Running,
    Sitting,
    Sleeping,
    Talking,
    Eating,
    Cooking,
    Working,
    Playing,
    UsingObject,
    Socializing,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum Trait {
    #[default]
    Active,
    Lazy,
    Cheerful,
    Gloomy,
    Creative,
    Genius,
    Neat,
    Slob,
    Outgoing,
    Introvert,
    Romantic,
    Unflirty,
    Ambitious,
    Good,
    Evil,
    SelfAssured,
    SelfDeprecating,
    Foodie,
    Glutton,
    HotHeaded,
    Calm,
    FamilyOriented,
    Loner,
    SocialButterfly,
}
