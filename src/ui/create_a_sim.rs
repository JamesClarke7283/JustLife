//! Create-A-Sim: a graphical, point-and-click 3-step wizard.
//!
//! Step 1 Identity (name + gender) -> Step 2 Looks (skin/hair/colour/shirt
//! carousels) -> Step 3 Personality (pick up to 3 traits) -> lot selection.
//! Everything is clickable (◄ ► carousels, gender/trait/Next/Back buttons);
//! keyboard also works (Enter = Next/Done, Esc = Back, type the name, 1-9
//! toggle traits) so the flow is reachable in the headless harness.

use bevy::input::ButtonState;
use bevy::input::keyboard::{Key, KeyboardInput};
use bevy::prelude::*;

use crate::core::state::GameState;
use crate::sim::appearance::{hair_colors, hair_styles, shirt_colors, skin_tones};
use crate::sim::{SimConfig, SimGender, Trait};

const TRAIT_CHOICES: [(Trait, &str); 9] = [
    (Trait::Cheerful, "Cheerful"),
    (Trait::Outgoing, "Outgoing"),
    (Trait::Creative, "Creative"),
    (Trait::Genius, "Genius"),
    (Trait::Active, "Active"),
    (Trait::Neat, "Neat"),
    (Trait::Foodie, "Foodie"),
    (Trait::Romantic, "Romantic"),
    (Trait::Ambitious, "Ambitious"),
];
const MAX_TRAITS: usize = 3;
const NAME_MAX: usize = 16;
const STEPS: usize = 3;

/// Which appearance attribute a carousel cycles.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Field {
    Skin,
    HairStyle,
    HairColor,
    Shirt,
}

/// An action a CAS button performs when clicked.
#[derive(Component, Clone, Copy)]
enum CasAction {
    Back,
    Next,
    Gender(SimGender),
    Cycle(Field, i32),
    ToggleTrait(usize),
    Randomize,
}

/// The current wizard step (0..STEPS).
#[derive(Resource, Default)]
struct CasStep(usize);

#[derive(Component)]
struct CasRoot;

const PANEL: Color = Color::srgba(0.07, 0.10, 0.16, 0.98);
const BTN: Color = Color::srgba(0.20, 0.30, 0.42, 0.98);
const BTN_HOVER: Color = Color::srgba(0.30, 0.45, 0.62, 1.0);
const ACCENT: Color = Color::srgb(0.95, 0.78, 0.30);

fn toggle_trait(config: &mut SimConfig, t: Trait) {
    if let Some(pos) = config.traits.iter().position(|x| *x == t) {
        config.traits.remove(pos);
    } else if config.traits.len() < MAX_TRAITS {
        config.traits.push(t);
    }
}

fn wrap(index: usize, dir: i32, len: usize) -> usize {
    (index as i32 + dir).rem_euclid(len as i32) as usize
}

fn cycle_field(config: &mut SimConfig, field: Field, dir: i32) {
    match field {
        Field::Skin => config.skin = wrap(config.skin, dir, skin_tones().len()),
        Field::HairStyle => config.hair_style = wrap(config.hair_style, dir, hair_styles().len()),
        Field::HairColor => config.hair_color = wrap(config.hair_color, dir, hair_colors().len()),
        Field::Shirt => config.shirt = wrap(config.shirt, dir, shirt_colors().len()),
    }
}

fn randomize(config: &mut SimConfig, seed: usize) {
    const NAMES: [&str; 8] = [
        "Alex", "Sam", "Robin", "Jordan", "Casey", "Riley", "Quinn", "Avery",
    ];
    config.first = NAMES[seed % NAMES.len()].to_string();
    config.gender = [SimGender::Female, SimGender::Male, SimGender::Custom][seed % 3];
    config.skin = seed % skin_tones().len();
    config.hair_color = (seed + 1) % hair_colors().len();
    config.hair_style = (seed + 2) % hair_styles().len();
    config.shirt = (seed + 3) % shirt_colors().len();
    config.traits.clear();
    for i in 0..MAX_TRAITS {
        let (t, _) = TRAIT_CHOICES[(seed + i * 3) % TRAIT_CHOICES.len()];
        if !config.traits.contains(&t) {
            config.traits.push(t);
        }
    }
}

