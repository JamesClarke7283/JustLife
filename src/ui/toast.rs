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
/// Top offset of the first toast (below the clock) and per-toast spacing.
const TOAST_TOP: f32 = 86.0;
const TOAST_SPACING: f32 = 44.0;

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
                        right: Val::Px(12.0),
                        top: Val::Px(TOAST_TOP + slot as f32 * TOAST_SPACING),
                        width: Val::Px(280.0),
                        padding: UiRect::axes(Val::Px(12.0), Val::Px(8.0)),
                        border: UiRect::all(Val::Px(2.0)),
                        align_items: AlignItems::Center,
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
