//! Sim info panel (Phase 10.4).
//!
//! A tabbed modal showing everything about the focus sim: bio header plus
//! Needs / Skills / Relationships / Career / Inventory tabs. Opened by clicking
//! the HUD portrait or pressing `I`; `Tab` cycles tabs and `Esc` closes (the
//! keyboard path keeps it reachable in the headless WASM harness).

use bevy::prelude::*;

use crate::career::skills::skill_for_career;
use crate::career::{Career, CareerDatabase, JobPerformance, SkillType, Skills};
use crate::core::state::GameState;
use crate::sim::moodlet::ActiveMoodlets;
use crate::sim::needs::{NeedType, Needs};
use crate::sim::{SimAge, SimGender, SimManager, SimName, SimTraits};
use crate::social::{RelationshipData, Relationships};

/// Which tab of the info panel is shown.
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum PanelTab {
    #[default]
    Needs,
    Skills,
    Relationships,
    Career,
    Inventory,
}

impl PanelTab {
    const ALL: [PanelTab; 5] = [
        PanelTab::Needs,
        PanelTab::Skills,
        PanelTab::Relationships,
        PanelTab::Career,
        PanelTab::Inventory,
    ];

    fn label(self) -> &'static str {
        match self {
            PanelTab::Needs => "Needs",
            PanelTab::Skills => "Skills",
            PanelTab::Relationships => "Relationships",
            PanelTab::Career => "Career",
            PanelTab::Inventory => "Inventory",
        }
    }

    fn next(self) -> PanelTab {
        let i = Self::ALL.iter().position(|t| *t == self).unwrap_or(0);
        Self::ALL[(i + 1) % Self::ALL.len()]
    }
}

/// Panel open state and active tab.
#[derive(Resource, Default)]
struct SimPanel {
    open: bool,
    tab: PanelTab,
}

/// Marks the HUD portrait button that toggles the panel.
#[derive(Component)]
pub struct SimPortraitButton;

/// Marks the panel UI root for teardown/rebuild.
#[derive(Component)]
struct SimPanelRoot;

/// All skills in display order.
fn skill_list() -> [(SkillType, &'static str); 9] {
    [
        (SkillType::Cooking, "Cooking"),
        (SkillType::Handiness, "Handiness"),
        (SkillType::Charisma, "Charisma"),
        (SkillType::Fitness, "Fitness"),
        (SkillType::Logic, "Logic"),
        (SkillType::Creativity, "Creativity"),
        (SkillType::Gardening, "Gardening"),
        (SkillType::Fishing, "Fishing"),
        (SkillType::Programming, "Programming"),
    ]
}

/// Toggle/close the panel and cycle tabs from the keyboard or portrait click.
fn panel_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    portrait: Query<&Interaction, (Changed<Interaction>, With<SimPortraitButton>)>,
    mut panel: ResMut<SimPanel>,
) {
    let portrait_clicked = portrait.iter().any(|i| *i == Interaction::Pressed);
    if keyboard.just_pressed(KeyCode::KeyI) || portrait_clicked {
        panel.open = !panel.open;
    }
    if !panel.open {
        return;
    }
    if keyboard.just_pressed(KeyCode::Escape) {
        panel.open = false;
    } else if keyboard.just_pressed(KeyCode::Tab) {
        panel.tab = panel.tab.next();
    }
}

