use bevy::prelude::*;

#[derive(Resource, Default)]
pub struct GameTime {
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
}

#[derive(Resource, Default)]
pub enum GameSpeed {
    #[default]
    Pause,
    Normal,
    Fast,
    Ultra,
}

#[derive(Resource, Default)]
pub enum GameState {
    #[default]
    MainMenu,
    LiveMode,
    BuildMode,
    BuyMode,
    CreateASim,
    Loading,
}

#[derive(Resource, Default)]
pub struct MoneyResource {
    pub amount: i64,
}

#[derive(Resource, Default)]
pub struct GameConfig {
    pub need_decay_rates: NeedDecayRates,
}

#[derive(Default)]
pub struct NeedDecayRates {
    pub hunger: f32,
    pub energy: f32,
    pub social: f32,
    pub fun: f32,
    pub hygiene: f32,
    pub bladder: f32,
}

#[derive(Resource, Default)]
pub struct SelectionResource {
    pub selected: Option<Entity>,
}
