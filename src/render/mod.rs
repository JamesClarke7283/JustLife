use bevy::prelude::*;

pub mod camera;
pub mod grid;
pub mod lighting;
pub mod primitives;

pub struct RenderPlugin;

impl Plugin for RenderPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((camera::CameraPlugin, grid::GridPlugin, lighting::LightingPlugin));
    }
}
