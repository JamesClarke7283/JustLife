use bevy::prelude::*;

use crate::build::history::HistoryRequest;
use crate::career::economy::format_money;
use crate::core::resources::{GameSpeed, MoneyResource};
use crate::core::state::GameState;
use crate::render::grid::GridOverlay;

pub mod buy_mode;
pub mod confirm;
pub mod history;
pub mod materials;
pub mod placement;
pub mod room_tool;

/// The active build-mode tool (selected with number keys / toolbar).
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq)]
pub enum BuildTool {
    #[default]
    Wall,
    Room,
    FloorPaint,
    WallPaint,
}

impl BuildTool {
    /// Tools in toolbar order, paired with their number-key shortcut.
    const ALL: [(BuildTool, u8); 4] = [
        (BuildTool::Wall, 1),
        (BuildTool::Room, 2),
        (BuildTool::FloorPaint, 3),
        (BuildTool::WallPaint, 4),
    ];

    fn label(&self) -> &'static str {
        match self {
            BuildTool::Wall => "Wall",
            BuildTool::Room => "Room",
            BuildTool::FloorPaint => "Floor Paint",
            BuildTool::WallPaint => "Wall Paint",
        }
    }

    /// One-line hint about what the tool does (shown in the options panel).
    fn hint(&self) -> &'static str {
        match self {
            BuildTool::Wall => "Drag to draw walls. R rotates, right-click sells.",
            BuildTool::Room => "Drag a rectangle to lay a room + floor.",
            BuildTool::FloorPaint => "Click tiles to paint the floor material.",
            BuildTool::WallPaint => "Click walls to paint their material.",
        }
    }
}

/// Build/Buy mode: enter with `B`, which pauses the simulation, shows the
/// buildable grid, and displays the build-mode toolbar.
pub struct BuildModePlugin;

impl Plugin for BuildModePlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((
            crate::world::wall_tool::WallToolPlugin,
            room_tool::RoomToolPlugin,
            buy_mode::BuyModePlugin,
            placement::PlacementPlugin,
            materials::MaterialPickerPlugin,
            history::BuildHistoryPlugin,
            confirm::PurchaseConfirmPlugin,
        ))
        .init_resource::<PreBuildSpeed>()
        .init_resource::<BuildTool>()
        .add_systems(Update, toggle_build_mode)
        .add_systems(
            Update,
            (
                select_build_tool,
                update_tool_label,
                tool_button_interaction,
                history_button_interaction,
                update_build_funds,
            )
                .run_if(in_state(GameState::BuildMode)),
        )
        .add_systems(OnEnter(GameState::BuildMode), enter_build_mode)
        .add_systems(OnExit(GameState::BuildMode), exit_build_mode);
    }
}

/// Remembers the live-mode game speed so it can be restored on exit.
#[derive(Resource, Default)]
struct PreBuildSpeed(GameSpeed);

/// Marker for the build-mode toolbar UI panels (all torn down on exit).
#[derive(Component)]
struct BuildModeUi;

/// Marker for the toolbar text that shows the active tool + hint.
#[derive(Component)]
struct BuildToolLabel;

/// A left-sidebar tool button.
#[derive(Component)]
struct ToolButton(BuildTool);

/// Toolbar undo/redo buttons.
#[derive(Component)]
struct HistoryButton(HistoryRequest);

/// The top-bar household funds readout.
#[derive(Component)]
struct BuildFundsLabel;

/// Select the active build tool with the number keys.
fn select_build_tool(keyboard: Res<ButtonInput<KeyCode>>, mut tool: ResMut<BuildTool>) {
    if keyboard.just_pressed(KeyCode::Digit1) {
        *tool = BuildTool::Wall;
    }
    if keyboard.just_pressed(KeyCode::Digit2) {
        *tool = BuildTool::Room;
    }
    if keyboard.just_pressed(KeyCode::Digit3) {
        *tool = BuildTool::FloorPaint;
    }
    if keyboard.just_pressed(KeyCode::Digit4) {
        *tool = BuildTool::WallPaint;
    }
}

/// Keep the options panel's tool label/hint in sync with the active tool.
fn update_tool_label(tool: Res<BuildTool>, mut labels: Query<&mut Text, With<BuildToolLabel>>) {
    if !tool.is_changed() {
        return;
    }
    for mut text in &mut labels {
        text.sections[0].value = format!("Tool: {} - {}", tool.label(), tool.hint());
    }
}

