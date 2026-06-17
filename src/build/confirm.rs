//! Confirmation dialog for expensive purchases (Phase 10.6).
//!
//! When an expensive catalog item is selected in buy mode, a dialog gates its
//! placement until the player confirms (Enter) or cancels (Esc). Confirmation is
//! remembered per item id so the player isn't re-prompted on every placement.

use bevy::prelude::*;

use crate::build::buy_mode::BuyCatalogState;
use crate::career::economy::format_money;
use crate::core::state::GameState;
use crate::world::catalog::CatalogDatabase;

/// Items priced above this require confirmation before placement.
pub const CONFIRM_THRESHOLD: u32 = 1000;

/// Remembers which item id the player has confirmed buying.
#[derive(Resource, Default)]
pub struct PurchaseGate {
    pub confirmed: Option<String>,
}

/// Whether placing `id` (priced `price`) still needs confirmation.
pub fn needs_confirm(price: u32, id: &str, gate: &PurchaseGate) -> bool {
    price > CONFIRM_THRESHOLD && gate.confirmed.as_deref() != Some(id)
}

#[derive(Component)]
struct ConfirmDialog;

/// Show/resolve the confirmation dialog for an expensive selected item.
fn confirm_system(
    mut commands: Commands,
    keyboard: Res<ButtonInput<KeyCode>>,
    catalog: Res<CatalogDatabase>,
    mut buy: ResMut<BuyCatalogState>,
    mut gate: ResMut<PurchaseGate>,
    dialogs: Query<Entity, With<ConfirmDialog>>,
) {
    // The selected item, if it still needs confirming.
    let pending = buy
        .selected
        .as_deref()
        .and_then(|id| {
            catalog
                .get(id)
                .map(|item| (id.to_string(), item.name.clone(), item.price))
        })
        .filter(|(id, _, price)| needs_confirm(*price, id, &gate));

    let Some((id, name, price)) = pending else {
        despawn_all(&mut commands, &dialogs);
        return;
    };

    if keyboard.just_pressed(KeyCode::Enter) {
        gate.confirmed = Some(id);
        despawn_all(&mut commands, &dialogs);
    } else if keyboard.just_pressed(KeyCode::Escape) {
        buy.selected = None;
        despawn_all(&mut commands, &dialogs);
    } else if dialogs.is_empty() {
        spawn_dialog(&mut commands, &name, price);
    }
}

fn despawn_all(commands: &mut Commands, dialogs: &Query<Entity, With<ConfirmDialog>>) {
    for entity in dialogs {
        commands.entity(entity).despawn_recursive();
    }
}

fn spawn_dialog(commands: &mut Commands, name: &str, price: u32) {
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Percent(50.0),
                    top: Val::Percent(40.0),
                    margin: UiRect::new(Val::Px(-170.0), Val::ZERO, Val::ZERO, Val::ZERO),
                    width: Val::Px(340.0),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    padding: UiRect::all(Val::Px(16.0)),
                    row_gap: Val::Px(10.0),
                    ..default()
                },
                background_color: Color::srgba(0.08, 0.10, 0.16, 0.97).into(),
                border_radius: BorderRadius::all(Val::Px(8.0)),
                ..default()
            },
            ConfirmDialog,
            Name::new("Purchase Confirm"),
        ))
        .with_children(|d| {
            d.spawn(TextBundle::from_section(
                "Confirm Purchase",
                TextStyle {
                    font_size: 22.0,
                    color: Color::WHITE,
                    ..default()
                },
            ));
            d.spawn(TextBundle::from_section(
                format!("Buy {name} for {}?", format_money(price as i64)),
                TextStyle {
                    font_size: 16.0,
                    color: Color::srgb(0.85, 0.92, 1.0),
                    ..default()
                },
            ));
            d.spawn(TextBundle::from_section(
                "[Enter] Confirm     [Esc] Cancel",
                TextStyle {
                    font_size: 14.0,
                    color: Color::srgb(1.0, 0.9, 0.5),
                    ..default()
                },
            ));
        });
}

/// Forget confirmations when leaving buy mode.
fn reset_gate(mut gate: ResMut<PurchaseGate>) {
    gate.confirmed = None;
}

/// Registers the purchase confirmation dialog (buy mode only).
pub struct PurchaseConfirmPlugin;

impl Plugin for PurchaseConfirmPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PurchaseGate>()
            .add_systems(Update, confirm_system.run_if(in_state(GameState::BuyMode)))
            .add_systems(OnExit(GameState::BuyMode), reset_gate);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_expensive_unconfirmed_items_need_confirming() {
        let mut gate = PurchaseGate::default();
        // Cheap item: never needs confirming.
        assert!(!needs_confirm(200, "lamp", &gate));
        // Expensive item: needs confirming until confirmed.
        assert!(needs_confirm(2500, "pool", &gate));
        gate.confirmed = Some("pool".to_string());
        assert!(!needs_confirm(2500, "pool", &gate));
        // A different expensive item still needs its own confirmation.
        assert!(needs_confirm(2500, "hot_tub", &gate));
    }
}
