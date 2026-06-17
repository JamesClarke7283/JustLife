//! Household economy: money formatting, periodic bills (delivered, payable, and
//! enforced on a deadline), bankruptcy repossession and a funds/bills HUD
//! (Phases 9.1 and 9.6).

use bevy::prelude::*;

use crate::core::components::Sellable;
use crate::core::resources::{GameTime, MoneyResource};
use crate::core::state::GameState;
use crate::world::PlacedObject;
use crate::world::placed::ObjectGrid;

/// In-game days between utility bills.
const BILL_INTERVAL_DAYS: u32 = 7;
/// Days a household has to pay a bill before it is force-collected.
const BILL_GRACE_DAYS: u32 = 3;
/// Flat base charge on every bill.
const BILL_BASE: i64 = 50;
/// Fraction of lot value added to each bill (1/divisor).
const BILL_VALUE_DIVISOR: i64 = 40;
/// Per powered appliance utility charge.
const APPLIANCE_BILL: i64 = 8;

/// Format a money amount for display, abbreviating large values with K/M.
pub fn format_money(amount: i64) -> String {
    let sign = if amount < 0 { "-" } else { "" };
    let a = amount.unsigned_abs();
    if a >= 1_000_000 {
        format!("{sign}${:.1}M", a as f64 / 1_000_000.0)
    } else if a >= 10_000 {
        format!("{sign}${:.1}K", a as f64 / 1_000.0)
    } else {
        format!("{sign}${a}")
    }
}

/// The lot-value portion of a bill (base charge plus a fraction of lot value).
pub fn bill_amount(lot_value: i64) -> i64 {
    BILL_BASE + lot_value / BILL_VALUE_DIVISOR
}

/// A full utility bill: lot-value charge plus per-appliance electricity/water.
pub fn bill_total(lot_value: i64, appliances: i64) -> i64 {
    bill_amount(lot_value) + appliances * APPLIANCE_BILL
}

/// Tracks when the last utility bill was charged.
#[derive(Resource, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Resource)]
pub struct BillingState {
    pub last_billed_day: u32,
}

impl Default for BillingState {
    fn default() -> Self {
        // The demo clock starts on day 6; the first bill lands an interval later.
        Self { last_billed_day: 6 }
    }
}

/// Outstanding bills awaiting payment.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Resource)]
pub struct Bills {
    /// Total currently owed.
    pub amount_due: i64,
    /// In-game day the outstanding balance is force-collected on.
    pub due_day: u32,
}

/// Marks the funds readout text in the HUD.
#[derive(Component)]
struct MoneyDisplay;

/// Marks the outstanding-bills readout text in the HUD.
#[derive(Component)]
struct BillsDisplay;

/// Deliver a utility bill once every billing interval, scaled by lot value and
/// appliance usage. The bill is added to the outstanding balance with a deadline
/// rather than charged immediately.
fn billing_system(
    game_time: Res<GameTime>,
    mut bills: ResMut<Bills>,
    mut state: ResMut<BillingState>,
    objects: Query<(&Sellable, &PlacedObject)>,
) {
    if game_time.day < state.last_billed_day + BILL_INTERVAL_DAYS {
        return;
    }
    state.last_billed_day = game_time.day;
    let lot_value: i64 = objects.iter().map(|(s, _)| s.value as i64).sum();
    let appliances = objects.iter().filter(|(_, o)| o.powered).count() as i64;
    let bill = bill_total(lot_value, appliances);
    bills.amount_due += bill;
    bills.due_day = game_time.day + BILL_GRACE_DAYS;
    info!(
        "Utility bill of {} delivered; due on day {}",
        format_money(bill),
        bills.due_day
    );
}

/// Pay the outstanding bills on demand (press P) if the household can afford it.
fn pay_bills_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut money: ResMut<MoneyResource>,
    mut bills: ResMut<Bills>,
) {
    if keyboard.just_pressed(KeyCode::KeyP) && bills.amount_due > 0 && money.spend(bills.amount_due)
    {
        info!("Paid {} in bills", format_money(bills.amount_due));
        bills.amount_due = 0;
    }
}

/// On the due day, force-collect any unpaid balance (driving funds negative if
/// needed, which the repossession system then resolves by selling objects).
fn bill_deadline_system(
    game_time: Res<GameTime>,
    mut money: ResMut<MoneyResource>,
    mut bills: ResMut<Bills>,
) {
    if bills.amount_due > 0 && game_time.day >= bills.due_day {
        money.amount -= bills.amount_due;
        bills.amount_due = 0;
    }
}

/// While the household is in debt, the repo collector hauls off the single most
/// valuable object each tick (refunding its value) until funds are non-negative.
fn repossession_system(
    mut money: ResMut<MoneyResource>,
    mut grid: ResMut<ObjectGrid>,
    mut commands: Commands,
    objects: Query<(Entity, &Sellable), With<PlacedObject>>,
) {
    if !money.is_bankrupt() {
        return;
    }
    if let Some((entity, value)) = objects
        .iter()
        .map(|(e, s)| (e, s.value))
        .max_by_key(|(_, v)| *v)
    {
        money.deposit(value as i64);
        grid.release(entity);
        commands.entity(entity).despawn_recursive();
    }
}

