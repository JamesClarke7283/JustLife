//! Live-mode HUD overlay (Phase 10.2).
//!
//! Lays out the in-game HUD over the 3D view: a needs panel and sim portrait at
//! the bottom, the current interaction in the bottom-centre, a clock with speed
//! controls in the top-right, and a mini-map of the lot. (Household funds are
//! drawn top-left by the economy module; the needs bars get richer behaviour in
//! 10.3 and the speed controls keyboard support in 10.9.)

use bevy::prelude::*;

use crate::core::resources::{GameSpeed, GameTime};
use crate::core::state::GameState;
use crate::sim::interaction::InteractionQueue;
use crate::sim::moodlet::{ActiveMoodlets, Mood};
use crate::sim::needs::{NeedType, Needs};
use crate::sim::{SimManager, SimName};

/// The six needs in display order, each with a label and colour (Phase 10.3
/// refines these bars further).
fn needs_layout() -> [(NeedType, &'static str, Color); 6] {
    [
        (NeedType::Hunger, "Hunger", Color::srgb(0.40, 0.80, 0.40)),
        (NeedType::Energy, "Energy", Color::srgb(0.95, 0.85, 0.30)),
        (NeedType::Social, "Social", Color::srgb(0.65, 0.45, 0.85)),
        (NeedType::Fun, "Fun", Color::srgb(0.95, 0.50, 0.70)),
        (NeedType::Hygiene, "Hygiene", Color::srgb(0.35, 0.80, 0.80)),
        (NeedType::Bladder, "Bladder", Color::srgb(0.40, 0.55, 0.90)),
    ]
}

/// World half-extent (in units) the mini-map covers around the origin.
const MAP_WORLD_HALF: f32 = 13.0;
/// Mini-map size in pixels.
const MAP_PX: f32 = 132.0;

#[derive(Component)]
struct HudRoot;
#[derive(Component)]
struct TimeText;
#[derive(Component)]
struct NeedBar(NeedType);
#[derive(Component)]
struct PortraitSwatch;
#[derive(Component)]
struct PortraitName;
#[derive(Component)]
struct QueueText;
#[derive(Component)]
struct SpeedButton(GameSpeed);
#[derive(Component)]
struct Minimap;
#[derive(Component)]
struct MinimapDot;

/// Colour representing a mood (used for the portrait swatch).
fn mood_color(mood: Mood) -> Color {
    match mood {
        Mood::Happy => Color::srgb(0.45, 0.85, 0.45),
        Mood::Energized => Color::srgb(0.95, 0.78, 0.30),
        Mood::Flirty => Color::srgb(0.92, 0.45, 0.62),
        Mood::Focused => Color::srgb(0.40, 0.62, 0.90),
        Mood::Fine => Color::srgb(0.70, 0.74, 0.78),
        Mood::Tense => Color::srgb(0.85, 0.55, 0.30),
        Mood::Uncomfortable => Color::srgb(0.80, 0.60, 0.35),
        Mood::Sad => Color::srgb(0.45, 0.55, 0.80),
        Mood::Angry => Color::srgb(0.85, 0.30, 0.28),
        Mood::Embarrassed => Color::srgb(0.90, 0.50, 0.70),
    }
}

/// The household's focus sim (the first one) for the needs/portrait readouts.
fn focus_sim(manager: &SimManager) -> Option<Entity> {
    manager.sims.first().copied()
}

fn panel_bg() -> BackgroundColor {
    Color::srgba(0.08, 0.12, 0.16, 0.82).into()
}

/// Build the HUD when entering live mode.
fn spawn_hud(mut commands: Commands) {
    let root = commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    ..default()
                },
                ..default()
            },
            HudRoot,
            Name::new("HUD"),
        ))
        .id();

    commands.entity(root).with_children(|root| {
        spawn_clock(root);
        spawn_bottom(root);
        spawn_minimap(root);
    });
}

