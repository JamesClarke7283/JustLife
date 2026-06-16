pub mod assets;
pub mod audio;
pub mod build;
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
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                // Render into the canvas already present in web/index.html instead
                // of letting Bevy append a second canvas (which broke page layout
                // and left the viewport showing only the clear color).
                canvas: Some("#game-canvas".into()),
                fit_canvas_to_parent: true,
                prevent_default_event_handling: true,
                title: "Just Life".into(),
                ..default()
            }),
            ..default()
        }))
        .add_plugins((
            core::CorePlugin,
            sim::SimPlugin,
            world::WorldPlugin,
            build::BuildModePlugin,
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