/// Apply a wizard action; returns true if it requested leaving CAS.
fn apply_action(
    action: CasAction,
    config: &mut SimConfig,
    step: &mut CasStep,
    seed: &mut usize,
) -> bool {
    match action {
        CasAction::Back => {
            if step.0 > 0 {
                step.0 -= 1;
            }
        }
        CasAction::Next => {
            if step.0 + 1 < STEPS {
                step.0 += 1;
            } else {
                return true; // Done -> leave CAS
            }
        }
        CasAction::Gender(g) => config.gender = g,
        CasAction::Cycle(field, dir) => cycle_field(config, field, dir),
        CasAction::ToggleTrait(i) => toggle_trait(config, TRAIT_CHOICES[i].0),
        CasAction::Randomize => {
            *seed = seed.wrapping_add(1);
            randomize(config, *seed);
        }
    }
    false
}

#[allow(clippy::too_many_arguments)]
fn cas_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut key_events: EventReader<KeyboardInput>,
    buttons: Query<(&Interaction, &CasAction), Changed<Interaction>>,
    mut config: ResMut<SimConfig>,
    mut step: ResMut<CasStep>,
    mut seed: Local<usize>,
    mut next_state: ResMut<NextState<GameState>>,
) {
    let mut done = false;

    // Point-and-click.
    for (interaction, action) in &buttons {
        if *interaction == Interaction::Pressed {
            done |= apply_action(*action, &mut config, &mut step, &mut seed);
        }
    }

    // Keyboard fallbacks.
    if keyboard.just_pressed(KeyCode::Enter) {
        done |= apply_action(CasAction::Next, &mut config, &mut step, &mut seed);
    }
    if keyboard.just_pressed(KeyCode::Escape) {
        apply_action(CasAction::Back, &mut config, &mut step, &mut seed);
    }
    if step.0 == 2 {
        const DIGITS: [KeyCode; 9] = [
            KeyCode::Digit1,
            KeyCode::Digit2,
            KeyCode::Digit3,
            KeyCode::Digit4,
            KeyCode::Digit5,
            KeyCode::Digit6,
            KeyCode::Digit7,
            KeyCode::Digit8,
            KeyCode::Digit9,
        ];
        for (i, key) in DIGITS.iter().enumerate() {
            if keyboard.just_pressed(*key) {
                toggle_trait(&mut config, TRAIT_CHOICES[i].0);
            }
        }
    }
    // Name typing on step 1.
    if step.0 == 0 {
        for ev in key_events.read() {
            if ev.state != ButtonState::Pressed {
                continue;
            }
            match &ev.logical_key {
                Key::Character(s) => {
                    for ch in s.chars() {
                        if (ch.is_alphabetic() || ch == ' ') && config.first.len() < NAME_MAX {
                            config.first.push(ch);
                        }
                    }
                }
                Key::Space if config.first.len() < NAME_MAX => config.first.push(' '),
                Key::Backspace => {
                    config.first.pop();
                }
                _ => {}
            }
        }
    }

    if done {
        next_state.set(GameState::LotSelect);
    }
}

/// Hover feedback for CAS buttons.
fn button_hover(mut buttons: Query<(&Interaction, &mut BackgroundColor), With<CasAction>>) {
    for (interaction, mut color) in &mut buttons {
        // Keep accent (selected) buttons; only react on idle/hover base buttons.
        let base = color.0;
        if base == BTN || base == BTN_HOVER {
            *color = if *interaction == Interaction::Hovered {
                BTN_HOVER.into()
            } else {
                BTN.into()
            };
        }
    }
}

/// Rebuild the wizard when the step or config changes.
fn render_cas(
    mut commands: Commands,
    config: Res<SimConfig>,
    step: Res<CasStep>,
    roots: Query<Entity, With<CasRoot>>,
) {
    if !config.is_changed() && !step.is_changed() && !roots.is_empty() {
        return;
    }
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }

    let root = commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    align_items: AlignItems::Center,
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                background_color: Color::srgba(0.02, 0.04, 0.07, 0.7).into(),
                ..default()
            },
            CasRoot,
            Name::new("Create-A-Sim"),
        ))
        .id();

    commands.entity(root).with_children(|root| {
        // The big card.
        root.spawn(NodeBundle {
            style: Style {
                width: Val::Px(720.0),
                flex_direction: FlexDirection::Column,
                align_items: AlignItems::Center,
                padding: UiRect::all(Val::Px(28.0)),
                row_gap: Val::Px(16.0),
                ..default()
            },
            background_color: PANEL.into(),
            border_radius: BorderRadius::all(Val::Px(14.0)),
            ..default()
        })
        .with_children(|card| {
            label(card, "Create A Sim", 40.0, Color::WHITE);
            label(
                card,
                &format!("Step {} of {}", step.0 + 1, STEPS),
                18.0,
                ACCENT,
            );
            match step.0 {
                0 => step_identity(card, &config),
                1 => step_looks(card, &config),
                _ => step_personality(card, &config),
            }
            nav_row(card, step.0);
        });
    });
}

