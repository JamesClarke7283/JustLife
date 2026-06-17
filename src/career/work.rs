//! Work schedule: sims leave for their shift, earn a wage, and come home
//! (Phase 9.4).
//!
//! When a sim's career shift is in progress on a work day it heads off-lot
//! (hidden) until the shift ends, then returns home and banks its pay (scaled by
//! job performance). Overtime and accrued vacation are player-driven and wait on
//! the career-panel UI (Phase 10).

use bevy::prelude::*;

use crate::career::{Career, CareerDatabase, CareerLevel, JobPerformance};
use crate::core::resources::{GameTime, MoneyResource};
use crate::core::state::GameState;
use crate::sim::AnimationState;

/// Where sims wait out their shift (well off the visible lot).
const OFF_LOT: Vec3 = Vec3::new(0.0, -50.0, 0.0);

/// Marks a sim currently away at work, remembering where home was.
#[derive(Component, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct AtWork {
    pub home: Vec3,
}

/// Weekday index for an absolute day counter (0 = Sunday .. 6 = Saturday).
pub fn day_of_week(day: u32) -> u8 {
    (day % 7) as u8
}

/// Whether a career level schedules work on the given absolute day.
pub fn is_work_day(level: &CareerLevel, day: u32) -> bool {
    level.work_days.contains(&day_of_week(day))
}

/// Whether `hour` falls within a shift, handling overnight shifts (start > end).
pub fn in_shift(hour: u32, start: u8, end: u8) -> bool {
    let h = hour as u8;
    if start <= end {
        h >= start && h < end
    } else {
        h >= start || h < end
    }
}

/// Length of a shift in hours, handling overnight wrap-around.
pub fn shift_hours(start: u8, end: u8) -> u8 {
    if start <= end {
        end - start
    } else {
        24 - start + end
    }
}

/// Pay banked for a completed shift: hourly wage * hours, scaled 0.5x..1.5x by
/// job performance.
pub fn shift_pay(salary: u32, hours: u8, performance: f32) -> i64 {
    let factor = 0.5 + (performance / 100.0).clamp(0.0, 1.0);
    (salary as f32 * hours as f32 * factor).round() as i64
}

/// Send sims to work when their shift starts and bring them home (with pay) when
/// it ends.
#[allow(clippy::type_complexity)]
fn work_schedule_system(
    game_time: Res<GameTime>,
    careers: Res<CareerDatabase>,
    mut money: ResMut<MoneyResource>,
    mut commands: Commands,
    mut sims: Query<(
        Entity,
        &Career,
        &JobPerformance,
        &mut Transform,
        &mut Visibility,
        &mut AnimationState,
        Option<&AtWork>,
    )>,
) {
    for (entity, career, perf, mut transform, mut visibility, mut anim, at_work) in &mut sims {
        let Some(level) = careers
            .get(&career.name)
            .and_then(|c| c.level_at(career.level))
        else {
            continue;
        };
        let should_work = is_work_day(level, game_time.day)
            && in_shift(game_time.hour, level.start_hour, level.end_hour);

        match (should_work, at_work) {
            // Shift starting: head off-lot and clock in.
            (true, None) => {
                commands.entity(entity).insert(AtWork {
                    home: transform.translation,
                });
                transform.translation = OFF_LOT;
                *visibility = Visibility::Hidden;
                *anim = AnimationState::Working;
            }
            // Shift over: come home and bank the day's pay.
            (false, Some(at_work)) => {
                transform.translation = at_work.home;
                *visibility = Visibility::Visible;
                *anim = AnimationState::Idle;
                let hours = shift_hours(level.start_hour, level.end_hour);
                money.deposit(shift_pay(level.salary, hours, perf.score));
                commands.entity(entity).remove::<AtWork>();
            }
            _ => {}
        }
    }
}

/// Registers the work-schedule system (live mode only).
pub struct WorkSchedulePlugin;

impl Plugin for WorkSchedulePlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<AtWork>().add_systems(
            Update,
            work_schedule_system.run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn level(start: u8, end: u8, days: &[u8]) -> CareerLevel {
        CareerLevel {
            title: "Test".into(),
            salary: 20,
            work_days: days.to_vec(),
            start_hour: start,
            end_hour: end,
        }
    }

    #[test]
    fn weekday_mapping_and_work_days() {
        // Day 6 is Saturday; day 8 is Monday in this counter.
        assert_eq!(day_of_week(6), 6);
        assert_eq!(day_of_week(8), 1);
        let weekdays = level(9, 17, &[1, 2, 3, 4, 5]);
        assert!(!is_work_day(&weekdays, 6)); // Saturday off
        assert!(is_work_day(&weekdays, 8)); // Monday on
    }

    #[test]
    fn shift_windows_handle_overnight() {
        // Day shift 9-17.
        assert!(in_shift(9, 9, 17));
        assert!(in_shift(16, 9, 17));
        assert!(!in_shift(17, 9, 17));
        assert!(!in_shift(8, 9, 17));
        assert_eq!(shift_hours(9, 17), 8);
        // Overnight shift 22-04.
        assert!(in_shift(23, 22, 4));
        assert!(in_shift(2, 22, 4));
        assert!(!in_shift(12, 22, 4));
        assert_eq!(shift_hours(22, 4), 6);
    }

    #[test]
    fn pay_scales_with_hours_and_performance() {
        // 20/hr * 8h at perf 50 -> factor 1.0 -> 160.
        assert_eq!(shift_pay(20, 8, 50.0), 160);
        // Higher performance pays more; lower pays less.
        assert!(shift_pay(20, 8, 100.0) > shift_pay(20, 8, 50.0));
        assert!(shift_pay(20, 8, 0.0) < shift_pay(20, 8, 50.0));
    }
}