/// Click a sidebar tool button to select it; highlight the active tool.
fn tool_button_interaction(
    mut tool: ResMut<BuildTool>,
    mut buttons: Query<(&Interaction, &ToolButton, &mut BackgroundColor)>,
) {
    for (interaction, button, mut color) in &mut buttons {
        if *interaction == Interaction::Pressed {
            *tool = button.0;
        }
        *color = if *tool == button.0 {
            Color::srgb(0.95, 0.78, 0.30).into()
        } else if *interaction == Interaction::Hovered {
            Color::srgba(0.3, 0.45, 0.6, 0.95).into()
        } else {
            Color::srgba(0.2, 0.32, 0.42, 0.95).into()
        };
    }
}

/// Click the Undo/Redo toolbar buttons to drive the build history.
fn history_button_interaction(
    mut buttons: Query<(&Interaction, &HistoryButton, &mut BackgroundColor), Changed<Interaction>>,
    mut requests: EventWriter<HistoryRequest>,
) {
    for (interaction, button, mut color) in &mut buttons {
        match interaction {
            Interaction::Pressed => {
                requests.send(button.0);
                *color = Color::srgba(0.15, 0.3, 0.45, 1.0).into();
            }
            Interaction::Hovered => *color = Color::srgba(0.3, 0.5, 0.7, 0.95).into(),
            Interaction::None => *color = Color::srgba(0.2, 0.4, 0.6, 0.95).into(),
        }
    }
}

/// Keep the top-bar funds readout current.
fn update_build_funds(
    money: Res<MoneyResource>,
    mut labels: Query<&mut Text, With<BuildFundsLabel>>,
) {
    if !money.is_changed() {
        return;
    }
    for mut text in &mut labels {
        text.sections[0].value = format_money(money.amount);
    }
}

/// Press `B` to toggle between Live and Build mode.
fn toggle_build_mode(
    keyboard: Res<ButtonInput<KeyCode>>,
    state: Res<State<GameState>>,
    mut next: ResMut<NextState<GameState>>,
) {
    if !keyboard.just_pressed(KeyCode::KeyB) {
        return;
    }
    match state.get() {
        GameState::LiveMode => next.set(GameState::BuildMode),
        GameState::BuildMode => next.set(GameState::LiveMode),
        // Ignore in menus / CAS / loading.
        _ => {}
    }
}

/// Entering build mode: pause the sim, reveal the grid, spawn the toolbar.
fn enter_build_mode(
    mut commands: Commands,
    mut speed: ResMut<GameSpeed>,
    mut pre: ResMut<PreBuildSpeed>,
    mut tool: ResMut<BuildTool>,
    money: Res<MoneyResource>,
    mut grids: Query<(&mut GridOverlay, &mut Visibility)>,
) {
    pre.0 = *speed;
    *speed = GameSpeed::Pause;
    *tool = BuildTool::Wall;

    for (mut grid, mut visibility) in &mut grids {
        grid.visible = true;
        *visibility = Visibility::Visible;
    }

    spawn_top_bar(&mut commands, money.amount);
    spawn_tool_sidebar(&mut commands);
    spawn_options_panel(&mut commands);
}

/// Top bar: mode indicator, funds, and undo/redo buttons.
fn spawn_top_bar(commands: &mut Commands, funds: i64) {
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    top: Val::Px(0.0),
                    left: Val::Px(0.0),
                    right: Val::Px(0.0),
                    padding: UiRect::all(Val::Px(10.0)),
                    align_items: AlignItems::Center,
                    column_gap: Val::Px(16.0),
                    ..default()
                },
                background_color: Color::srgba(0.10, 0.30, 0.50, 0.9).into(),
                ..default()
            },
            BuildModeUi,
            Name::new("Build Top Bar"),
        ))
        .with_children(|bar| {
            bar.spawn(TextBundle::from_section(
                "BUILD MODE",
                TextStyle {
                    font_size: 22.0,
                    color: Color::WHITE,
                    ..default()
                },
            ));
            bar.spawn((
                TextBundle::from_section(
                    format_money(funds),
                    TextStyle {
                        font_size: 18.0,
                        color: Color::srgb(0.7, 1.0, 0.75),
                        ..default()
                    },
                ),
                BuildFundsLabel,
            ));
            top_bar_button(bar, HistoryRequest::Undo, "Undo");
            top_bar_button(bar, HistoryRequest::Redo, "Redo");
            bar.spawn(TextBundle::from_section(
                "B: Live   V: Buy",
                TextStyle {
                    font_size: 14.0,
                    color: Color::srgb(0.85, 0.92, 1.0),
                    ..default()
                },
            ));
        });
}

