use bevy::prelude::*;

#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum GameState {
    #[default]
    MainMenu,
    LiveMode,
    BuildMode,
    BuyMode,
    CreateASim,
    Loading,
}