/// Rebuild the panel when it opens, closes, or switches tab.
#[allow(clippy::too_many_arguments)]
fn render_panel(
    mut commands: Commands,
    panel: Res<SimPanel>,
    roots: Query<Entity, With<SimPanelRoot>>,
    manager: Res<SimManager>,
    careers: Res<CareerDatabase>,
    names: Query<&SimName>,
    bio: Query<(&SimName, &SimAge, &SimGender, &SimTraits)>,
    needs: Query<&Needs>,
    moodlets: Query<&ActiveMoodlets>,
    skills: Query<&Skills>,
    career: Query<(&Career, &JobPerformance)>,
    relationships: Query<&Relationships>,
) {
    if !panel.is_changed() {
        return;
    }
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
    if !panel.open {
        return;
    }
    let Some(focus) = manager.sims.first().copied() else {
        return;
    };

    let root = commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    right: Val::Px(20.0),
                    top: Val::Px(70.0),
                    width: Val::Px(360.0),
                    flex_direction: FlexDirection::Column,
                    padding: UiRect::all(Val::Px(12.0)),
                    row_gap: Val::Px(8.0),
                    ..default()
                },
                background_color: Color::srgba(0.06, 0.09, 0.13, 0.95).into(),
                border_radius: BorderRadius::all(Val::Px(8.0)),
                ..default()
            },
            SimPanelRoot,
            Name::new("Sim Info Panel"),
        ))
        .id();

    commands.entity(root).with_children(|panel_ui| {
        // Bio header.
        if let Ok((name, age, gender, traits)) = bio.get(focus) {
            heading(panel_ui, &format!("{} {}", name.first, name.last), 24.0);
            let traits_str = traits
                .traits
                .iter()
                .map(|t| format!("{t:?}"))
                .collect::<Vec<_>>()
                .join(", ");
            line(
                panel_ui,
                &format!("{age:?}  -  {gender:?}"),
                Color::srgb(0.8, 0.85, 0.9),
            );
            line(
                panel_ui,
                &format!("Traits: {traits_str}"),
                Color::srgb(0.8, 0.85, 0.9),
            );
            line(panel_ui, "Aspiration: -", Color::srgb(0.6, 0.65, 0.7));
        }

        // Tab row.
        panel_ui
            .spawn(NodeBundle {
                style: Style {
                    column_gap: Val::Px(4.0),
                    margin: UiRect::vertical(Val::Px(4.0)),
                    flex_wrap: FlexWrap::Wrap,
                    row_gap: Val::Px(4.0),
                    ..default()
                },
                ..default()
            })
            .with_children(|row| {
                for tab in PanelTab::ALL {
                    let active = tab == panel.tab;
                    row.spawn(NodeBundle {
                        style: Style {
                            padding: UiRect::axes(Val::Px(8.0), Val::Px(4.0)),
                            ..default()
                        },
                        background_color: if active {
                            Color::srgb(0.95, 0.78, 0.30).into()
                        } else {
                            Color::srgba(0.2, 0.28, 0.36, 0.9).into()
                        },
                        border_radius: BorderRadius::all(Val::Px(4.0)),
                        ..default()
                    })
                    .with_children(|b| {
                        b.spawn(TextBundle::from_section(
                            tab.label(),
                            TextStyle {
                                font_size: 13.0,
                                color: if active { Color::BLACK } else { Color::WHITE },
                                ..default()
                            },
                        ));
                    });
                }
            });

        // Tab content.
        match panel.tab {
            PanelTab::Needs => {
                render_needs(panel_ui, needs.get(focus).ok(), moodlets.get(focus).ok())
            }
            PanelTab::Skills => render_skills(panel_ui, skills.get(focus).ok()),
            PanelTab::Relationships => {
                render_relationships(panel_ui, relationships.get(focus).ok(), &names)
            }
            PanelTab::Career => render_career(panel_ui, career.get(focus).ok(), &careers),
            PanelTab::Inventory => {
                line(panel_ui, "Inventory is empty.", Color::srgb(0.7, 0.75, 0.8))
            }
        }

        line(
            panel_ui,
            "[I] close   [Tab] next tab",
            Color::srgba(0.7, 0.75, 0.85, 0.8),
        );
    });
}

fn render_needs(parent: &mut ChildBuilder, needs: Option<&Needs>, moods: Option<&ActiveMoodlets>) {
    let Some(needs) = needs else { return };
    for (need, label) in [
        (NeedType::Hunger, "Hunger"),
        (NeedType::Energy, "Energy"),
        (NeedType::Social, "Social"),
        (NeedType::Fun, "Fun"),
        (NeedType::Hygiene, "Hygiene"),
        (NeedType::Bladder, "Bladder"),
    ] {
        line(
            parent,
            &format!("{label}: {:.0}/100", needs.get(need)),
            Color::srgb(0.85, 0.9, 0.95),
        );
    }
    if let Some(moods) = moods {
        heading(parent, "Moodlets", 15.0);
        if moods.moodlets.is_empty() {
            line(parent, "  (none)", Color::srgb(0.6, 0.65, 0.7));
        }
        for m in &moods.moodlets {
            line(
                parent,
                &format!("  {} ({:+})", m.name, m.impact),
                Color::srgb(0.8, 0.85, 0.9),
            );
        }
    }
}