fn top_bar_button(bar: &mut ChildBuilder, request: HistoryRequest, label: &str) {
    bar.spawn((
        ButtonBundle {
            style: Style {
                padding: UiRect::axes(Val::Px(10.0), Val::Px(5.0)),
                ..default()
            },
            background_color: Color::srgba(0.2, 0.4, 0.6, 0.95).into(),
            border_radius: BorderRadius::all(Val::Px(4.0)),
            ..default()
        },
        HistoryButton(request),
    ))
    .with_children(|b| {
        b.spawn(TextBundle::from_section(
            label,
            TextStyle {
                font_size: 15.0,
                color: Color::WHITE,
                ..default()
            },
        ));
    });
}

/// Left sidebar: one button per build tool.
fn spawn_tool_sidebar(commands: &mut Commands) {
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Px(8.0),
                    top: Val::Px(60.0),
                    flex_direction: FlexDirection::Column,
                    padding: UiRect::all(Val::Px(8.0)),
                    row_gap: Val::Px(6.0),
                    ..default()
                },
                background_color: Color::srgba(0.08, 0.16, 0.24, 0.9).into(),
                border_radius: BorderRadius::all(Val::Px(6.0)),
                ..default()
            },
            BuildModeUi,
            Name::new("Build Tool Sidebar"),
        ))
        .with_children(|side| {
            side.spawn(TextBundle::from_section(
                "Tools",
                TextStyle {
                    font_size: 14.0,
                    color: Color::srgb(0.8, 0.88, 0.95),
                    ..default()
                },
            ));
            for (build_tool, digit) in BuildTool::ALL {
                side.spawn((
                    ButtonBundle {
                        style: Style {
                            width: Val::Px(132.0),
                            height: Val::Px(34.0),
                            align_items: AlignItems::Center,
                            padding: UiRect::horizontal(Val::Px(8.0)),
                            ..default()
                        },
                        background_color: Color::srgba(0.2, 0.32, 0.42, 0.95).into(),
                        border_radius: BorderRadius::all(Val::Px(4.0)),
                        ..default()
                    },
                    ToolButton(build_tool),
                ))
                .with_children(|b| {
                    b.spawn(TextBundle::from_section(
                        format!("{digit}  {}", build_tool.label()),
                        TextStyle {
                            font_size: 15.0,
                            color: Color::WHITE,
                            ..default()
                        },
                    ));
                });
            }
        });
}

/// Bottom panel: options/hint for the selected tool.
fn spawn_options_panel(commands: &mut Commands) {
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Px(8.0),
                    bottom: Val::Px(8.0),
                    padding: UiRect::all(Val::Px(8.0)),
                    ..default()
                },
                background_color: Color::srgba(0.08, 0.16, 0.24, 0.9).into(),
                border_radius: BorderRadius::all(Val::Px(6.0)),
                ..default()
            },
            BuildModeUi,
            Name::new("Build Options Panel"),
        ))
        .with_children(|panel| {
            panel.spawn((
                TextBundle::from_section(
                    "Tool: Wall - Drag to draw walls. R rotates, right-click sells.",
                    TextStyle {
                        font_size: 15.0,
                        color: Color::srgb(1.0, 0.95, 0.7),
                        ..default()
                    },
                ),
                BuildToolLabel,
            ));
        });
}

/// Leaving build mode: restore the simulation speed and remove the toolbar.
fn exit_build_mode(
    mut commands: Commands,
    mut speed: ResMut<GameSpeed>,
    pre: Res<PreBuildSpeed>,
    toolbars: Query<Entity, With<BuildModeUi>>,
) {
    *speed = pre.0;
    for entity in &toolbars {
        commands.entity(entity).despawn_recursive();
    }
}