/// Step 1: name field + gender choice.
fn step_identity(card: &mut ChildBuilder, config: &SimConfig) {
    label(card, "Who are you?", 24.0, Color::srgb(0.85, 0.9, 0.96));
    // Name "field".
    card.spawn(NodeBundle {
        style: Style {
            width: Val::Px(360.0),
            height: Val::Px(48.0),
            align_items: AlignItems::Center,
            justify_content: JustifyContent::Center,
            ..default()
        },
        background_color: Color::srgba(0.0, 0.0, 0.0, 0.5).into(),
        border_radius: BorderRadius::all(Val::Px(8.0)),
        ..default()
    })
    .with_children(|f| {
        label(f, &format!("{}|", config.first), 26.0, Color::WHITE);
    });
    label(
        card,
        "(type to edit your name)",
        13.0,
        Color::srgba(0.8, 0.85, 0.95, 0.7),
    );

    // Gender buttons.
    card.spawn(NodeBundle {
        style: Style {
            column_gap: Val::Px(12.0),
            margin: UiRect::top(Val::Px(6.0)),
            ..default()
        },
        ..default()
    })
    .with_children(|row| {
        for (g, name) in [
            (SimGender::Male, "Male"),
            (SimGender::Female, "Female"),
            (SimGender::Custom, "Custom"),
        ] {
            let selected = config.gender == g;
            button(row, CasAction::Gender(g), name, 120.0, selected);
        }
    });
}

/// Step 2: appearance carousels.
fn step_looks(card: &mut ChildBuilder, config: &SimConfig) {
    label(card, "Pick your look", 24.0, Color::srgb(0.85, 0.9, 0.96));
    carousel(card, Field::Skin, "Skin", skin_tones()[config.skin % 5].0);
    carousel(
        card,
        Field::HairStyle,
        "Hair",
        hair_styles()[config.hair_style % 4].0,
    );
    carousel(
        card,
        Field::HairColor,
        "Hair Colour",
        hair_colors()[config.hair_color % 5].0,
    );
    carousel(
        card,
        Field::Shirt,
        "Shirt",
        shirt_colors()[config.shirt % 5].0,
    );
    card.spawn(NodeBundle {
        style: Style {
            margin: UiRect::top(Val::Px(6.0)),
            ..default()
        },
        ..default()
    })
    .with_children(|row| {
        button(row, CasAction::Randomize, "Randomize", 160.0, false);
    });
}

/// Step 3: trait picker.
fn step_personality(card: &mut ChildBuilder, config: &SimConfig) {
    label(
        card,
        &format!(
            "Pick up to {MAX_TRAITS} traits ({}/{})",
            config.traits.len(),
            MAX_TRAITS
        ),
        24.0,
        Color::srgb(0.85, 0.9, 0.96),
    );
    card.spawn(NodeBundle {
        style: Style {
            width: Val::Px(560.0),
            flex_wrap: FlexWrap::Wrap,
            column_gap: Val::Px(10.0),
            row_gap: Val::Px(10.0),
            justify_content: JustifyContent::Center,
            ..default()
        },
        ..default()
    })
    .with_children(|grid| {
        for (i, (t, name)) in TRAIT_CHOICES.iter().enumerate() {
            let on = config.traits.contains(t);
            button(grid, CasAction::ToggleTrait(i), name, 168.0, on);
        }
    });
}

