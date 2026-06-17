//! Main menu (Phase 10.1).
//!
//! A title screen layered over the live 3D lot (which renders as a slowly
//! panning backdrop). Buttons - New Game, Load Game, Options, Quit - respond to
//! the mouse and to keyboard shortcuts so the menu is reachable in the headless
//! WASM harness (Enter/N start a game, O opens options, Esc/Q quit/back).

use bevy::app::AppExit;
use bevy::prelude::*;

use crate::core::state::GameState;
use crate::render::camera::{CameraRig, IsometricCamera};

/// Radians per second the backdrop camera drifts while on the menu.
const MENU_PAN_SPEED: f32 = 0.08;

/// Which menu screen is currently shown.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq)]
enum MenuScreen {
    #[default]
    Root,
    Options,
}

/// Marks the menu UI root so it can be torn down and rebuilt between screens.
#[derive(Component)]
struct MenuRoot;

/// A clickable menu button and the action it triggers.
#[derive(Component, Clone, Copy, PartialEq, Eq)]
enum MenuButton {
    NewGame,
    LoadGame,
    Options,
    Back,
    Quit,
}

/// An action raised by a button click or keyboard shortcut.
#[derive(Event, Clone, Copy)]
struct MenuAction(MenuButton);

const BUTTON_IDLE: Color = Color::srgba(0.16, 0.34, 0.24, 0.95);
const BUTTON_HOVER: Color = Color::srgba(0.26, 0.52, 0.36, 0.98);

/// Build the menu UI for the given screen under a fresh `MenuRoot`.
fn spawn_menu(commands: &mut Commands, asset_server: &AssetServer, screen: MenuScreen) {
    let root = commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    justify_content: JustifyContent::Center,
                    row_gap: Val::Px(14.0),
                    ..default()
                },
                // Dim the backdrop so the 3D lot reads as a soft background.
                background_color: Color::srgba(0.04, 0.07, 0.10, 0.55).into(),
                ..default()
            },
            MenuRoot,
            Name::new("Main Menu"),
        ))
        .id();

    commands.entity(root).with_children(|parent| match screen {
        MenuScreen::Root => build_root(parent, asset_server),
        MenuScreen::Options => build_options(parent),
    });
}

/// The title screen: logo plus the four primary buttons.
fn build_root(parent: &mut ChildBuilder, asset_server: &AssetServer) {
    parent.spawn(ImageBundle {
        image: UiImage::new(asset_server.load("textures/ui_logo.png")),
        style: Style {
            width: Val::Px(460.0),
            height: Val::Px(255.0),
            margin: UiRect::bottom(Val::Px(10.0)),
            ..default()
        },
        ..default()
    });

    for (button, label) in [
        (MenuButton::NewGame, "New Game"),
        (MenuButton::LoadGame, "Load Game"),
        (MenuButton::Options, "Options"),
        (MenuButton::Quit, "Quit"),
    ] {
        spawn_button(parent, button, label);
    }

    parent.spawn(TextBundle::from_section(
        "Enter / N: New Game    O: Options    Esc / Q: Quit",
        TextStyle {
            font_size: 14.0,
            color: Color::srgba(0.85, 0.92, 1.0, 0.8),
            ..default()
        },
    ));
}

/// The options screen: placeholder settings rows plus a Back button.
fn build_options(parent: &mut ChildBuilder) {
    parent.spawn(TextBundle::from_section(
        "Options",
        TextStyle {
            font_size: 34.0,
            color: Color::WHITE,
            ..default()
        },
    ));
    for row in [
        "Resolution:  1280 x 800",
        "Volume:      80%",
        "Controls:    WASD pan, wheel zoom, Q pie menu",
        "Language:    English",
    ] {
        parent.spawn(TextBundle::from_section(
            row,
            TextStyle {
                font_size: 18.0,
                color: Color::srgb(0.85, 0.92, 1.0),
                ..default()
            },
        ));
    }
    spawn_button(parent, MenuButton::Back, "Back");
    parent.spawn(TextBundle::from_section(
        "Esc / B: Back",
        TextStyle {
            font_size: 14.0,
            color: Color::srgba(0.85, 0.92, 1.0, 0.8),
            ..default()
        },
    ));
}

