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

/// Need value below which the bar flashes red.
const NEED_CRITICAL: f32 = 25.0;

#[derive(Component)]
struct HudRoot;
#[derive(Component)]
struct TimeText;
/// The animated fill of a needs bar.
#[derive(Component)]
struct NeedBar {
    need: NeedType,
    base: Color,
    /// Smoothly-animated displayed percentage (lerps toward the real value).
    shown: f32,
}
/// The interactive track wrapping a needs bar (hover/click target).
#[derive(Component)]
struct NeedButton(NeedType);
/// The tooltip container shown when hovering a needs bar.
#[derive(Component)]
struct NeedTooltip;
/// The tooltip's text node.
#[derive(Component)]
struct NeedTooltipText;
/// A marker floating over an object that satisfies the highlighted need.
#[derive(Component)]
struct NeedHighlightMarker;
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

/// The need currently hovered in the HUD (drives the tooltip).
#[derive(Resource, Default)]
struct HoveredNeed(Option<NeedType>);

/// The need whose satisfying objects are highlighted on the lot.
#[derive(Resource, Default)]
struct HighlightNeed(Option<NeedType>);

/// Exponential smoothing of a bar's shown value toward its target.
fn lerp_toward(current: f32, target: f32, dt: f32) -> f32 {
    let t = (dt * 8.0).clamp(0.0, 1.0);
    current + (target - current) * t
}

/// Linear blend between two colours in sRGB space.
fn blend(a: Color, b: Color, t: f32) -> Color {
    let a = a.to_srgba();
    let b = b.to_srgba();
    Color::srgba(
        a.red + (b.red - a.red) * t,
        a.green + (b.green - a.green) * t,
        a.blue + (b.blue - a.blue) * t,
        a.alpha,
    )
}

/// Bar colour: pulses toward red while the value is critical, else the base.
fn need_bar_color(base: Color, value: f32, seconds: f32) -> Color {
    if value >= NEED_CRITICAL {
        return base;
    }
    let pulse = (seconds * 6.0).sin() * 0.5 + 0.5; // 0..1
    blend(base, Color::srgb(1.0, 0.18, 0.18), 0.45 + 0.45 * pulse)
}

/// Objects/sources that satisfy a need (shown in the hover tooltip).
fn need_sources(need: NeedType) -> &'static str {
    match need {
        NeedType::Hunger => "Fridge, Stove, Dining Table",
        NeedType::Energy => "Bed, Sofa",
        NeedType::Social => "Phone, other Sims",
        NeedType::Fun => "TV, Computer, Bookshelf",
        NeedType::Hygiene => "Shower, Bath, Sink",
        NeedType::Bladder => "Toilet",
    }
}

/// Display label for a need.
fn need_label(need: NeedType) -> &'static str {
    needs_layout()
        .into_iter()
        .find(|(n, _, _)| *n == need)
        .map(|(_, label, _)| label)
        .unwrap_or("Need")
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
        spawn_tooltip(root);
    });
}

