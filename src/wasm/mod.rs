use bevy::prelude::*;

pub struct WasmPlugin;

impl Plugin for WasmPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<WasmConfig>();
    }
}

#[derive(Resource, Debug, Clone, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct WasmConfig {
    pub touch_enabled: bool,
    pub pixel_ratio: f32,
}

impl Default for WasmConfig {
    fn default() -> Self {
        Self {
            touch_enabled: false,
            pixel_ratio: 1.0,
        }
    }
}
