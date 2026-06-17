use bevy::prelude::*;

use crate::core::resources::MoneyResource;
use crate::core::state::GameState;
use crate::world::catalog::{CatalogDatabase, spawn_catalog_item};
use crate::world::wall_tool::spawn_wall_segment;

/// Enough information to re-create an entity for redo (since entity ids change
/// across despawn/respawn).
#[derive(Clone)]
pub enum Recon {
    Object {
        item_id: String,
        pos: Vec3,
        rotation: Quat,
    },
    Wall {
        start: Vec2,
        end: Vec2,
    },
}

#[derive(Clone, Copy, PartialEq)]
enum Op {
    Place,
    Sell,
}

/// One reversible build/buy action.
pub struct Action {
    op: Op,
    recon: Recon,
    /// The live entity, when the action's object currently exists.
    entity: Option<Entity>,
    /// Money moved by the action (price for Place, refund for Sell).
    money: i64,
}

/// Undo/redo stacks for build/buy operations.
#[derive(Resource, Default)]
pub struct BuildHistory {
    undo: Vec<Action>,
    redo: Vec<Action>,
}

impl BuildHistory {
    /// Record that an object/wall was placed (entity `entity`, costing `cost`).
    pub fn record_place(&mut self, recon: Recon, entity: Entity, cost: i64) {
        self.undo.push(Action {
            op: Op::Place,
            recon,
            entity: Some(entity),
            money: cost,
        });
        self.redo.clear();
    }

    /// Record that an object was sold for `refund` (it has already been removed).
    pub fn record_sell(&mut self, recon: Recon, refund: i64) {
        self.undo.push(Action {
            op: Op::Sell,
            recon,
            entity: None,
            money: refund,
        });
        self.redo.clear();
    }
}

/// A request to undo or redo, raised by the keyboard or a toolbar button.
#[derive(Event, Clone, Copy, PartialEq, Eq)]
pub enum HistoryRequest {
    Undo,
    Redo,
}

pub struct BuildHistoryPlugin;

impl Plugin for BuildHistoryPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<BuildHistory>()
            .add_event::<HistoryRequest>()
            .add_systems(Update, undo_redo_system.run_if(in_build_or_buy_mode))
            .add_systems(OnExit(GameState::BuildMode), clear_history)
            .add_systems(OnExit(GameState::BuyMode), clear_history);
    }
}

fn in_build_or_buy_mode(state: Res<State<GameState>>) -> bool {
    matches!(state.get(), GameState::BuildMode | GameState::BuyMode)
}

fn clear_history(mut history: ResMut<BuildHistory>) {
    history.undo.clear();
    history.redo.clear();
}

/// Re-create an entity from its reconstruction data.
fn respawn(
    recon: &Recon,
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    catalog: &CatalogDatabase,
) -> Option<Entity> {
    match recon {
        Recon::Object {
            item_id,
            pos,
            rotation,
        } => catalog
            .get(item_id)
            .map(|item| spawn_catalog_item(commands, meshes, materials, item, *pos, *rotation)),
        Recon::Wall { start, end } => Some(spawn_wall_segment(commands, *start, *end)),
    }
}

#[allow(clippy::too_many_arguments)]
fn undo_redo_system(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut requests: EventReader<HistoryRequest>,
    catalog: Res<CatalogDatabase>,
    mut history: ResMut<BuildHistory>,
    mut money: ResMut<MoneyResource>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // Trigger from Ctrl+Z / Ctrl+Y or from toolbar Undo/Redo buttons.
    let ctrl = keyboard.pressed(KeyCode::ControlLeft) || keyboard.pressed(KeyCode::ControlRight);
    let mut want_undo = ctrl && keyboard.just_pressed(KeyCode::KeyZ);
    let mut want_redo = ctrl && keyboard.just_pressed(KeyCode::KeyY);
    for request in requests.read() {
        match request {
            HistoryRequest::Undo => want_undo = true,
            HistoryRequest::Redo => want_redo = true,
        }
    }

    if want_undo && let Some(mut action) = history.undo.pop() {
        match action.op {
            // Undo a placement: remove it and refund what was spent.
            Op::Place => {
                if let Some(entity) = action.entity.take() {
                    commands.entity(entity).despawn_recursive();
                }
                money.amount += action.money;
            }
            // Undo a sale: re-create the object and re-charge the refund.
            Op::Sell => {
                action.entity = respawn(
                    &action.recon,
                    &mut commands,
                    &mut meshes,
                    &mut materials,
                    &catalog,
                );
                money.amount -= action.money;
            }
        }
        history.redo.push(action);
    }

    if want_redo && let Some(mut action) = history.redo.pop() {
        match action.op {
            // Redo a placement: re-create it and re-charge the cost.
            Op::Place => {
                action.entity = respawn(
                    &action.recon,
                    &mut commands,
                    &mut meshes,
                    &mut materials,
                    &catalog,
                );
                money.amount -= action.money;
            }
            // Redo a sale: remove the object and refund again.
            Op::Sell => {
                if let Some(entity) = action.entity.take() {
                    commands.entity(entity).despawn_recursive();
                }
                money.amount += action.money;
            }
        }
        history.undo.push(action);
    }
}