/// Spawn one styled menu button.
fn spawn_button(parent: &mut ChildBuilder, button: MenuButton, label: &str) {
    parent
        .spawn((
            ButtonBundle {
                style: Style {
                    width: Val::Px(240.0),
                    height: Val::Px(46.0),
                    align_items: AlignItems::Center,
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                background_color: BUTTON_IDLE.into(),
                border_radius: BorderRadius::all(Val::Px(8.0)),
                ..default()
            },
            button,
        ))
        .with_children(|b| {
            b.spawn(TextBundle::from_section(
                label,
                TextStyle {
                    font_size: 22.0,
                    color: Color::WHITE,
                    ..default()
                },
            ));
        });
}

/// Spawn the root menu when entering the main menu state.
fn enter_main_menu(
    mut commands: Commands,
    mut screen: ResMut<MenuScreen>,
    asset_server: Res<AssetServer>,
) {
    *screen = MenuScreen::Root;
    spawn_menu(&mut commands, &asset_server, MenuScreen::Root);
}

/// Tear down the menu when leaving the main menu state.
fn exit_main_menu(mut commands: Commands, roots: Query<Entity, With<MenuRoot>>) {
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
}

/// Translate button clicks into menu actions (and drive hover colours).
fn button_interaction(
    mut interactions: Query<
        (&Interaction, &MenuButton, &mut BackgroundColor),
        Changed<Interaction>,
    >,
    mut actions: EventWriter<MenuAction>,
) {
    for (interaction, button, mut color) in &mut interactions {
        match interaction {
            Interaction::Pressed => {
                actions.send(MenuAction(*button));
            }
            Interaction::Hovered => *color = BUTTON_HOVER.into(),
            Interaction::None => *color = BUTTON_IDLE.into(),
        }
    }
}

/// Keyboard shortcuts for the menu.
fn menu_keyboard(
    keyboard: Res<ButtonInput<KeyCode>>,
    screen: Res<MenuScreen>,
    mut actions: EventWriter<MenuAction>,
) {
    match *screen {
        MenuScreen::Root => {
            if keyboard.any_just_pressed([KeyCode::Enter, KeyCode::KeyN]) {
                actions.send(MenuAction(MenuButton::NewGame));
            } else if keyboard.just_pressed(KeyCode::KeyO) {
                actions.send(MenuAction(MenuButton::Options));
            } else if keyboard.any_just_pressed([KeyCode::KeyQ, KeyCode::Escape]) {
                actions.send(MenuAction(MenuButton::Quit));
            }
        }
        MenuScreen::Options => {
            if keyboard.any_just_pressed([KeyCode::Escape, KeyCode::KeyB]) {
                actions.send(MenuAction(MenuButton::Back));
            }
        }
    }
}

/// Apply menu actions: start the game, switch screens, or quit.
fn apply_menu_action(
    mut events: EventReader<MenuAction>,
    mut commands: Commands,
    mut screen: ResMut<MenuScreen>,
    mut next_state: ResMut<NextState<GameState>>,
    mut exit: EventWriter<AppExit>,
    asset_server: Res<AssetServer>,
    roots: Query<Entity, With<MenuRoot>>,
) {
    for MenuAction(button) in events.read() {
        match button {
            MenuButton::NewGame => next_state.set(GameState::CreateASim),
            MenuButton::LoadGame => info!("Load Game: no saves yet"),
            MenuButton::Options => {
                *screen = MenuScreen::Options;
                rebuild(&mut commands, &asset_server, &roots, *screen);
            }
            MenuButton::Back => {
                *screen = MenuScreen::Root;
                rebuild(&mut commands, &asset_server, &roots, *screen);
            }
            MenuButton::Quit => {
                exit.send(AppExit::Success);
            }
        }
    }
}

/// Despawn the current menu root and respawn it for `screen`.
fn rebuild(
    commands: &mut Commands,
    asset_server: &AssetServer,
    roots: &Query<Entity, With<MenuRoot>>,
    screen: MenuScreen,
) {
    for entity in roots {
        commands.entity(entity).despawn_recursive();
    }
    spawn_menu(commands, asset_server, screen);
}

/// Slowly orbit the backdrop camera while the menu is up.
fn menu_camera_pan(time: Res<Time>, mut rigs: Query<&mut CameraRig, With<IsometricCamera>>) {
    for mut rig in &mut rigs {
        rig.yaw += MENU_PAN_SPEED * time.delta_seconds();
    }
}

/// Registers the main menu.
pub struct MainMenuPlugin;

impl Plugin for MainMenuPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<MenuScreen>()
            .add_event::<MenuAction>()
            .add_systems(OnEnter(GameState::MainMenu), enter_main_menu)
            .add_systems(OnExit(GameState::MainMenu), exit_main_menu)
            .add_systems(
                Update,
                (
                    button_interaction,
                    menu_keyboard,
                    apply_menu_action,
                    menu_camera_pan,
                )
                    .run_if(in_state(GameState::MainMenu)),
            );
    }
}
