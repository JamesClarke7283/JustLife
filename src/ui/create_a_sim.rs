//! Create-A-Sim screen (start of the New Game flow).
//!
//! A carousel-style chooser: Up/Down move between rows, Left/Right cycle the
//! highlighted row's value (gender, skin, hair, shirt), and on the Name row you
//! type the name directly. 1-9 toggle traits, R randomises (off the Name row),
//! Enter confirms. Keyboard-driven so it works in the headless harness.

use bevy::input::ButtonState;
use bevy::input::keyboard::{Key, KeyboardInput};
use bevy::prelude::*;

use crate::core::state::GameState;
use crate::sim::appearance::{hair_colors, hair_styles, shirt_colors, skin_tones};
use crate::sim::{SimConfig, SimGender, Trait};

/// The traits offered for selection (numbered 1-9 in the UI; up to three).
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

/// Maximum traits a sim may have.
const MAX_TRAITS: usize = 3;
/// Maximum name length.
const NAME_MAX: usize = 16;

/// The editable rows of the CAS screen.
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
enum CasRow {
    #[default]
    Name,
    Gender,
    Skin,
    HairStyle,
    HairColor,
    Shirt,
    Traits,
}

const ROWS: [CasRow; 7] = [
    CasRow::Name,
    CasRow::Gender,
    CasRow::Skin,
    CasRow::HairStyle,
    CasRow::HairColor,
    CasRow::Shirt,
    CasRow::Traits,
];

/// The highlighted row.
#[derive(Resource, Default)]
struct CasCursor {
    row: usize,
}

#[derive(Component)]
struct CasRoot;

/// Toggle a trait in the config (respecting the 3-trait cap).
fn toggle_trait(config: &mut SimConfig, t: Trait) {
    if let Some(pos) = config.traits.iter().position(|x| *x == t) {
        config.traits.remove(pos);
    } else if config.traits.len() < MAX_TRAITS {
        config.traits.push(t);
    }
}

/// Cycle to the next/previous gender.
fn cycle_gender(g: SimGender, dir: i32) -> SimGender {
    let order = [SimGender::Male, SimGender::Female, SimGender::Custom];
    let i = order.iter().position(|x| *x == g).unwrap_or(0) as i32;
    order[(i + dir).rem_euclid(order.len() as i32) as usize]
}

/// Wrap a preset index by `dir` within `len`.
fn wrap(index: usize, dir: i32, len: usize) -> usize {
    (index as i32 + dir).rem_euclid(len as i32) as usize
}

/// Cycle the highlighted row's value by `dir` (-1 / +1).
fn cycle_row(config: &mut SimConfig, row: CasRow, dir: i32) {
    match row {
        CasRow::Gender => config.gender = cycle_gender(config.gender, dir),
        CasRow::Skin => config.skin = wrap(config.skin, dir, skin_tones().len()),
        CasRow::HairStyle => config.hair_style = wrap(config.hair_style, dir, hair_styles().len()),
        CasRow::HairColor => config.hair_color = wrap(config.hair_color, dir, hair_colors().len()),
        CasRow::Shirt => config.shirt = wrap(config.shirt, dir, shirt_colors().len()),
        CasRow::Name | CasRow::Traits => {}
    }
}

/// Deterministic "randomiser" advanced by a counter (no RNG in this build).
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

