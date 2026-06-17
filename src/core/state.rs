use bevy::prelude::*;

#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum GameState {
    #[default]
    MainMenu,
    LiveMode,
    BuildMode,
    BuyMode,
    CreateASim,
    /// Choosing and buying a lot (after Create-A-Sim, before Live mode).
    LotSelect,
    Loading,
}
