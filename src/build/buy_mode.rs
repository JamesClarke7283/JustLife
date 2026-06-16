use bevy::prelude::*;

use crate::core::resources::GameSpeed;
use crate::core::state::GameState;
use crate::world::catalog::{CatalogCategory, CatalogDatabase};

/// Buy mode: enter with `V` to browse and select objects from the catalog.
pub struct BuyModePlugin;

impl Plugin for BuyModePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<BuyCatalogState>()
            .init_resource::<PreBuySpeed>()
            .add_systems(Update, toggle_buy_mode)
            .add_systems(OnEnter(GameState::BuyMode), enter_buy_mode)
            .add_systems(OnExit(GameState::BuyMode), exit_buy_mode)
            .add_systems(
                Update,
                (
                    category_tab_clicks,
                    item_entry_clicks,
                    rebuild_item_list,
                    update_detail,
                    highlight_buttons,
                )
                    .run_if(in_state(GameState::BuyMode)),
            );
    }
}

/// Which category is shown and which item is selected for placement.
#[derive(Resource)]
pub struct BuyCatalogState {
    pub category: CatalogCategory,
    pub selected: Option<String>,
    /// Set when the item list needs to be (re)built (panel opened or category
    /// changed). Cleared once `rebuild_item_list` repopulates the list.
    rebuild: bool,
}

impl Default for BuyCatalogState {
    fn default() -> Self {
        Self {
            category: CatalogCategory::Comfort,
            selected: None,
            rebuild: true,
        }
    }
}

/// Remembers the game speed to restore when leaving buy mode.
#[derive(Resource, Default)]
struct PreBuySpeed(GameSpeed);

#[derive(Component)]
struct BuyModeUi;

#[derive(Component)]
struct CategoryTab(CatalogCategory);

#[derive(Component)]
struct ItemEntry(String);

#[derive(Component)]
struct ItemListRoot;

#[derive(Component)]
struct DetailText;

const PANEL_BG: Color = Color::srgba(0.08, 0.10, 0.16, 0.94);
const TAB_BG: Color = Color::srgb(0.18, 0.22, 0.30);
const TAB_ACTIVE: Color = Color::srgb(0.30, 0.55, 0.85);
const ITEM_BG: Color = Color::srgb(0.14, 0.17, 0.24);
const ITEM_SELECTED: Color = Color::srgb(0.25, 0.45, 0.35);

/// Toggle buy mode with the `V` key.
fn toggle_buy_mode(
    keyboard: Res<ButtonInput<KeyCode>>,
    state: Res<State<GameState>>,
    mut next: ResMut<NextState<GameState>>,
) {
    if !keyboard.just_pressed(KeyCode::KeyV) {
        return;
    }
    match state.get() {
        GameState::BuyMode => next.set(GameState::LiveMode),
        GameState::LiveMode | GameState::BuildMode => next.set(GameState::BuyMode),
        _ => {}
    }
}

fn enter_buy_mode(
    mut commands: Commands,
    mut speed: ResMut<GameSpeed>,
    mut pre: ResMut<PreBuySpeed>,
    mut buy: ResMut<BuyCatalogState>,
    catalog: Res<CatalogDatabase>,
) {
    pre.0 = *speed;
    *speed = GameSpeed::Pause;
    buy.selected = None;
    buy.rebuild = true;

    // Categories that actually have items, for the tab row.
    let categories: Vec<CatalogCategory> = CatalogCategory::ALL
        .into_iter()
        .filter(|c| catalog.by_category(*c).next().is_some())
        .collect();
    if let Some(first) = categories.first() {
        buy.category = *first;
    }

    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    top: Val::Px(56.0),
                    right: Val::Px(0.0),
                    bottom: Val::Px(0.0),
                    width: Val::Px(330.0),
                    flex_direction: FlexDirection::Column,
                    padding: UiRect::all(Val::Px(10.0)),
                    row_gap: Val::Px(8.0),
                    ..default()
                },
                background_color: PANEL_BG.into(),
                ..default()
            },
            BuyModeUi,
            Name::new("Buy Mode Panel"),
        ))
        .with_children(|panel| {
            panel.spawn(TextBundle::from_section(
                "BUY MODE  —  press V to exit",
                TextStyle {
                    font_size: 20.0,
                    color: Color::WHITE,
                    ..default()
                },
            ));

            // Category tab row (wrapping).
            panel
                .spawn(NodeBundle {
                    style: Style {
                        flex_direction: FlexDirection::Row,
                        flex_wrap: FlexWrap::Wrap,
                        column_gap: Val::Px(4.0),
                        row_gap: Val::Px(4.0),
                        ..default()
                    },
                    ..default()
                })
                .with_children(|row| {
                    for category in categories {
                        row.spawn((
                            ButtonBundle {
                                style: Style {
                                    padding: UiRect::axes(Val::Px(7.0), Val::Px(4.0)),
                                    ..default()
                                },
                                background_color: TAB_BG.into(),
                                ..default()
                            },
                            CategoryTab(category),
                        ))
                        .with_children(|b| {
                            b.spawn(TextBundle::from_section(
                                category.label(),
                                TextStyle {
                                    font_size: 13.0,
                                    color: Color::srgb(0.9, 0.92, 0.96),
                                    ..default()
                                },
                            ));
                        });
                    }
                });

            // Item list (populated by rebuild_item_list).
            panel.spawn((
                NodeBundle {
                    style: Style {
                        flex_direction: FlexDirection::Column,
                        row_gap: Val::Px(4.0),
                        flex_grow: 1.0,
                        overflow: Overflow::clip_y(),
                        ..default()
                    },
                    ..default()
                },
                ItemListRoot,
            ));

            // Detail line for the selected item.
            panel.spawn((
                TextBundle::from_section(
                    "Select an item to see its details.",
                    TextStyle {
                        font_size: 14.0,
                        color: Color::srgb(0.85, 0.9, 0.7),
                        ..default()
                    },
                ),
                DetailText,
            ));
        });
}