/// Top-right: clock plus speed buttons.
fn spawn_clock(root: &mut ChildBuilder) {
    root.spawn(NodeBundle {
        style: Style {
            position_type: PositionType::Absolute,
            right: Val::Px(12.0),
            top: Val::Px(12.0),
            flex_direction: FlexDirection::Column,
            align_items: AlignItems::FlexEnd,
            padding: UiRect::all(Val::Px(8.0)),
            row_gap: Val::Px(6.0),
            ..default()
        },
        background_color: panel_bg(),
        border_radius: BorderRadius::all(Val::Px(6.0)),
        ..default()
    })
    .with_children(|panel| {
        panel.spawn((
            TextBundle::from_section(
                "Day 1  00:00",
                TextStyle {
                    font_size: 20.0,
                    color: Color::WHITE,
                    ..default()
                },
            ),
            TimeText,
        ));
        panel
            .spawn(NodeBundle {
                style: Style {
                    column_gap: Val::Px(4.0),
                    ..default()
                },
                ..default()
            })
            .with_children(|row| {
                for (speed, label) in [
                    (GameSpeed::Pause, "II"),
                    (GameSpeed::Normal, "1x"),
                    (GameSpeed::Fast, "2x"),
                    (GameSpeed::Ultra, "4x"),
                ] {
                    row.spawn((
                        ButtonBundle {
                            style: Style {
                                width: Val::Px(36.0),
                                height: Val::Px(28.0),
                                align_items: AlignItems::Center,
                                justify_content: JustifyContent::Center,
                                ..default()
                            },
                            background_color: Color::srgba(0.2, 0.3, 0.4, 0.9).into(),
                            border_radius: BorderRadius::all(Val::Px(4.0)),
                            ..default()
                        },
                        SpeedButton(speed),
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
            });
    });
}

/// Bottom strip: portrait (left), needs bars, and current interaction (centre).
fn spawn_bottom(root: &mut ChildBuilder) {
    root.spawn(NodeBundle {
        style: Style {
            position_type: PositionType::Absolute,
            left: Val::Px(12.0),
            bottom: Val::Px(12.0),
            align_items: AlignItems::FlexEnd,
            column_gap: Val::Px(12.0),
            ..default()
        },
        ..default()
    })
    .with_children(|bottom| {
        // Portrait + mood swatch + name.
        bottom
            .spawn(NodeBundle {
                style: Style {
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    padding: UiRect::all(Val::Px(8.0)),
                    row_gap: Val::Px(4.0),
                    ..default()
                },
                background_color: panel_bg(),
                border_radius: BorderRadius::all(Val::Px(6.0)),
                ..default()
            })
            .with_children(|p| {
                p.spawn((
                    NodeBundle {
                        style: Style {
                            width: Val::Px(56.0),
                            height: Val::Px(56.0),
                            ..default()
                        },
                        background_color: Color::srgb(0.7, 0.7, 0.7).into(),
                        border_radius: BorderRadius::all(Val::Px(28.0)),
                        ..default()
                    },
                    PortraitSwatch,
                ));
                p.spawn((
                    TextBundle::from_section(
                        "-",
                        TextStyle {
                            font_size: 14.0,
                            color: Color::WHITE,
                            ..default()
                        },
                    ),
                    PortraitName,
                ));
            });

        // Needs bars.
        bottom
            .spawn(NodeBundle {
                style: Style {
                    flex_direction: FlexDirection::Column,
                    padding: UiRect::all(Val::Px(8.0)),
                    row_gap: Val::Px(3.0),
                    ..default()
                },
                background_color: panel_bg(),
                border_radius: BorderRadius::all(Val::Px(6.0)),
                ..default()
            })
            .with_children(|panel| {
                for (need, label, color) in needs_layout() {
                    panel
                        .spawn(NodeBundle {
                            style: Style {
                                align_items: AlignItems::Center,
                                column_gap: Val::Px(6.0),
                                ..default()
                            },
                            ..default()
                        })
                        .with_children(|row| {
                            row.spawn(
                                TextBundle::from_section(
                                    label,
                                    TextStyle {
                                        font_size: 12.0,
                                        color: Color::srgb(0.85, 0.9, 0.95),
                                        ..default()
                                    },
                                )
                                .with_style(Style {
                                    width: Val::Px(54.0),
                                    ..default()
                                }),
                            );
                            // Track + fill.
                            row.spawn(NodeBundle {
                                style: Style {
                                    width: Val::Px(140.0),
                                    height: Val::Px(12.0),
                                    ..default()
                                },
                                background_color: Color::srgba(0.0, 0.0, 0.0, 0.5).into(),
                                border_radius: BorderRadius::all(Val::Px(6.0)),
                                ..default()
                            })
                            .with_children(|track| {
                                track.spawn((
                                    NodeBundle {
                                        style: Style {
                                            width: Val::Percent(100.0),
                                            height: Val::Percent(100.0),
                                            ..default()
                                        },
                                        background_color: color.into(),
                                        border_radius: BorderRadius::all(Val::Px(6.0)),
                                        ..default()
                                    },
                                    NeedBar(need),
                                ));
                            });
                        });
                }
            });

        // Current interaction.
        bottom
            .spawn(NodeBundle {
                style: Style {
                    padding: UiRect::all(Val::Px(8.0)),
                    ..default()
                },
                background_color: panel_bg(),
                border_radius: BorderRadius::all(Val::Px(6.0)),
                ..default()
            })
            .with_children(|p| {
                p.spawn((
                    TextBundle::from_section(
                        "Idle",
                        TextStyle {
                            font_size: 15.0,
                            color: Color::srgb(1.0, 0.95, 0.7),
                            ..default()
                        },
                    ),
                    QueueText,
                ));
            });
    });
}

/// Bottom-right: mini-map of the lot with sim dots.
fn spawn_minimap(root: &mut ChildBuilder) {
    root.spawn((
        NodeBundle {
            style: Style {
                position_type: PositionType::Absolute,
                right: Val::Px(12.0),
                bottom: Val::Px(12.0),
                width: Val::Px(MAP_PX),
                height: Val::Px(MAP_PX),
                ..default()
            },
            background_color: Color::srgba(0.18, 0.32, 0.20, 0.85).into(),
            border_radius: BorderRadius::all(Val::Px(4.0)),
            ..default()
        },
        Minimap,
        Name::new("Mini-map"),
    ))
    .with_children(|map| {
        // A rough house footprint marker in the centre.
        map.spawn(NodeBundle {
            style: Style {
                position_type: PositionType::Absolute,
                left: Val::Px(MAP_PX * 0.32),
                top: Val::Px(MAP_PX * 0.32),
                width: Val::Px(MAP_PX * 0.42),
                height: Val::Px(MAP_PX * 0.42),
                ..default()
            },
            background_color: Color::srgba(0.55, 0.4, 0.32, 0.7).into(),
            ..default()
        });
    });
}

/// Despawn the HUD when leaving live mode.
fn despawn_hud(mut commands: Commands, huds: Query<Entity, With<HudRoot>>) {
    for entity in &huds {
        commands.entity(entity).despawn_recursive();
    }
}

/// Update the clock readout.
fn update_time(time: Res<GameTime>, mut labels: Query<&mut Text, With<TimeText>>) {
    for mut text in &mut labels {
        if let Some(section) = text.sections.first_mut() {
            section.value = format!("Day {}  {:02}:{:02}", time.day, time.hour, time.minute);
        }
    }
}

/// Highlight the active speed button and apply clicks.
fn speed_controls(
    mut speed: ResMut<GameSpeed>,
    mut buttons: Query<(&Interaction, &SpeedButton, &mut BackgroundColor)>,
) {
    for (interaction, button, mut color) in &mut buttons {
        if *interaction == Interaction::Pressed {
            *speed = button.0;
        }
        let active = *speed == button.0;
        *color = if active {
            Color::srgb(0.95, 0.78, 0.30).into()
        } else if *interaction == Interaction::Hovered {
            Color::srgba(0.3, 0.45, 0.6, 0.95).into()
        } else {
            Color::srgba(0.2, 0.3, 0.4, 0.9).into()
        };
    }
}

/// Update the needs bars from the focus sim.
fn update_needs(
    manager: Res<SimManager>,
    sims: Query<&Needs>,
    mut bars: Query<(&NeedBar, &mut Style)>,
) {
    let Some(needs) = focus_sim(&manager).and_then(|e| sims.get(e).ok()) else {
        return;
    };
    for (bar, mut style) in &mut bars {
        style.width = Val::Percent(needs.get(bar.0).clamp(0.0, 100.0));
    }
}

/// Update the portrait swatch colour, name, and current interaction text.
fn update_portrait(
    manager: Res<SimManager>,
    sims: Query<(&SimName, &ActiveMoodlets, Option<&InteractionQueue>)>,
    mut swatches: Query<&mut BackgroundColor, With<PortraitSwatch>>,
    mut names: Query<&mut Text, (With<PortraitName>, Without<QueueText>)>,
    mut queue: Query<&mut Text, (With<QueueText>, Without<PortraitName>)>,
) {
    let Some((name, moodlets, iq)) = focus_sim(&manager).and_then(|e| sims.get(e).ok()) else {
        return;
    };
    for mut color in &mut swatches {
        *color = mood_color(moodlets.dominant_mood()).into();
    }
    for mut text in &mut names {
        if let Some(section) = text.sections.first_mut() {
            section.value = name.first.clone();
        }
    }
    for mut text in &mut queue {
        if let Some(section) = text.sections.first_mut() {
            section.value = iq
                .and_then(|q| q.current())
                .map(|c| c.action.clone())
                .unwrap_or_else(|| "Idle".to_string());
        }
    }
}

/// Redraw sim dots on the mini-map each frame (immediate-mode).
fn update_minimap(
    mut commands: Commands,
    maps: Query<Entity, With<Minimap>>,
    dots: Query<Entity, With<MinimapDot>>,
    sims: Query<&Transform, With<SimName>>,
) {
    for dot in &dots {
        commands.entity(dot).despawn_recursive();
    }
    let Ok(map) = maps.get_single() else {
        return;
    };
    for transform in &sims {
        let p = transform.translation;
        // Hidden (off-lot at work) sims sit far away; skip them.
        if p.y < -1.0 {
            continue;
        }
        let mx = ((p.x + MAP_WORLD_HALF) / (2.0 * MAP_WORLD_HALF)).clamp(0.0, 1.0) * MAP_PX;
        let my = ((p.z + MAP_WORLD_HALF) / (2.0 * MAP_WORLD_HALF)).clamp(0.0, 1.0) * MAP_PX;
        commands.entity(map).with_children(|m| {
            m.spawn((
                NodeBundle {
                    style: Style {
                        position_type: PositionType::Absolute,
                        left: Val::Px(mx - 3.0),
                        top: Val::Px(my - 3.0),
                        width: Val::Px(6.0),
                        height: Val::Px(6.0),
                        ..default()
                    },
                    background_color: Color::srgb(1.0, 0.95, 0.3).into(),
                    border_radius: BorderRadius::all(Val::Px(3.0)),
                    ..default()
                },
                MinimapDot,
            ));
        });
    }
}

/// Registers the live-mode HUD.
pub struct HudPlugin;

impl Plugin for HudPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(GameState::LiveMode), spawn_hud)
            .add_systems(OnExit(GameState::LiveMode), despawn_hud)
            .add_systems(
                Update,
                (
                    update_time,
                    speed_controls,
                    update_needs,
                    update_portrait,
                    update_minimap,
                )
                    .run_if(in_state(GameState::LiveMode)),
            );
    }
}