/// A hover tooltip for the needs bars (hidden until a bar is hovered).
fn spawn_tooltip(root: &mut ChildBuilder) {
    root.spawn((
        NodeBundle {
            style: Style {
                position_type: PositionType::Absolute,
                left: Val::Px(90.0),
                bottom: Val::Px(116.0),
                padding: UiRect::all(Val::Px(6.0)),
                display: Display::None,
                ..default()
            },
            background_color: Color::srgba(0.0, 0.0, 0.0, 0.88).into(),
            border_radius: BorderRadius::all(Val::Px(4.0)),
            ..default()
        },
        NeedTooltip,
        Name::new("Need Tooltip"),
    ))
    .with_children(|t| {
        t.spawn((
            TextBundle::from_section(
                String::new(),
                TextStyle {
                    font_size: 13.0,
                    color: Color::WHITE,
                    ..default()
                },
            ),
            NeedTooltipText,
        ));
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
                            // Interactive track (hover for tooltip, click to
                            // highlight matching objects) wrapping the fill.
                            row.spawn((
                                ButtonBundle {
                                    style: Style {
                                        width: Val::Px(140.0),
                                        height: Val::Px(12.0),
                                        ..default()
                                    },
                                    background_color: Color::srgba(0.0, 0.0, 0.0, 0.5).into(),
                                    border_radius: BorderRadius::all(Val::Px(6.0)),
                                    ..default()
                                },
                                NeedButton(need),
                            ))
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
                                    NeedBar {
                                        need,
                                        base: color,
                                        shown: 100.0,
                                    },
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

/// Update the needs bars from the focus sim: smoothly animate the fill and
/// flash the bar red while the need is critical.
fn update_needs(
    time: Res<Time>,
    manager: Res<SimManager>,
    sims: Query<&Needs>,
    mut bars: Query<(&mut NeedBar, &mut Style, &mut BackgroundColor)>,
) {
    let Some(needs) = focus_sim(&manager).and_then(|e| sims.get(e).ok()) else {
        return;
    };
    let dt = time.delta_seconds();
    let seconds = time.elapsed_seconds();
    for (mut bar, mut style, mut color) in &mut bars {
        let target = needs.get(bar.need).clamp(0.0, 100.0);
        bar.shown = lerp_toward(bar.shown, target, dt);
        style.width = Val::Percent(bar.shown);
        *color = need_bar_color(bar.base, target, seconds).into();
    }
}

/// Track hover (tooltip) and clicks (toggle object highlight) on needs bars.
fn need_bar_interaction(
    buttons: Query<(&Interaction, &NeedButton), Changed<Interaction>>,
    hovered_buttons: Query<(&Interaction, &NeedButton)>,
    mut hovered: ResMut<HoveredNeed>,
    mut highlight: ResMut<HighlightNeed>,
) {
    for (interaction, button) in &buttons {
        if *interaction == Interaction::Pressed {
            // Toggle the highlight for this need.
            highlight.0 = if highlight.0 == Some(button.0) {
                None
            } else {
                Some(button.0)
            };
        }
    }
    // Recompute the hovered need from the current frame's states.
    hovered.0 = hovered_buttons
        .iter()
        .find(|(i, _)| **i == Interaction::Hovered || **i == Interaction::Pressed)
        .map(|(_, b)| b.0);
}

/// Show/hide and fill the needs tooltip based on the hovered need.
fn update_tooltip(
    hovered: Res<HoveredNeed>,
    manager: Res<SimManager>,
    sims: Query<&Needs>,
    mut tooltips: Query<&mut Style, With<NeedTooltip>>,
    mut texts: Query<&mut Text, With<NeedTooltipText>>,
) {
    let needs = focus_sim(&manager).and_then(|e| sims.get(e).ok());
    for mut style in &mut tooltips {
        style.display = if hovered.0.is_some() {
            Display::Flex
        } else {
            Display::None
        };
    }
    if let (Some(need), Some(needs)) = (hovered.0, needs) {
        for mut text in &mut texts {
            if let Some(section) = text.sections.first_mut() {
                section.value = format!(
                    "{}: {:.0}/100\nfrom {}",
                    need_label(need),
                    needs.get(need),
                    need_sources(need)
                );
            }
        }
    }
}

/// Float a marker over every object that satisfies the highlighted need.
#[allow(clippy::too_many_arguments)]
fn highlight_need_objects(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut cache: Local<Option<(Handle<Mesh>, Handle<StandardMaterial>)>>,
    highlight: Res<HighlightNeed>,
    catalog: Res<crate::world::catalog::CatalogDatabase>,
    objects: Query<(&crate::world::PlacedObject, &Transform)>,
    markers: Query<Entity, With<NeedHighlightMarker>>,
) {
    for marker in &markers {
        commands.entity(marker).despawn_recursive();
    }
    let Some(need) = highlight.0 else {
        return;
    };
    let (mesh, material) = cache.get_or_insert_with(|| {
        (
            meshes.add(Sphere::new(0.35)),
            materials.add(StandardMaterial {
                base_color: Color::srgb(1.0, 0.9, 0.25),
                emissive: LinearRgba::new(0.9, 0.8, 0.1, 1.0),
                unlit: true,
                ..default()
            }),
        )
    });
    for (obj, transform) in &objects {
        let satisfies = catalog
            .get(&obj.catalog_id)
            .is_some_and(|item| item.actions.iter().any(|a| a.need == need));
        if satisfies {
            commands.spawn((
                PbrBundle {
                    mesh: mesh.clone(),
                    material: material.clone(),
                    transform: Transform::from_translation(
                        transform.translation + Vec3::new(0.0, 2.0, 0.0),
                    ),
                    ..default()
                },
                NeedHighlightMarker,
                Name::new("Need Highlight"),
            ));
        }
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
        app.init_resource::<HoveredNeed>()
            .init_resource::<HighlightNeed>()
            .add_systems(OnEnter(GameState::LiveMode), spawn_hud)
            .add_systems(OnExit(GameState::LiveMode), despawn_hud)
            .add_systems(
                Update,
                (
                    update_time,
                    speed_controls,
                    update_needs,
                    need_bar_interaction,
                    update_tooltip,
                    highlight_need_objects,
                    update_portrait,
                    update_minimap,
                )
                    .run_if(in_state(GameState::LiveMode)),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lerp_moves_toward_target_without_overshoot() {
        // Half-second step closes most of the gap but never overshoots.
        let next = lerp_toward(0.0, 100.0, 0.016);
        assert!(next > 0.0 && next < 100.0);
        // A huge dt clamps to the target exactly.
        assert_eq!(lerp_toward(20.0, 80.0, 10.0), 80.0);
    }

    #[test]
    fn bar_flashes_only_when_critical() {
        let base = Color::srgb(0.4, 0.8, 0.4);
        // Healthy need keeps its base colour at any time.
        assert_eq!(need_bar_color(base, 60.0, 1.0), base);
        // Critical need shifts toward red.
        let crit = need_bar_color(base, 10.0, 1.0).to_srgba();
        assert!(crit.red > base.to_srgba().red);
    }

    #[test]
    fn every_need_has_a_label_and_sources() {
        for (need, _, _) in needs_layout() {
            assert_ne!(need_label(need), "Need");
            assert!(!need_sources(need).is_empty());
        }
    }
}
