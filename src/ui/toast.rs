//! Toast notifications (Phase 10.7).
//!
//! Transient messages stack in the top-right and auto-dismiss after a few
//! seconds, colour-coded by severity (info/success/warning/error). Any system
//! emits one with `ToastEvent`; this module renders and expires them. Toasts are
//! standalone absolutely-positioned nodes (no pre-spawned tray to depend on).

use bevy::prelude::*;

use crate::core::events::{ToastEvent, ToastKind};
use crate::core::state::GameState;

/// Seconds a toast stays on screen before fading out.
const TOAST_LIFETIME: f32 = 5.0;

/// An individual toast with its remaining lifetime.
#[derive(Component)]
struct Toast {
    remaining: f32,
}

/// Accent colour for a toast kind.
fn kind_color(kind: ToastKind) -> Color {
    match kind {
        ToastKind::Info => Color::srgba(0.25, 0.50, 0.80, 0.95),
        ToastKind::Success => Color::srgba(0.22, 0.60, 0.34, 0.95),
        ToastKind::Warning => Color::srgba(0.80, 0.60, 0.18, 0.95),
        ToastKind::Error => Color::srgba(0.74, 0.28, 0.26, 0.95),
    }
}

/// Spawn a toast card per incoming `ToastEvent`, stacked top-right.
fn spawn_toasts(
    mut commands: Commands,
    mut events: EventReader<ToastEvent>,
    existing: Query<&Toast>,
) {
    let base = existing.iter().count();
    for (slot, event) in (base..).zip(events.read()) {
        info!("toast: {}", event.message);
        commands
            .spawn((
                NodeBundle {
                    style: Style {
                        position_type: PositionType::Absolute,
                        // Mirror the job board overlay exactly (it renders):
                        // left 50% + negative margin, top as a percentage.
                        left: Val::Percent(50.0),
                        top: Val::Percent(11.0 + slot as f32 * 6.5),
                        margin: UiRect::left(Val::Px(-160.0)),
                        width: Val::Px(320.0),
                        flex_direction: FlexDirection::Column,
                        align_items: AlignItems::Center,
                        padding: UiRect::all(Val::Px(10.0)),
                        border: UiRect::all(Val::Px(2.0)),
                        ..default()
                    },
                    background_color: kind_color(event.kind).into(),
                    border_color: Color::srgba(1.0, 1.0, 1.0, 0.8).into(),
                    border_radius: BorderRadius::all(Val::Px(6.0)),
                    ..default()
                },
                Toast {
                    remaining: TOAST_LIFETIME,
                },
                Name::new("Toast"),
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
    }
}

/// Tick toast lifetimes, fading out and despawning when expired.
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
            color.0 = color.0.with_alpha(toast.remaining);
        }
    }
}

/// Clear toasts when leaving live mode.
fn clear_toasts(mut commands: Commands, toasts: Query<Entity, With<Toast>>) {
    for entity in &toasts {
        commands.entity(entity).despawn_recursive();
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
        app.add_systems(OnEnter(GameState::LiveMode), welcome_toast)
            .add_systems(OnExit(GameState::LiveMode), clear_toasts)
            .add_systems(
                Update,
                (spawn_toasts, tick_toasts).run_if(in_state(GameState::LiveMode)),
            );
    }
}
