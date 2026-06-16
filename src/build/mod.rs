use bevy::prelude::*;

use crate::core::resources::GameSpeed;
use crate::core::state::GameState;
use crate::render::grid::GridOverlay;

pub mod room_tool;

/// The active build-mode tool (selected with number keys / toolbar).
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq)]
pub enum BuildTool {
    #[default]
    Wall,
    Room,
}

impl BuildTool {
    fn label(&self) -> &'static str {
        match self {
            BuildTool::Wall => "Wall",
            BuildTool::Room => "Room",
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
        ))
        .init_resource::<PreBuildSpeed>()
        .init_resource::<BuildTool>()
        .add_systems(Update, toggle_build_mode)
        .add_systems(
            Update,
            (select_build_tool, update_tool_label).run_if(in_state(GameState::BuildMode)),
        )
        .add_systems(OnEnter(GameState::BuildMode), enter_build_mode)
        .add_systems(OnExit(GameState::BuildMode), exit_build_mode);
    }
}

/// Remembers the live-mode game speed so it can be restored on exit.
#[derive(Resource, Default)]
struct PreBuildSpeed(GameSpeed);

/// Marker for the build-mode toolbar UI root.
#[derive(Component)]
struct BuildModeUi;

/// Marker for the toolbar text that shows the active tool.
#[derive(Component)]
struct BuildToolLabel;

/// Select the active build tool with the number keys.
fn select_build_tool(keyboard: Res<ButtonInput<KeyCode>>, mut tool: ResMut<BuildTool>) {
    if keyboard.just_pressed(KeyCode::Digit1) {
        *tool = BuildTool::Wall;
    }
    if keyboard.just_pressed(KeyCode::Digit2) {
        *tool = BuildTool::Room;
    }
}

/// Keep the toolbar's tool label in sync with the active tool.
fn update_tool_label(tool: Res<BuildTool>, mut labels: Query<&mut Text, With<BuildToolLabel>>) {
    if !tool.is_changed() {
        return;
    }
    for mut text in &mut labels {
        text.sections[0].value = format!("Tool: {}   [1] Wall   [2] Room", tool.label());
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
    mut grids: Query<(&mut GridOverlay, &mut Visibility)>,
) {
    pre.0 = *speed;
    *speed = GameSpeed::Pause;
    *tool = BuildTool::Wall;

    for (mut grid, mut visibility) in &mut grids {
        grid.visible = true;
        *visibility = Visibility::Visible;
    }

    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    top: Val::Px(0.0),
                    left: Val::Px(0.0),
                    right: Val::Px(0.0),
                    padding: UiRect::all(Val::Px(12.0)),
                    align_items: AlignItems::Center,
                    column_gap: Val::Px(12.0),
                    ..default()
                },
                background_color: Color::srgba(0.10, 0.30, 0.50, 0.88).into(),
                ..default()
            },
            BuildModeUi,
            Name::new("Build Mode Toolbar"),
        ))
        .with_children(|parent| {
            parent.spawn(TextBundle::from_section(
                "BUILD MODE",
                TextStyle {
                    font_size: 24.0,
                    color: Color::WHITE,
                    ..default()
                },
            ));
            parent.spawn(TextBundle::from_section(
                "press B to return to Live Mode",
                TextStyle {
                    font_size: 16.0,
                    color: Color::srgb(0.85, 0.92, 1.0),
                    ..default()
                },
            ));
            parent.spawn((
                TextBundle::from_section(
                    "Tool: Wall   [1] Wall   [2] Room",
                    TextStyle {
                        font_size: 16.0,
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
