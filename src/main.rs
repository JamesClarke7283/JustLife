pub mod assets;
pub mod audio;
pub mod career;
pub mod core;
pub mod interaction;
pub mod render;
pub mod sim;
pub mod social;
pub mod ui;
pub mod wasm;
pub mod world;

use bevy::prelude::*;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins((
            core::CorePlugin,
            sim::SimPlugin,
            world::WorldPlugin,
            ui::UIPlugin,
            interaction::InteractionPlugin,
            career::CareerPlugin,
            social::SocialPlugin,
            audio::AudioPlugin,
            assets::AssetsPlugin,
            wasm::WasmPlugin,
            render::RenderPlugin,
        ))
        .run();
}