/// Back / Next (or Start) navigation row.
fn nav_row(card: &mut ChildBuilder, step: usize) {
    card.spawn(NodeBundle {
        style: Style {
            column_gap: Val::Px(16.0),
            margin: UiRect::top(Val::Px(10.0)),
            ..default()
        },
        ..default()
    })
    .with_children(|row| {
        if step > 0 {
            button(row, CasAction::Back, "< Back", 150.0, false);
        }
        let last = step + 1 == STEPS;
        button(
            row,
            CasAction::Next,
            if last { "Start Game >" } else { "Next >" },
            190.0,
            last,
        );
    });
}

/// A labelled carousel row: [<] label: value [>].
fn carousel(card: &mut ChildBuilder, field: Field, name: &str, value: &str) {
    card.spawn(NodeBundle {
        style: Style {
            width: Val::Px(440.0),
            align_items: AlignItems::Center,
            justify_content: JustifyContent::SpaceBetween,
            ..default()
        },
        ..default()
    })
    .with_children(|row| {
        button(row, CasAction::Cycle(field, -1), "<", 56.0, false);
        row.spawn(NodeBundle {
            style: Style {
                width: Val::Px(300.0),
                justify_content: JustifyContent::Center,
                ..default()
            },
            ..default()
        })
        .with_children(|mid| {
            label(mid, &format!("{name}: {value}"), 22.0, Color::WHITE);
        });
        button(row, CasAction::Cycle(field, 1), ">", 56.0, false);
    });
}

/// Spawn a clickable button; `selected` paints it with the accent colour.
fn button(parent: &mut ChildBuilder, action: CasAction, text: &str, width: f32, selected: bool) {
    let bg = if selected { ACCENT } else { BTN };
    parent
        .spawn((
            ButtonBundle {
                style: Style {
                    width: Val::Px(width),
                    height: Val::Px(44.0),
                    align_items: AlignItems::Center,
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                background_color: bg.into(),
                border_radius: BorderRadius::all(Val::Px(8.0)),
                ..default()
            },
            action,
        ))
        .with_children(|b| {
            b.spawn(TextBundle::from_section(
                text,
                TextStyle {
                    font_size: 20.0,
                    color: if selected { Color::BLACK } else { Color::WHITE },
                    ..default()
                },
            ));
        });
}

fn label(parent: &mut ChildBuilder, value: &str, size: f32, color: Color) {
    parent.spawn(TextBundle::from_section(
        value,
        TextStyle {
            font_size: size,
            color,
            ..default()
        },
    ));
}

fn exit_cas(
    mut commands: Commands,
    mut step: ResMut<CasStep>,
    roots: Query<Entity, With<CasRoot>>,
) {
    step.0 = 0;
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
}

/// Registers the Create-A-Sim wizard.
pub struct CreateASimPlugin;

impl Plugin for CreateASimPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CasStep>()
            .add_systems(OnExit(GameState::CreateASim), exit_cas)
            .add_systems(
                Update,
                (cas_input, button_hover, render_cas).run_if(in_state(GameState::CreateASim)),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg() -> SimConfig {
        SimConfig::default()
    }

    #[test]
    fn next_advances_then_finishes() {
        let (mut c, mut s, mut seed) = (cfg(), CasStep(0), 0usize);
        assert!(!apply_action(CasAction::Next, &mut c, &mut s, &mut seed));
        assert_eq!(s.0, 1);
        assert!(!apply_action(CasAction::Next, &mut c, &mut s, &mut seed));
        assert_eq!(s.0, 2);
        // Final Next finishes (leaves CAS).
        assert!(apply_action(CasAction::Next, &mut c, &mut s, &mut seed));
    }

    #[test]
    fn back_stops_at_first_step() {
        let (mut c, mut s, mut seed) = (cfg(), CasStep(0), 0usize);
        assert!(!apply_action(CasAction::Back, &mut c, &mut s, &mut seed));
        assert_eq!(s.0, 0);
    }

    #[test]
    fn cycle_and_trait_actions_apply() {
        let (mut c, mut s, mut seed) = (cfg(), CasStep(1), 0usize);
        c.skin = 0;
        apply_action(CasAction::Cycle(Field::Skin, -1), &mut c, &mut s, &mut seed);
        assert_eq!(c.skin, skin_tones().len() - 1);
        c.traits.clear();
        apply_action(CasAction::ToggleTrait(0), &mut c, &mut s, &mut seed);
        assert_eq!(c.traits, vec![TRAIT_CHOICES[0].0]);
    }
}
