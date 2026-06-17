//! Skills: XP gain from activities, levels, and their effect on work and
//! interactions (Phase 9.5).
//!
//! Sims earn skill XP while doing relevant activities (cooking builds Cooking,
//! working builds Logic, and so on). Levels (0-10) derive from XP, feed job
//! performance (the relevant skill raises promotion odds) and scale interaction
//! effectiveness. The visual skill bar lives in the sim info panel (Phase 10).

use bevy::prelude::*;

use crate::career::{SkillType, Skills};
use crate::core::resources::{GameConfig, GameSpeed};
use crate::core::state::GameState;
use crate::sim::{AnimationState, SimId};

/// Maximum skill level.
pub const MAX_SKILL: u8 = 10;
/// XP required per level (level n needs n * this much cumulative XP).
pub const XP_PER_LEVEL: f32 = 100.0;
/// Skill XP earned per in-game minute of a relevant activity.
const SKILL_GAIN_RATE: f32 = 0.6;

/// Derive a 0-10 skill level from accumulated XP.
pub fn level_for_xp(xp: f32) -> u8 {
    ((xp / XP_PER_LEVEL).floor() as u8).min(MAX_SKILL)
}

/// Effectiveness multiplier a skill level grants an interaction (1.0 at level 0
/// up to 2.0 at level 10): better meals, faster repairs, more charming chats.
pub fn effectiveness_multiplier(level: u8) -> f32 {
    1.0 + level.min(MAX_SKILL) as f32 / MAX_SKILL as f32
}

/// The skill trained by a given activity, if any.
pub fn skill_for_activity(anim: AnimationState) -> Option<SkillType> {
    match anim {
        AnimationState::Cooking => Some(SkillType::Cooking),
        AnimationState::Working => Some(SkillType::Logic),
        AnimationState::Playing => Some(SkillType::Creativity),
        AnimationState::Talking | AnimationState::Socializing => Some(SkillType::Charisma),
        AnimationState::Running => Some(SkillType::Fitness),
        _ => None,
    }
}

/// The skill most relevant to a career track (gates promotions).
pub fn skill_for_career(career: &str) -> SkillType {
    match career {
        "Tech" => SkillType::Logic,
        "Culinary" => SkillType::Cooking,
        "Athletic" => SkillType::Fitness,
        "Creative" => SkillType::Creativity,
        "Entertainment" | "Business" => SkillType::Charisma,
        "Medical" => SkillType::Logic,
        "Criminal" => SkillType::Handiness,
        _ => SkillType::Logic,
    }
}

impl Skills {
    /// Add XP to a skill.
    pub fn add_xp(&mut self, skill: SkillType, amount: f32) {
        *self.progress.entry(skill).or_default() += amount;
    }

    /// Accumulated XP in a skill.
    pub fn xp(&self, skill: SkillType) -> f32 {
        self.progress.get(&skill).copied().unwrap_or(0.0)
    }

    /// Current level (0-10) of a skill.
    pub fn level(&self, skill: SkillType) -> u8 {
        level_for_xp(self.xp(skill))
    }
}

/// Give every sim a Skills component so skill systems have something to track.
fn ensure_skills(mut commands: Commands, sims: Query<Entity, (With<SimId>, Without<Skills>)>) {
    for entity in &sims {
        commands.entity(entity).insert(Skills::default());
    }
}

/// Award skill XP for whatever a sim is currently doing.
fn skill_gain_system(
    game_config: Res<GameConfig>,
    game_speed: Res<GameSpeed>,
    time: Res<Time>,
    mut sims: Query<(&AnimationState, &mut Skills)>,
) {
    let speed = game_speed.multiplier();
    if speed == 0.0 {
        return;
    }
    let game_minutes = time.delta_seconds() * speed / game_config.real_seconds_per_game_minute;
    for (anim, mut skills) in &mut sims {
        if let Some(skill) = skill_for_activity(*anim) {
            skills.add_xp(skill, SKILL_GAIN_RATE * game_minutes);
        }
    }
}

/// Registers the skill systems (live mode only).
pub struct SkillsPlugin;

impl Plugin for SkillsPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            Update,
            (ensure_skills, skill_gain_system).run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn levels_derive_from_xp_and_cap() {
        assert_eq!(level_for_xp(0.0), 0);
        assert_eq!(level_for_xp(99.0), 0);
        assert_eq!(level_for_xp(100.0), 1);
        assert_eq!(level_for_xp(550.0), 5);
        // Caps at MAX_SKILL even with excess XP.
        assert_eq!(level_for_xp(99_999.0), MAX_SKILL);
    }

    #[test]
    fn effectiveness_rises_with_level() {
        assert_eq!(effectiveness_multiplier(0), 1.0);
        assert_eq!(effectiveness_multiplier(10), 2.0);
        assert!(effectiveness_multiplier(5) > effectiveness_multiplier(2));
    }

    #[test]
    fn activities_and_careers_map_to_skills() {
        assert_eq!(
            skill_for_activity(AnimationState::Cooking),
            Some(SkillType::Cooking)
        );
        assert_eq!(skill_for_activity(AnimationState::Idle), None);
        assert_eq!(skill_for_career("Tech"), SkillType::Logic);
        assert_eq!(skill_for_career("Culinary"), SkillType::Cooking);
    }

    #[test]
    fn skills_accumulate_xp_into_levels() {
        let mut skills = Skills::default();
        assert_eq!(skills.level(SkillType::Cooking), 0);
        skills.add_xp(SkillType::Cooking, 250.0);
        assert_eq!(skills.level(SkillType::Cooking), 2);
        // Unrelated skills stay at zero.
        assert_eq!(skills.level(SkillType::Logic), 0);
    }
}
