//! Time control (Phase 10.9).
//!
//! The HUD already shows clickable pause/1x/2x/4x speed buttons (10.2). This
//! adds keyboard control (0 pause, 1/2/3 speed, Space toggle), a slight screen
//! dim while paused, and auto-ultra while the player sim sleeps (to skip the
//! night). The active speed is highlighted by the HUD's speed buttons.

use bevy::prelude::*;

use crate::core::resources::GameSpeed;
use crate::core::state::GameState;
use crate::sim::{AnimationState, SimManager};
use crate::ui::pie_menu::PieMenuState;

/// Remembers the speed before a Space-pause so it can be restored.
#[derive(Resource, Default)]
struct PrePauseSpeed(Option<GameSpeed>);

/// Whether the current Ultra speed was auto-engaged for sleep.
#[derive(Resource, Default)]
struct AutoUltra(bool);

/// Whether the game was auto-paused because the browser tab lost focus.
#[derive(Resource, Default)]
struct BlurPaused(bool);

/// Pause the game when the window/tab loses focus and resume on return - but
/// only auto-resume pauses we caused, so a manual pause is respected (Phase 12.2,
/// browser tab focus/blur handling).
fn pause_on_blur(
    mut focus_events: EventReader<bevy::window::WindowFocused>,
    mut speed: ResMut<GameSpeed>,
    mut pre: ResMut<PrePauseSpeed>,
    mut blur: ResMut<BlurPaused>,
) {
    for event in focus_events.read() {
        if !event.focused {
            if *speed != GameSpeed::Pause {
                pre.0 = Some(*speed);
                *speed = GameSpeed::Pause;
                blur.0 = true;
            }
        } else if blur.0 {
            *speed = pre.0.take().unwrap_or(GameSpeed::Normal);
            blur.0 = false;
        }
    }
}

/// Full-screen dim shown while paused.
#[derive(Component)]
struct PauseDim;

/// Keyboard speed control (gated off while the pie menu eats number keys).
fn time_keys(
    keyboard: Res<ButtonInput<KeyCode>>,
    pie: Res<PieMenuState>,
    mut speed: ResMut<GameSpeed>,
    mut pre: ResMut<PrePauseSpeed>,
) {
    if keyboard.just_pressed(KeyCode::Space) {
        *speed = if *speed == GameSpeed::Pause {
            pre.0.take().unwrap_or(GameSpeed::Normal)
        } else {
            pre.0 = Some(*speed);
            GameSpeed::Pause
        };
    }
    if pie.open {
        return; // don't fight the pie menu's number-key selection
    }
    if keyboard.just_pressed(KeyCode::Digit0) {
        *speed = GameSpeed::Pause;
    }
    if keyboard.just_pressed(KeyCode::Digit1) {
        *speed = GameSpeed::Normal;
    }
    if keyboard.just_pressed(KeyCode::Digit2) {
        *speed = GameSpeed::Fast;
    }
    if keyboard.just_pressed(KeyCode::Digit3) {
        *speed = GameSpeed::Ultra;
    }
}

/// Show/hide a slight screen dim while paused (under the HUD via negative z).
fn pause_dim(
    mut commands: Commands,
    speed: Res<GameSpeed>,
    overlays: Query<Entity, With<PauseDim>>,
) {
    let paused = *speed == GameSpeed::Pause;
    match (paused, overlays.iter().next()) {
        (true, None) => {
            commands.spawn((
                NodeBundle {
                    style: Style {
                        position_type: PositionType::Absolute,
                        width: Val::Percent(100.0),
                        height: Val::Percent(100.0),
                        ..default()
                    },
                    background_color: Color::srgba(0.0, 0.0, 0.05, 0.28).into(),
                    z_index: ZIndex::Global(-1),
                    ..default()
                },
                PauseDim,
                Name::new("Pause Dim"),
            ));
        }
        (false, Some(_)) => {
            for entity in &overlays {
                commands.entity(entity).despawn_recursive();
            }
        }
        _ => {}
    }
}

/// While the player sim sleeps, auto-engage Ultra to skip the night; restore
/// Normal on waking (only undoing the speed we auto-set).
fn auto_ultra_sleep(
    manager: Res<SimManager>,
    sims: Query<&AnimationState>,
    mut speed: ResMut<GameSpeed>,
    mut auto: ResMut<AutoUltra>,
) {
    let sleeping = manager
        .sims
        .first()
        .and_then(|e| sims.get(*e).ok())
        .is_some_and(|a| *a == AnimationState::Sleeping);

    if sleeping && matches!(*speed, GameSpeed::Normal | GameSpeed::Fast) {
        *speed = GameSpeed::Ultra;
        auto.0 = true;
    } else if !sleeping && auto.0 {
        if *speed == GameSpeed::Ultra {
            *speed = GameSpeed::Normal;
        }
        auto.0 = false;
    }
}

/// Tear down the dim when leaving live mode.
fn clear_dim(mut commands: Commands, overlays: Query<Entity, With<PauseDim>>) {
    for entity in &overlays {
        commands.entity(entity).despawn_recursive();
    }
}

/// Registers time control (live mode only).
pub struct TimeControlPlugin;

impl Plugin for TimeControlPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PrePauseSpeed>()
            .init_resource::<AutoUltra>()
            .init_resource::<BlurPaused>()
            .add_systems(OnExit(GameState::LiveMode), clear_dim)
            .add_systems(
                Update,
                (time_keys, auto_ultra_sleep, pause_dim, pause_on_blur)
                    .run_if(in_state(GameState::LiveMode)),
            );
    }
}