/// Spawn the funds + bills readout in the top-left when entering live mode.
fn spawn_money_hud(mut commands: Commands, money: Res<MoneyResource>) {
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Px(12.0),
                    top: Val::Px(12.0),
                    padding: UiRect::all(Val::Px(8.0)),
                    flex_direction: FlexDirection::Column,
                    row_gap: Val::Px(2.0),
                    ..default()
                },
                background_color: Color::srgba(0.10, 0.16, 0.12, 0.82).into(),
                border_radius: BorderRadius::all(Val::Px(6.0)),
                ..default()
            },
            MoneyDisplay,
            Name::new("Money HUD"),
        ))
        .with_children(|parent| {
            parent.spawn((
                TextBundle::from_section(
                    format_money(money.amount),
                    TextStyle {
                        font_size: 22.0,
                        color: Color::srgb(0.7, 1.0, 0.75),
                        ..default()
                    },
                ),
                MoneyDisplay,
            ));
            parent.spawn((
                TextBundle::from_section(
                    String::new(),
                    TextStyle {
                        font_size: 14.0,
                        color: Color::srgb(1.0, 0.82, 0.4),
                        ..default()
                    },
                ),
                BillsDisplay,
            ));
        });
}

/// Refresh the outstanding-bills readout when the balance changes.
fn update_bills_hud(bills: Res<Bills>, mut labels: Query<&mut Text, With<BillsDisplay>>) {
    if !bills.is_changed() {
        return;
    }
    for mut text in &mut labels {
        if let Some(section) = text.sections.first_mut() {
            section.value = if bills.amount_due > 0 {
                format!(
                    "Bills: {} (day {})",
                    format_money(bills.amount_due),
                    bills.due_day
                )
            } else {
                String::new()
            };
        }
    }
}

/// Refresh the funds readout when the balance changes.
fn update_money_hud(money: Res<MoneyResource>, mut labels: Query<&mut Text, With<MoneyDisplay>>) {
    if !money.is_changed() {
        return;
    }
    for mut text in &mut labels {
        if let Some(section) = text.sections.first_mut() {
            section.value = format_money(money.amount);
            section.style.color = if money.is_bankrupt() {
                Color::srgb(1.0, 0.45, 0.4)
            } else {
                Color::srgb(0.7, 1.0, 0.75)
            };
        }
    }
}

/// Despawn the funds HUD when leaving live mode.
fn despawn_money_hud(mut commands: Commands, huds: Query<Entity, With<MoneyDisplay>>) {
    for entity in &huds {
        commands.entity(entity).despawn_recursive();
    }
}

/// Registers the household economy systems and the funds HUD.
pub struct EconomyPlugin;

impl Plugin for EconomyPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<BillingState>()
            .init_resource::<Bills>()
            .register_type::<BillingState>()
            .register_type::<Bills>()
            .add_systems(OnEnter(GameState::LiveMode), spawn_money_hud)
            .add_systems(OnExit(GameState::LiveMode), despawn_money_hud)
            .add_systems(
                Update,
                (
                    billing_system,
                    pay_bills_input,
                    bill_deadline_system,
                    repossession_system,
                    update_money_hud,
                    update_bills_hud,
                )
                    .run_if(in_state(GameState::LiveMode)),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn money_formats_with_k_and_m_suffixes() {
        assert_eq!(format_money(0), "$0");
        assert_eq!(format_money(950), "$950");
        assert_eq!(format_money(20_000), "$20.0K");
        assert_eq!(format_money(1_500_000), "$1.5M");
        assert_eq!(format_money(-12_345), "-$12.3K");
    }

    #[test]
    fn bills_scale_with_lot_value() {
        // Empty lot: just the base charge.
        assert_eq!(bill_amount(0), BILL_BASE);
        // Larger lots pay more.
        assert!(bill_amount(8_000) > bill_amount(800));
        assert_eq!(bill_amount(40_000), BILL_BASE + 1_000);
    }

    #[test]
    fn full_bill_adds_appliance_usage() {
        // Appliances add to the lot-value charge.
        assert_eq!(bill_total(0, 0), bill_amount(0));
        assert_eq!(bill_total(0, 5), BILL_BASE + 5 * APPLIANCE_BILL);
        assert!(bill_total(40_000, 10) > bill_total(40_000, 0));
    }

    #[test]
    fn money_helpers_track_affordability_and_debt() {
        let mut money = MoneyResource { amount: 100 };
        assert!(money.can_afford(100));
        assert!(!money.can_afford(101));
        assert!(money.spend(60));
        assert_eq!(money.amount, 40);
        assert!(!money.spend(50)); // can't overspend
        money.deposit(10);
        assert_eq!(money.amount, 50);
        money.amount = -5;
        assert!(money.is_bankrupt());
    }
}