fn render_skills(parent: &mut ChildBuilder, skills: Option<&Skills>) {
    let skills = skills.cloned().unwrap_or_default();
    for (skill, label) in skill_list() {
        let level = skills.level(skill);
        let pips = "#".repeat(level as usize) + &"-".repeat((10 - level) as usize);
        line(
            parent,
            &format!("{label:<11} {pips} {level}"),
            Color::srgb(0.85, 0.9, 0.95),
        );
    }
}

fn render_relationships(
    parent: &mut ChildBuilder,
    rels: Option<&Relationships>,
    names: &Query<&SimName>,
) {
    let Some(rels) = rels else {
        line(parent, "No relationships yet.", Color::srgb(0.7, 0.75, 0.8));
        return;
    };
    let mut entries: Vec<(&Entity, &RelationshipData)> = rels.relationships.iter().collect();
    entries.sort_by(|a, b| b.1.friendship_score.total_cmp(&a.1.friendship_score));
    if entries.is_empty() {
        line(parent, "No relationships yet.", Color::srgb(0.7, 0.75, 0.8));
    }
    for (entity, data) in entries {
        let who = names
            .get(*entity)
            .map(|n| n.first.clone())
            .unwrap_or_else(|_| "Someone".to_string());
        line(
            parent,
            &format!(
                "{who}: {:?}  (F {:.0} / R {:.0})",
                data.sentiment, data.friendship_score, data.romance_score
            ),
            Color::srgb(0.85, 0.9, 0.95),
        );
    }
}

fn render_career(
    parent: &mut ChildBuilder,
    career: Option<(&Career, &JobPerformance)>,
    careers: &CareerDatabase,
) {
    let Some((career, perf)) = career else {
        line(parent, "Unemployed.", Color::srgb(0.7, 0.75, 0.8));
        return;
    };
    let title = careers
        .get(&career.name)
        .and_then(|c| c.level_at(career.level))
        .map(|l| l.title.clone())
        .unwrap_or_else(|| "-".to_string());
    line(
        parent,
        &format!("{} - level {}", career.name, career.level),
        Color::srgb(0.85, 0.9, 0.95),
    );
    line(
        parent,
        &format!("Title: {title}"),
        Color::srgb(0.85, 0.9, 0.95),
    );
    line(
        parent,
        &format!("Performance: {:.0}/100", perf.score),
        Color::srgb(0.85, 0.9, 0.95),
    );
    line(
        parent,
        &format!("Key skill: {:?}", skill_for_career(&career.name)),
        Color::srgb(0.7, 0.75, 0.8),
    );
}

/// A bold heading line.
fn heading(parent: &mut ChildBuilder, text: &str, size: f32) {
    parent.spawn(TextBundle::from_section(
        text,
        TextStyle {
            font_size: size,
            color: Color::WHITE,
            ..default()
        },
    ));
}

/// A normal body line.
fn line(parent: &mut ChildBuilder, text: &str, color: Color) {
    parent.spawn(TextBundle::from_section(
        text,
        TextStyle {
            font_size: 14.0,
            color,
            ..default()
        },
    ));
}

/// Close the panel when leaving live mode.
fn close_on_exit(
    mut panel: ResMut<SimPanel>,
    mut commands: Commands,
    roots: Query<Entity, With<SimPanelRoot>>,
) {
    panel.open = false;
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
}

/// Registers the sim info panel.
pub struct SimPanelPlugin;

impl Plugin for SimPanelPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<SimPanel>()
            .add_systems(OnExit(GameState::LiveMode), close_on_exit)
            .add_systems(
                Update,
                (panel_input, render_panel).run_if(in_state(GameState::LiveMode)),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tabs_cycle_in_order_and_wrap() {
        assert_eq!(PanelTab::Needs.next(), PanelTab::Skills);
        assert_eq!(PanelTab::Inventory.next(), PanelTab::Needs);
        // All five tabs reachable by cycling.
        let mut seen = std::collections::HashSet::new();
        let mut t = PanelTab::Needs;
        for _ in 0..PanelTab::ALL.len() {
            seen.insert(t);
            t = t.next();
        }
        assert_eq!(seen.len(), 5);
    }

    #[test]
    fn every_skill_has_a_label() {
        assert_eq!(skill_list().len(), 9);
    }
}
