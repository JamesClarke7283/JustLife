//! Lot selection screen (after Create-A-Sim, before Live mode).
//!
//! The player browses several lots, sees each one's size and price, and buys
//! one - its cost comes out of the household funds. Keyboard-driven (Up/Down or
//! 1-4 to choose, Enter to buy) so it works in the headless harness.

use bevy::prelude::*;

use crate::career::economy::format_money;
use crate::core::resources::MoneyResource;
use crate::core::state::GameState;

/// A buyable lot offered on the selection screen.
struct LotInfo {
    name: &'static str,
    size: &'static str,
    price: i64,
    blurb: &'static str,
}

const LOTS: [LotInfo; 4] = [
    LotInfo {
        name: "Cozy Starter",
        size: "20 x 20",
        price: 4_000,
        blurb: "Small and affordable - leaves plenty for furniture.",
    },
    LotInfo {
        name: "Suburban Plot",
        size: "30 x 30",
        price: 8_000,
        blurb: "Room for a family home and a garden.",
    },
    LotInfo {
        name: "Lakeside Retreat",
        size: "30 x 40",
        price: 12_000,
        blurb: "Scenic waterfront - more space, higher bills.",
    },
    LotInfo {
        name: "Downtown Loft",
        size: "25 x 25",
        price: 15_000,
        blurb: "Central and pricey, close to everything.",
    },
];

/// The lot the player has bought (kept for later use; the lot geometry is the
/// demo lot for now).
#[derive(Resource, Default)]
pub struct PurchasedLot {
    pub name: String,
}

/// The highlighted lot in the chooser.
#[derive(Resource, Default)]
struct LotCursor {
    index: usize,
}

#[derive(Component)]
struct LotSelectRoot;

/// Move the cursor (Up/Down/W/S or number keys) and buy with Enter.
fn lot_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut cursor: ResMut<LotCursor>,
    mut money: ResMut<MoneyResource>,
    mut purchased: ResMut<PurchasedLot>,
    mut next_state: ResMut<NextState<GameState>>,
) {
    let n = LOTS.len();
    if keyboard.any_just_pressed([KeyCode::ArrowDown, KeyCode::KeyS]) {
        cursor.index = (cursor.index + 1) % n;
    }
    if keyboard.any_just_pressed([KeyCode::ArrowUp, KeyCode::KeyW]) {
        cursor.index = (cursor.index + n - 1) % n;
    }
    for (i, key) in [
        KeyCode::Digit1,
        KeyCode::Digit2,
        KeyCode::Digit3,
        KeyCode::Digit4,
    ]
    .iter()
    .enumerate()
    .take(n)
    {
        if keyboard.just_pressed(*key) {
            cursor.index = i;
        }
    }

    if keyboard.just_pressed(KeyCode::Enter) {
        let lot = &LOTS[cursor.index];
        if money.spend(lot.price) {
            purchased.name = lot.name.to_string();
            next_state.set(GameState::LiveMode);
        }
    }
}

/// Rebuild the chooser when the cursor moves (or it's first shown).
fn render_lot_select(
    mut commands: Commands,
    cursor: Res<LotCursor>,
    money: Res<MoneyResource>,
    roots: Query<Entity, With<LotSelectRoot>>,
) {
    if !cursor.is_changed() && !money.is_changed() && !roots.is_empty() {
        return;
    }
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }

    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    justify_content: JustifyContent::Center,
                    row_gap: Val::Px(8.0),
                    ..default()
                },
                background_color: Color::srgba(0.05, 0.08, 0.12, 0.96).into(),
                ..default()
            },
            LotSelectRoot,
            Name::new("Lot Select"),
        ))
        .with_children(|root| {
            text(root, "Choose Your Lot", 34.0, Color::WHITE);
            text(
                root,
                &format!("Funds: {}", format_money(money.amount)),
                18.0,
                Color::srgb(0.7, 1.0, 0.75),
            );
            for (i, lot) in LOTS.iter().enumerate() {
                let selected = i == cursor.index;
                let affordable = money.amount >= lot.price;
                let marker = if selected { ">" } else { " " };
                let price = if affordable {
                    format_money(lot.price)
                } else {
                    format!("{} (too expensive)", format_money(lot.price))
                };
                let color = if selected {
                    Color::srgb(0.5, 0.95, 0.6)
                } else if affordable {
                    Color::srgb(0.82, 0.88, 0.95)
                } else {
                    Color::srgb(0.7, 0.45, 0.45)
                };
                text(
                    root,
                    &format!(
                        "{marker} {}. {}  [{}]  {}",
                        i + 1,
                        lot.name,
                        lot.size,
                        price
                    ),
                    20.0,
                    color,
                );
                if selected {
                    text(
                        root,
                        &format!("     {}", lot.blurb),
                        14.0,
                        Color::srgb(0.75, 0.8, 0.88),
                    );
                }
            }
            text(
                root,
                "Up/Down or 1-4 to choose   [Enter] Buy & move in",
                14.0,
                Color::srgba(0.8, 0.86, 0.95, 0.85),
            );
        });
}

fn exit_lot_select(mut commands: Commands, roots: Query<Entity, With<LotSelectRoot>>) {
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
}

fn text(parent: &mut ChildBuilder, value: &str, size: f32, color: Color) {
    parent.spawn(TextBundle::from_section(
        value,
        TextStyle {
            font_size: size,
            color,
            ..default()
        },
    ));
}

/// Registers the lot selection screen.
pub struct LotSelectPlugin;

impl Plugin for LotSelectPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<LotCursor>()
            .init_resource::<PurchasedLot>()
            .add_systems(OnExit(GameState::LotSelect), exit_lot_select)
            .add_systems(
                Update,
                (lot_input, render_lot_select).run_if(in_state(GameState::LotSelect)),
            );
    }
}
