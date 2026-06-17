//! Job performance, promotions and demotions (Phase 9.3).
//!
//! Each worked day produces a performance score driven by the sim's mood and a
//! relevant skill; sustained high scores promote, poor scores demote, and missed
//! work erodes the score. (Coworker-relationship effects await the multi-sim
//! workplace; the career panel UI lands in Phase 10.)

use bevy::prelude::*;

use crate::career::skills::skill_for_career;
use crate::career::{Career, CareerDatabase, JobPerformance, Skills};
use crate::core::resources::GameTime;
use crate::core::state::GameState;
use crate::sim::SimId;
use crate::sim::moodlet::{ActiveMoodlets, Mood};

/// Score at or above which the sim is promoted.
const PROMOTE_AT: f32 = 80.0;
/// Score at or below which the sim is demoted.
const DEMOTE_AT: f32 = 25.0;
/// Performance lost when a sim misses a scheduled work day.
const MISSED_WORK_PENALTY: f32 = 25.0;

/// Mood's contribution to a day's performance (focused/happy help, foul moods hurt).
pub fn mood_performance(mood: Mood) -> f32 {
    match mood {
        Mood::Focused => 25.0,
        Mood::Happy | Mood::Energized => 20.0,
        Mood::Flirty => 8.0,
        Mood::Fine => 5.0,
        Mood::Tense | Mood::Uncomfortable => -10.0,
        Mood::Embarrassed => -12.0,
        Mood::Sad => -15.0,
        Mood::Angry => -20.0,
    }
}

/// Performance score (0..100) for a worked day from mood and a relevant skill.
pub fn performance_for_day(mood: Mood, skill_level: u8) -> f32 {
    (50.0 + mood_performance(mood) + skill_level as f32 * 2.5).clamp(0.0, 100.0)
}

/// New performance score after missing a scheduled work day.
pub fn performance_after_absence(score: f32) -> f32 {
    (score - MISSED_WORK_PENALTY).max(0.0)
}

/// Whether a performance score promotes, holds, or demotes the sim.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CareerOutcome {
    Promote,
    Hold,
    Demote,
}

/// Classify a performance score into a career outcome.
pub fn outcome_for(score: f32) -> CareerOutcome {
    if score >= PROMOTE_AT {
        CareerOutcome::Promote
    } else if score <= DEMOTE_AT {
        CareerOutcome::Demote
    } else {
        CareerOutcome::Hold
    }
}

/// Apply an outcome to a 1-based career level, clamped to `[1, max_level]`.
pub fn apply_outcome(level: u8, outcome: CareerOutcome, max_level: u8) -> u8 {
    match outcome {
        CareerOutcome::Promote => (level + 1).min(max_level.max(1)),
        CareerOutcome::Demote => level.saturating_sub(1).max(1),
        CareerOutcome::Hold => level,
    }
}

/// Give any careerless demo sim a starter Tech job so the system has subjects.
fn assign_demo_careers(
    mut commands: Commands,
    sims: Query<Entity, (With<SimId>, Without<Career>)>,
) {
    for entity in &sims {
        commands.entity(entity).insert((
            Career {
                name: "Tech".to_string(),
                level: 1,
                daily_performance: 50.0,
            },
            JobPerformance {
                score: 50.0,
                days_missed: 0,
            },
        ));
    }
}

/// Once per in-game day, score each employed sim's day and apply promotions or
/// demotions based on the result.
#[allow(clippy::type_complexity)]
fn daily_performance_system(
    game_time: Res<GameTime>,
    careers: Res<CareerDatabase>,
    mut last_day: Local<u32>,
    mut sims: Query<(
        &mut Career,
        &mut JobPerformance,
        &ActiveMoodlets,
        Option<&Skills>,
    )>,
) {
    if game_time.day == *last_day {
        return;
    }
    *last_day = game_time.day;

    for (mut career, mut perf, moods, skills) in &mut sims {
        // The career's relevant skill raises performance (and so promotion odds).
        let skill_level = skills
            .map(|s| s.level(skill_for_career(&career.name)))
            .unwrap_or(0);
        // Attendance modelling lands with the work schedule (9.4); assume the
        // sim showed up for now.
        let score = performance_for_day(moods.dominant_mood(), skill_level);
        perf.score = score;
        let max_level = careers
            .get(&career.name)
            .map(|c| c.max_level())
            .unwrap_or(career.level);
        career.level = apply_outcome(career.level, outcome_for(score), max_level);
        career.daily_performance = score;
    }
}

/// Registers the job-performance systems (live mode only).
pub struct PerformancePlugin;

impl Plugin for PerformancePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            Update,
            (assign_demo_careers, daily_performance_system).run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn good_mood_and_skill_raise_performance() {
        let low = performance_for_day(Mood::Angry, 0);
        let high = performance_for_day(Mood::Focused, 8);
        assert!(high > low);
        // Scores stay within bounds.
        assert!((0.0..=100.0).contains(&performance_for_day(Mood::Focused, 10)));
        assert!((0.0..=100.0).contains(&performance_for_day(Mood::Angry, 0)));
    }

    #[test]
    fn outcomes_classify_by_threshold() {
        assert_eq!(outcome_for(85.0), CareerOutcome::Promote);
        assert_eq!(outcome_for(50.0), CareerOutcome::Hold);
        assert_eq!(outcome_for(20.0), CareerOutcome::Demote);
    }

    #[test]
    fn promotion_and_demotion_clamp_to_track() {
        // Promotion stops at the top.
        assert_eq!(apply_outcome(5, CareerOutcome::Promote, 5), 5);
        assert_eq!(apply_outcome(2, CareerOutcome::Promote, 5), 3);
        // Demotion never drops below level 1.
        assert_eq!(apply_outcome(1, CareerOutcome::Demote, 5), 1);
        assert_eq!(apply_outcome(3, CareerOutcome::Demote, 5), 2);
    }

    #[test]
    fn missing_work_erodes_performance() {
        assert_eq!(performance_after_absence(50.0), 25.0);
        assert_eq!(performance_after_absence(10.0), 0.0);
    }
}