fn exit_buy_mode(
    mut commands: Commands,
    mut speed: ResMut<GameSpeed>,
    pre: Res<PreBuySpeed>,
    panels: Query<Entity, With<BuyModeUi>>,
) {
    *speed = pre.0;
    for entity in &panels {
        commands.entity(entity).despawn_recursive();
    }
}

/// Switch category when a tab is clicked.
fn category_tab_clicks(
    mut buy: ResMut<BuyCatalogState>,
    tabs: Query<(&Interaction, &CategoryTab), Changed<Interaction>>,
) {
    for (interaction, tab) in &tabs {
        if *interaction == Interaction::Pressed && buy.category != tab.0 {
            buy.category = tab.0;
            buy.selected = None;
            buy.rebuild = true;
        }
    }
}

/// Select an item when its entry is clicked.
fn item_entry_clicks(
    mut buy: ResMut<BuyCatalogState>,
    entries: Query<(&Interaction, &ItemEntry), Changed<Interaction>>,
) {
    for (interaction, entry) in &entries {
        if *interaction == Interaction::Pressed {
            buy.selected = Some(entry.0.clone());
        }
    }
}

/// Repopulate the item list when the category changes.
fn rebuild_item_list(
    mut commands: Commands,
    mut buy: ResMut<BuyCatalogState>,
    catalog: Res<CatalogDatabase>,
    list_root: Query<Entity, With<ItemListRoot>>,
    existing: Query<Entity, With<ItemEntry>>,
) {
    if !buy.rebuild {
        return;
    }
    // Wait until the panel's list container exists (it spawns via commands).
    let Ok(root) = list_root.get_single() else {
        return;
    };
    buy.rebuild = false;
    for entity in &existing {
        commands.entity(entity).despawn_recursive();
    }

    let mut items: Vec<_> = catalog.by_category(buy.category).collect();
    items.sort_by_key(|i| i.price);

    commands.entity(root).with_children(|list| {
        for item in items {
            list.spawn((
                ButtonBundle {
                    style: Style {
                        flex_direction: FlexDirection::Column,
                        padding: UiRect::all(Val::Px(6.0)),
                        ..default()
                    },
                    background_color: ITEM_BG.into(),
                    ..default()
                },
                ItemEntry(item.id.clone()),
            ))
            .with_children(|b| {
                b.spawn(TextBundle::from_section(
                    item.name.clone(),
                    TextStyle {
                        font_size: 15.0,
                        color: Color::WHITE,
                        ..default()
                    },
                ));
                b.spawn(TextBundle::from_section(
                    format!(
                        "${}   {}x{}",
                        item.price, item.footprint.0, item.footprint.1
                    ),
                    TextStyle {
                        font_size: 12.0,
                        color: Color::srgb(0.7, 0.78, 0.9),
                        ..default()
                    },
                ));
            });
        }
    });
}

/// Update the detail line for the currently selected item.
fn update_detail(
    buy: Res<BuyCatalogState>,
    catalog: Res<CatalogDatabase>,
    mut detail: Query<&mut Text, With<DetailText>>,
) {
    if !buy.is_changed() {
        return;
    }
    let Ok(mut text) = detail.get_single_mut() else {
        return;
    };
    let value = match buy.selected.as_deref().and_then(|id| catalog.get(id)) {
        Some(item) => {
            let needs = if item.actions.is_empty() {
                "decorative".to_string()
            } else {
                item.actions
                    .iter()
                    .map(|a| format!("{:?}", a.need))
                    .collect::<Vec<_>>()
                    .join(", ")
            };
            format!(
                "{}\n${} | size {}x{} | needs: {}\n{}",
                item.name, item.price, item.footprint.0, item.footprint.1, needs, item.description
            )
        }
        None => "Select an item to see its details.".to_string(),
    };
    text.sections[0].value = value;
}

/// Highlight the active category tab and the selected item.
fn highlight_buttons(
    buy: Res<BuyCatalogState>,
    mut tabs: Query<(&CategoryTab, &mut BackgroundColor), Without<ItemEntry>>,
    mut entries: Query<(&ItemEntry, &mut BackgroundColor), Without<CategoryTab>>,
) {
    for (tab, mut bg) in &mut tabs {
        *bg = if tab.0 == buy.category {
            TAB_ACTIVE.into()
        } else {
            TAB_BG.into()
        };
    }
    for (entry, mut bg) in &mut entries {
        *bg = if Some(&entry.0) == buy.selected.as_ref() {
            ITEM_SELECTED.into()
        } else {
            ITEM_BG.into()
        };
    }
}
