//! Toast notifications (Phase 10.7).
//!
//! Transient messages stack in the top-right and auto-dismiss after a few
//! seconds, colour-coded by severity (info/success/warning/error). Any system
//! emits one with `ToastEvent`; this module renders and expires them.

use bevy::prelude::*;

use crate::core::events::{ToastEvent, ToastKind};
use crate::core::state::GameState;

/// Seconds a toast stays on screen before fading out.
const TOAST_LIFETIME: f32 = 5.0;

/// The top-right container that stacks toasts.
#[derive(Component)]
struct ToastTray;

/// An individual toast with its remaining lifetime.
#[derive(Component)]
struct Toast {
    remaining: f32,
}

/// Accent colour for a toast kind.
fn kind_color(kind: ToastKind) -> Color {
    match kind {
        ToastKind::Info => Color::srgb(0.25, 0.50, 0.80),
        ToastKind::Success => Color::srgb(0.25, 0.62, 0.36),
        ToastKind::Warning => Color::srgb(0.80, 0.62, 0.20),
        ToastKind::Error => Color::srgb(0.74, 0.28, 0.26),
    }
}

/// Spawn the tray when live mode begins (below the clock).
fn spawn_tray(mut commands: Commands) {
    commands.spawn((
        NodeBundle {
            style: Style {
                position_type: PositionType::Absolute,
                right: Val::Px(12.0),
                top: Val::Px(86.0),
                width: Val::Px(280.0),
                flex_direction: FlexDirection::Column,
                align_items: AlignItems::FlexEnd,
                row_gap: Val::Px(6.0),
                ..default()
            },
            ..default()
        },
        ToastTray,
        Name::new("Toast Tray"),
    ));
}

/// Despawn the tray (and toasts) when leaving live mode.
fn despawn_tray(mut commands: Commands, trays: Query<Entity, With<ToastTray>>) {
    for entity in &trays {
        commands.entity(entity).despawn_recursive();
    }
}

/// Add a toast card per incoming `ToastEvent`.
fn spawn_toasts(
    mut commands: Commands,
    mut events: EventReader<ToastEvent>,
    trays: Query<Entity, With<ToastTray>>,
) {
    let Ok(tray) = trays.get_single() else {
        return;
    };
    for event in events.read() {
        commands.entity(tray).with_children(|tray| {
            tray.spawn((
                NodeBundle {
                    style: Style {
                        padding: UiRect::axes(Val::Px(12.0), Val::Px(8.0)),
                        max_width: Val::Px(280.0),
                        ..default()
                    },
                    background_color: kind_color(event.kind).with_alpha(0.94).into(),
                    border_radius: BorderRadius::all(Val::Px(6.0)),
                    ..default()
                },
                Toast {
                    remaining: TOAST_LIFETIME,
                },
            ))
            .with_children(|card| {
                card.spawn(TextBundle::from_section(
                    event.message.clone(),
                    TextStyle {
                        font_size: 15.0,
                        color: Color::WHITE,
                        ..default()
                    },
                ));
            });
        });
    }
}

/// Tick toast lifetimes, fading them out and despawning when expired.
fn tick_toasts(
    time: Res<Time>,
    mut commands: Commands,
    mut toasts: Query<(Entity, &mut Toast, &mut BackgroundColor)>,
) {
    for (entity, mut toast, mut color) in &mut toasts {
        toast.remaining -= time.delta_seconds();
        if toast.remaining <= 0.0 {
            commands.entity(entity).despawn_recursive();
        } else if toast.remaining < 1.0 {
            // Fade out over the last second.
            color.0 = color.0.with_alpha(toast.remaining * 0.94);
        }
    }
}

/// A welcome toast when the player moves in.
fn welcome_toast(mut toasts: EventWriter<ToastEvent>) {
    toasts.send(ToastEvent::success("Welcome home! Press J to find a job."));
}

/// Registers the toast system.
pub struct ToastPlugin;

impl Plugin for ToastPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            OnEnter(GameState::LiveMode),
            (spawn_tray, welcome_toast).chain(),
        )
        .add_systems(OnExit(GameState::LiveMode), despawn_tray)
        .add_systems(
            Update,
            (spawn_toasts, tick_toasts).run_if(in_state(GameState::LiveMode)),
        );
    }
}