/// Handle CAS keyboard input: navigation, value cycling, traits, randomise.
fn cas_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut key_events: EventReader<KeyboardInput>,
    mut config: ResMut<SimConfig>,
    mut cursor: ResMut<CasCursor>,
    mut seed: Local<usize>,
    mut next_state: ResMut<NextState<GameState>>,
) {
    // Row navigation.
    if keyboard.just_pressed(KeyCode::ArrowDown) {
        cursor.row = (cursor.row + 1) % ROWS.len();
    }
    if keyboard.just_pressed(KeyCode::ArrowUp) {
        cursor.row = (cursor.row + ROWS.len() - 1) % ROWS.len();
    }
    let row = ROWS[cursor.row];

    // Value carousel.
    if keyboard.just_pressed(KeyCode::ArrowRight) {
        cycle_row(&mut config, row, 1);
    }
    if keyboard.just_pressed(KeyCode::ArrowLeft) {
        cycle_row(&mut config, row, -1);
    }

    // Traits (always available via number keys).
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

    // Randomise (not while editing the name, so R can be typed into names).
    if row != CasRow::Name && keyboard.just_pressed(KeyCode::KeyR) {
        *seed = seed.wrapping_add(1);
        randomize(&mut config, *seed);
    }

    // Type the name when the Name row is active.
    if row == CasRow::Name {
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

    if keyboard.just_pressed(KeyCode::Enter) {
        next_state.set(GameState::LotSelect);
    }
}

/// Rebuild the CAS panel whenever the config or cursor changes (or first shown).
fn render_cas(
    mut commands: Commands,
    config: Res<SimConfig>,
    cursor: Res<CasCursor>,
    roots: Query<Entity, With<CasRoot>>,
) {
    if !config.is_changed() && !cursor.is_changed() && !roots.is_empty() {
        return;
    }
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }

    let active = ROWS[cursor.row];
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    justify_content: JustifyContent::Center,
                    row_gap: Val::Px(6.0),
                    ..default()
                },
                background_color: Color::srgba(0.05, 0.08, 0.12, 0.96).into(),
                ..default()
            },
            CasRoot,
            Name::new("Create-A-Sim"),
        ))
        .with_children(|root| {
            text(root, "Create A Sim", 34.0, Color::WHITE);

            // Name row (type to edit).
            let caret = if active == CasRow::Name { "_" } else { "" };
            row_line(root, active == CasRow::Name, false, &format!("Name: {}{caret}", config.first));
            // Carousel rows.
            row_line(
                root,
                active == CasRow::Gender,
                true,
                &format!("Gender: {:?}", config.gender),
            );
            row_line(
                root,
                active == CasRow::Skin,
                true,
                &format!("Skin: {}", skin_tones()[config.skin % skin_tones().len()].0),
            );
            row_line(
                root,
                active == CasRow::HairStyle,
                true,
                &format!(
                    "Hair: {}",
                    hair_styles()[config.hair_style % hair_styles().len()].0
                ),
            );
            row_line(
                root,
                active == CasRow::HairColor,
                true,
                &format!(
                    "Hair Color: {}",
                    hair_colors()[config.hair_color % hair_colors().len()].0
                ),
            );
            row_line(
                root,
                active == CasRow::Shirt,
                true,
                &format!("Shirt: {}", shirt_colors()[config.shirt % shirt_colors().len()].0),
            );

            // Traits row + list.
            let chosen = config
                .traits
                .iter()
                .map(|t| format!("{t:?}"))
                .collect::<Vec<_>>()
                .join(", ");
            row_line(
                root,
                active == CasRow::Traits,
                false,
                &format!(
                    "Traits ({}/{}): {}",
                    config.traits.len(),
                    MAX_TRAITS,
                    if chosen.is_empty() { "-" } else { &chosen }
                ),
            );
            root.spawn(NodeBundle {
                style: Style {
                    flex_direction: FlexDirection::Row,
                    flex_wrap: FlexWrap::Wrap,
                    column_gap: Val::Px(10.0),
                    max_width: Val::Px(560.0),
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                ..default()
            })
            .with_children(|list| {
                for (i, (t, label)) in TRAIT_CHOICES.iter().enumerate() {
                    let on = config.traits.contains(t);
                    text(
                        list,
                        &format!("{}:{}{}", i + 1, label, if on { "*" } else { "" }),
                        13.0,
                        if on {
                            Color::srgb(0.5, 0.95, 0.6)
                        } else {
                            Color::srgb(0.7, 0.75, 0.82)
                        },
                    );
                }
            });

            text(
                root,
                "Up/Down row   Left/Right change   type=name   1-9 traits   R random   [Enter] Done",
                14.0,
                Color::srgba(0.8, 0.86, 0.95, 0.85),
            );
        });
}

/// A row, highlighted when active and showing carousel arrows when cyclable.
fn row_line(parent: &mut ChildBuilder, active: bool, carousel: bool, value: &str) {
    let body = if carousel && active {
        format!("< {value} >")
    } else {
        value.to_string()
    };
    let marker = if active { "> " } else { "  " };
    let color = if active {
        Color::srgb(1.0, 0.92, 0.6)
    } else {
        Color::srgb(0.82, 0.88, 0.95)
    };
    text(parent, &format!("{marker}{body}"), 20.0, color);
}

fn exit_cas(mut commands: Commands, roots: Query<Entity, With<CasRoot>>) {
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
}

fn text(parent: &mut ChildBuilder, value: &str, size: f32, color: Color) {
    parent.spawn(TextBundle::from_section(
        value,
        TextStyle {
            font_size: size,
            color,
            ..default()
        },
    ));
}

/// Registers the Create-A-Sim screen.
pub struct CreateASimPlugin;

impl Plugin for CreateASimPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CasCursor>()
            .add_systems(OnExit(GameState::CreateASim), exit_cas)
            .add_systems(
                Update,
                (cas_input, render_cas).run_if(in_state(GameState::CreateASim)),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn traits_toggle_and_cap_at_three() {
        let mut config = SimConfig {
            traits: vec![],
            ..Default::default()
        };
        toggle_trait(&mut config, Trait::Creative);
        toggle_trait(&mut config, Trait::Genius);
        toggle_trait(&mut config, Trait::Neat);
        toggle_trait(&mut config, Trait::Active); // over the cap -> ignored
        assert_eq!(config.traits.len(), 3);
        assert!(!config.traits.contains(&Trait::Active));
        toggle_trait(&mut config, Trait::Genius); // remove
        assert_eq!(config.traits.len(), 2);
    }

    #[test]
    fn carousel_cycles_and_wraps() {
        let mut config = SimConfig {
            skin: 0,
            ..Default::default()
        };
        let n = skin_tones().len();
        cycle_row(&mut config, CasRow::Skin, -1);
        assert_eq!(config.skin, n - 1); // wrapped backwards
        cycle_row(&mut config, CasRow::Skin, 1);
        assert_eq!(config.skin, 0); // wrapped forwards
    }

    #[test]
    fn gender_cycles_both_directions() {
        assert_eq!(cycle_gender(SimGender::Male, 1), SimGender::Female);
        assert_eq!(cycle_gender(SimGender::Male, -1), SimGender::Custom);
    }

    #[test]
    fn randomize_stays_within_palettes() {
        let mut config = SimConfig::default();
        randomize(&mut config, 7);
        assert!(config.skin < skin_tones().len());
        assert!(config.hair_color < hair_colors().len());
        assert!(config.traits.len() <= MAX_TRAITS);
    }
}
