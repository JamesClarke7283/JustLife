//! Create-A-Sim screen (start of the New Game flow).
//!
//! The player customises their one starting sim - name, gender, and up to three
//! traits - then confirms to head to lot selection. Keyboard-driven so it works
//! in the headless harness: N cycles the name, G cycles gender, 1-9 toggle
//! traits, R randomises, Enter confirms.

use bevy::prelude::*;

use crate::core::state::GameState;
use crate::sim::{SimConfig, SimGender, Trait};

/// First names offered/cycled in CAS.
const NAMES: [&str; 8] = [
    "Alex", "Sam", "Robin", "Jordan", "Casey", "Riley", "Quinn", "Avery",
];

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

/// Cycle to the next gender.
fn next_gender(g: SimGender) -> SimGender {
    match g {
        SimGender::Male => SimGender::Female,
        SimGender::Female => SimGender::Custom,
        SimGender::Custom => SimGender::Male,
    }
}

/// Deterministic "randomiser" advanced by a counter (no RNG in this build).
fn randomize(config: &mut SimConfig, seed: usize) {
    config.first = NAMES[seed % NAMES.len()].to_string();
    config.gender = match seed % 3 {
        0 => SimGender::Female,
        1 => SimGender::Male,
        _ => SimGender::Custom,
    };
    config.skin = seed % 4;
    config.traits.clear();
    for i in 0..MAX_TRAITS {
        let (t, _) = TRAIT_CHOICES[(seed + i * 3) % TRAIT_CHOICES.len()];
        if !config.traits.contains(&t) {
            config.traits.push(t);
        }
    }
}

/// Handle CAS keyboard input.
fn cas_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut config: ResMut<SimConfig>,
    mut seed: Local<usize>,
    mut next_state: ResMut<NextState<GameState>>,
) {
    if keyboard.just_pressed(KeyCode::KeyN) {
        let cur = NAMES.iter().position(|n| *n == config.first).unwrap_or(0);
        config.first = NAMES[(cur + 1) % NAMES.len()].to_string();
    }
    if keyboard.just_pressed(KeyCode::KeyG) {
        config.gender = next_gender(config.gender);
    }
    if keyboard.just_pressed(KeyCode::KeyR) {
        *seed = seed.wrapping_add(1);
        randomize(&mut config, *seed);
    }
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
    if keyboard.just_pressed(KeyCode::Enter) {
        // On to choosing and buying a lot.
        next_state.set(GameState::LotSelect);
    }
}

/// Rebuild the CAS panel whenever the config changes (or when first shown).
fn render_cas(mut commands: Commands, config: Res<SimConfig>, roots: Query<Entity, With<CasRoot>>) {
    if !config.is_changed() && !roots.is_empty() {
        return;
    }
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }

    let selected_traits = config
        .traits
        .iter()
        .map(|t| format!("{t:?}"))
        .collect::<Vec<_>>()
        .join(", ");

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
                    row_gap: Val::Px(8.0),
                    ..default()
                },
                background_color: Color::srgba(0.05, 0.08, 0.12, 0.96).into(),
                ..default()
            },
            CasRoot,
            Name::new("Create-A-Sim"),
        ))
        .with_children(|root| {
            heading(root, "Create A Sim", 34.0, Color::WHITE);
            line(
                root,
                &format!("Name:    {} {}", config.first, config.last),
                Color::srgb(0.85, 0.92, 1.0),
            );
            line(
                root,
                &format!("Gender:  {:?}", config.gender),
                Color::srgb(0.85, 0.92, 1.0),
            );
            line(
                root,
                &format!("Skin:    tone {}", config.skin + 1),
                Color::srgb(0.85, 0.92, 1.0),
            );
            line(
                root,
                &format!(
                    "Traits ({}/{}):  {}",
                    config.traits.len(),
                    MAX_TRAITS,
                    if selected_traits.is_empty() {
                        "-".to_string()
                    } else {
                        selected_traits
                    }
                ),
                Color::srgb(1.0, 0.92, 0.6),
            );

            // Trait choices, highlighting the chosen ones.
            root.spawn(NodeBundle {
                style: Style {
                    flex_direction: FlexDirection::Column,
                    margin: UiRect::vertical(Val::Px(6.0)),
                    ..default()
                },
                ..default()
            })
            .with_children(|list| {
                for (i, (t, label)) in TRAIT_CHOICES.iter().enumerate() {
                    let chosen = config.traits.contains(t);
                    line(
                        list,
                        &format!("  {}: {}{}", i + 1, label, if chosen { "  *" } else { "" }),
                        if chosen {
                            Color::srgb(0.5, 0.95, 0.6)
                        } else {
                            Color::srgb(0.7, 0.75, 0.82)
                        },
                    );
                }
            });

            line(
                root,
                "N name   G gender   1-9 traits   R randomize   [Enter] Done",
                Color::srgba(0.8, 0.86, 0.95, 0.85),
            );
        });
}

fn exit_cas(mut commands: Commands, roots: Query<Entity, With<CasRoot>>) {
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
}

fn heading(parent: &mut ChildBuilder, text: &str, size: f32, color: Color) {
    parent.spawn(TextBundle::from_section(
        text,
        TextStyle {
            font_size: size,
            color,
            ..default()
        },
    ));
}

fn line(parent: &mut ChildBuilder, text: &str, color: Color) {
    parent.spawn(TextBundle::from_section(
        text,
        TextStyle {
            font_size: 18.0,
            color,
            ..default()
        },
    ));
}

/// Registers the Create-A-Sim screen.
pub struct CreateASimPlugin;

impl Plugin for CreateASimPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnExit(GameState::CreateASim), exit_cas)
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
        // Toggling an existing trait removes it.
        toggle_trait(&mut config, Trait::Genius);
        assert!(!config.traits.contains(&Trait::Genius));
        assert_eq!(config.traits.len(), 2);
    }

    #[test]
    fn gender_cycles_through_all_three() {
        let mut g = SimGender::Male;
        let mut seen = std::collections::HashSet::new();
        for _ in 0..3 {
            seen.insert(format!("{g:?}"));
            g = next_gender(g);
        }
        assert_eq!(seen.len(), 3);
    }

    #[test]
    fn randomize_picks_valid_traits_within_cap() {
        let mut config = SimConfig::default();
        randomize(&mut config, 5);
        assert!(config.traits.len() <= MAX_TRAITS);
        assert!(!config.first.is_empty());
    }
}
