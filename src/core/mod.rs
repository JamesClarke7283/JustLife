use bevy::prelude::*;

pub mod components;
pub mod events;
pub mod resources;
pub mod state;
pub mod time;

pub struct CorePlugin;

impl Plugin for CorePlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<resources::GameTime>()
            .register_type::<resources::GameSpeed>()
            .register_type::<resources::MoneyResource>()
            .register_type::<resources::GameConfig>()
            .register_type::<resources::NeedDecayRates>()
            .register_type::<resources::AutonomyLevel>()
            .register_type::<resources::SelectionResource>()
            .init_resource::<resources::GameConfig>()
            .init_resource::<resources::GameTime>()
            .init_resource::<resources::GameSpeed>()
            .init_resource::<resources::MoneyResource>()
            .init_resource::<resources::SelectionResource>()
            // Boot into the main menu; New Game transitions to Live mode.
            .insert_state(state::GameState::MainMenu)
            .add_event::<events::NeedChangeEvent>()
            .add_event::<crate::sim::needs::NeedThresholdEvent>()
            .add_event::<events::InteractionEvent>()
            .add_event::<events::TimeTickEvent>()
            .add_event::<events::SocialEvent>()
            .add_event::<events::CareerEvent>()
            .add_event::<events::BuildModeEvent>()
            .add_event::<events::SimSpawnEvent>()
            .add_event::<events::SimDeathEvent>()
            .add_event::<events::ToastEvent>()
            .add_systems(Startup, setup)
            .add_systems(Update, time::tick_game_time);
    }
}

fn setup(
    mut money: ResMut<resources::MoneyResource>,
    mut speed: ResMut<resources::GameSpeed>,
    config: Res<resources::GameConfig>,
) {
    // Camera is spawned by render::camera::spawn_camera to avoid duplicate cameras.
    money.amount = config.starting_funds;
    // Run the simulation by default (no time-control UI yet); build/buy modes
    // pause it via their own enter/exit handlers.
    *speed = resources::GameSpeed::Normal;
}
