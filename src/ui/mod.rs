use bevy::prelude::*;

pub mod main_menu;
pub mod pie_menu;

pub struct UIPlugin;

impl Plugin for UIPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((pie_menu::PieMenuPlugin, main_menu::MainMenuPlugin))
            .init_resource::<UIMode>()
            .register_type::<UIMode>()
            .register_type::<NeedsBarStyle>();
    }
}

#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Resource)]
pub enum UIMode {
    #[default]
    MainMenu,
    CreateASim,
    LiveMode,
    BuildMode,
    BuyMode,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct NeedsBarStyle {
    pub bar_width: f32,
    pub bar_height: f32,
    pub critical_flash: bool,
}
