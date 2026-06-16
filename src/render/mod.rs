use bevy::prelude::*;

pub mod camera;
pub mod grid;
pub mod lighting;
pub mod primitives;

pub struct RenderPlugin;

impl Plugin for RenderPlugin {
    fn build(&self, app: &mut App) {
        // Daytime sky-blue background instead of the default dark gray.
        app.insert_resource(ClearColor(Color::srgb(0.53, 0.81, 0.92)))
            .add_plugins((
                camera::CameraPlugin,
                grid::GridPlugin,
                lighting::LightingPlugin,
            ));
    }
}
