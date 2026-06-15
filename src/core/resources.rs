use bevy::prelude::*;

/// In-game calendar time: day, hour, minute.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Resource)]
pub struct GameTime {
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
}

/// Current simulation speed. Paused is the default until the player starts.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Resource)]
pub enum GameSpeed {
    #[default]
    Pause,
    Normal,
    Fast,
    Ultra,
}

impl GameSpeed {
    /// Real-time multiplier for this speed setting.
    pub const fn multiplier(self) -> f32 {
        match self {
            GameSpeed::Pause => 0.0,
            GameSpeed::Normal => 1.0,
            GameSpeed::Fast => 2.0,
            GameSpeed::Ultra => 4.0,
        }
    }
}

/// Global household funds. Negative values represent debt.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Resource)]
pub struct MoneyResource {
    pub amount: i64,
}

/// Tunable constants that drive simulation balance.
#[derive(Resource, Debug, Clone, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct GameConfig {
    /// Starting money for a new household.
    pub starting_funds: i64,
    /// Minutes of real time per in-game minute at 1x speed.
    pub real_seconds_per_game_minute: f32,
    /// How fast each need decays per in-game minute.
    pub need_decay_rates: NeedDecayRates,
    /// Salary multiplier applied to all career salaries.
    pub salary_multiplier: f32,
    /// Speed at which sims age through life stages.
    pub aging_speed: f32,
    /// Default autonomy level for unselected sims.
    pub autonomy_level: AutonomyLevel,
}

impl Default for GameConfig {
    fn default() -> Self {
        Self {
            starting_funds: 20_000,
            real_seconds_per_game_minute: 1.0,
            need_decay_rates: NeedDecayRates::default(),
            salary_multiplier: 1.0,
            aging_speed: 1.0,
            autonomy_level: AutonomyLevel::Full,
        }
    }
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum AutonomyLevel {
    #[default]
    Full,
    High,
    Low,
    Off,
}

/// Decay rates for each of the six core needs, expressed as need-units per in-game minute.
#[derive(Resource, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct NeedDecayRates {
    pub hunger: f32,
    pub energy: f32,
    pub social: f32,
    pub fun: f32,
    pub hygiene: f32,
    pub bladder: f32,
}

impl Default for NeedDecayRates {
    fn default() -> Self {
        Self {
            // Tuned so a sim needs to eat 2-3 times per day.
            hunger: 0.08,
            // Tuned to last ~16 hours awake before sleep is required.
            energy: 0.06,
            // Decays slowly; extroverts will feel it faster via trait modifiers.
            social: 0.04,
            // Requires active engagement; passive decay is low.
            fun: 0.05,
            // Drops from exercise and work; moderate base rate.
            hygiene: 0.05,
            // Fills up ~3 times per day.
            bladder: 0.07,
        }
    }
}

/// Currently selected entity in the world (sim, object, etc.).
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Resource)]
pub struct SelectionResource {
    pub selected: Option<Entity>,
}
