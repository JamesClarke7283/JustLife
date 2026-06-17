//! Job board: let the player take a career (per user request).
//!
//! The player sim starts unemployed. Pressing J opens a board of the available
//! careers (level-1 title + salary); Up/Down choose, Enter takes the job, Esc
//! closes. Once hired, the work-schedule system sends the sim to work.
//! Keyboard-driven so it works in the headless harness.

use bevy::prelude::*;

use crate::career::economy::format_money;
use crate::career::{Career, CareerDatabase, JobPerformance};
use crate::core::state::GameState;
use crate::sim::SimManager;

/// Job board open state + highlighted career.
#[derive(Resource, Default)]
struct JobBoard {
    open: bool,
    cursor: usize,
}

#[derive(Component)]
struct JobBoardRoot;

/// Open/close the board and take the highlighted job.
fn job_board_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    careers: Res<CareerDatabase>,
    manager: Res<SimManager>,
    mut board: ResMut<JobBoard>,
    mut toasts: EventWriter<crate::core::events::ToastEvent>,
    mut commands: Commands,
) {
    if keyboard.just_pressed(KeyCode::KeyJ) {
        board.open = !board.open;
        board.cursor = 0;
    }
    if !board.open {
        return;
    }
    let n = careers.careers.len();
    if n == 0 {
        return;
    }
    if keyboard.just_pressed(KeyCode::Escape) {
        board.open = false;
        return;
    }
    if keyboard.just_pressed(KeyCode::ArrowDown) {
        board.cursor = (board.cursor + 1) % n;
    }
    if keyboard.just_pressed(KeyCode::ArrowUp) {
        board.cursor = (board.cursor + n - 1) % n;
    }
    if keyboard.just_pressed(KeyCode::Enter)
        && let Some(&sim) = manager.sims.first()
    {
        let career = &careers.careers[board.cursor];
        commands.entity(sim).insert((
            Career {
                name: career.name.clone(),
                level: 1,
                daily_performance: 50.0,
            },
            JobPerformance {
                score: 50.0,
                days_missed: 0,
            },
        ));
        toasts.send(crate::core::events::ToastEvent::success(format!(
            "Hired! You're now in {}.",
            career.name
        )));
        board.open = false;
    }
}

/// Rebuild the board overlay when it opens/changes.
fn render_job_board(
    mut commands: Commands,
    board: Res<JobBoard>,
    careers: Res<CareerDatabase>,
    manager: Res<SimManager>,
    current: Query<&Career>,
    roots: Query<Entity, With<JobBoardRoot>>,
) {
    if !board.is_changed() && !roots.is_empty() {
        return;
    }
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
    if !board.open {
        return;
    }

    let employed = manager
        .sims
        .first()
        .and_then(|e| current.get(*e).ok())
        .map(|c| c.name.clone());

    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Percent(50.0),
                    top: Val::Percent(18.0),
                    margin: UiRect::left(Val::Px(-200.0)),
                    width: Val::Px(400.0),
                    flex_direction: FlexDirection::Column,
                    padding: UiRect::all(Val::Px(14.0)),
                    row_gap: Val::Px(6.0),
                    ..default()
                },
                background_color: Color::srgba(0.06, 0.09, 0.13, 0.96).into(),
                border_radius: BorderRadius::all(Val::Px(8.0)),
                ..default()
            },
            JobBoardRoot,
            Name::new("Job Board"),
        ))
        .with_children(|root| {
            line(root, "Find a Job", 26.0, Color::WHITE);
            line(
                root,
                &match &employed {
                    Some(name) => format!("Current: {name}"),
                    None => "Current: Unemployed".to_string(),
                },
                15.0,
                Color::srgb(0.7, 0.8, 0.9),
            );
            for (i, career) in careers.careers.iter().enumerate() {
                let selected = i == board.cursor;
                let (title, salary) = career
                    .level_at(1)
                    .map(|l| (l.title.clone(), l.salary as i64))
                    .unwrap_or_else(|| ("-".to_string(), 0));
                line(
                    root,
                    &format!(
                        "{} {} - {} ({}/hr)",
                        if selected { ">" } else { " " },
                        career.name,
                        title,
                        format_money(salary)
                    ),
                    17.0,
                    if selected {
                        Color::srgb(0.95, 0.85, 0.4)
                    } else {
                        Color::srgb(0.82, 0.88, 0.95)
                    },
                );
            }
            line(
                root,
                "Up/Down choose   [Enter] Take job   [Esc/J] Close",
                13.0,
                Color::srgba(0.8, 0.86, 0.95, 0.85),
            );
        });
}

fn line(parent: &mut ChildBuilder, value: &str, size: f32, color: Color) {
    parent.spawn(TextBundle::from_section(
        value,
        TextStyle {
            font_size: size,
            color,
            ..default()
        },
    ));
}

fn close_on_exit(
    mut board: ResMut<JobBoard>,
    mut commands: Commands,
    roots: Query<Entity, With<JobBoardRoot>>,
) {
    board.open = false;
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
}

/// Registers the job board (live mode only).
pub struct JobBoardPlugin;

impl Plugin for JobBoardPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<JobBoard>()
            .add_systems(OnExit(GameState::LiveMode), close_on_exit)
            .add_systems(
                Update,
                (job_board_input, render_job_board).run_if(in_state(GameState::LiveMode)),
            );
    }
}
