//! Freelance / odd jobs (Phase 9.7).
//!
//! Sims can pick up gig work (conceptually from a phone or computer). Each gig
//! has a kind, a pay-out, a relevant skill, and a chunk of work; finishing one
//! banks the pay and grants skill XP. Some gigs are recurring so they return to
//! the board. A `G` shortcut hands the next gig to a free sim for testing until
//! the phone/computer interaction lands.

use bevy::prelude::*;

use crate::career::work::AtWork;
use crate::career::{SkillType, Skills};
use crate::core::resources::{GameConfig, GameSpeed, MoneyResource};
use crate::core::state::GameState;
use crate::sim::SimId;

/// A category of freelance gig.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GigKind {
    Programming,
    Painting,
    Writing,
    Repair,
    Delivery,
}

impl GigKind {
    /// The skill this gig trains and is gated by.
    pub fn skill(self) -> SkillType {
        match self {
            GigKind::Programming => SkillType::Logic,
            GigKind::Painting => SkillType::Creativity,
            GigKind::Writing => SkillType::Charisma,
            GigKind::Repair => SkillType::Handiness,
            GigKind::Delivery => SkillType::Fitness,
        }
    }

    /// Display label.
    pub fn label(self) -> &'static str {
        match self {
            GigKind::Programming => "Programming",
            GigKind::Painting => "Painting",
            GigKind::Writing => "Writing",
            GigKind::Repair => "Repair",
            GigKind::Delivery => "Delivery",
        }
    }
}

/// A freelance gig: pay, the work it takes, its skill reward, and whether it
/// returns to the board after completion.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Gig {
    pub kind: GigKind,
    pub pay: i64,
    /// In-game minutes of work to finish the gig.
    pub work_minutes: f32,
    /// Skill XP granted on completion.
    pub xp: f32,
    /// Whether the gig reappears on the board after being completed.
    pub recurring: bool,
}

impl Gig {
    /// The skill trained by completing this gig.
    pub fn skill(&self) -> SkillType {
        self.kind.skill()
    }
}

/// The starter set of available gigs.
pub fn gig_catalog() -> Vec<Gig> {
    vec![
        Gig {
            kind: GigKind::Programming,
            pay: 220,
            work_minutes: 240.0,
            xp: 120.0,
            recurring: true,
        },
        Gig {
            kind: GigKind::Painting,
            pay: 160,
            work_minutes: 180.0,
            xp: 90.0,
            recurring: false,
        },
        Gig {
            kind: GigKind::Writing,
            pay: 140,
            work_minutes: 200.0,
            xp: 80.0,
            recurring: true,
        },
        Gig {
            kind: GigKind::Repair,
            pay: 110,
            work_minutes: 120.0,
            xp: 60.0,
            recurring: true,
        },
        Gig {
            kind: GigKind::Delivery,
            pay: 80,
            work_minutes: 90.0,
            xp: 40.0,
            recurring: false,
        },
    ]
}

/// The pickable gigs, cycled out as sims take them.
#[derive(Resource)]
pub struct GigBoard {
    pub available: Vec<Gig>,
    next: usize,
}

impl Default for GigBoard {
    fn default() -> Self {
        Self {
            available: gig_catalog(),
            next: 0,
        }
    }
}

impl GigBoard {
    /// Hand out the next gig in round-robin order.
    pub fn next_gig(&mut self) -> Option<Gig> {
        if self.available.is_empty() {
            return None;
        }
        let gig = self.available[self.next % self.available.len()];
        self.next = self.next.wrapping_add(1);
        Some(gig)
    }
}

/// A gig a sim is currently working on.
#[derive(Component, Debug, Clone, Copy, PartialEq)]
pub struct ActiveGig {
    pub gig: Gig,
    /// In-game minutes worked so far.
    pub elapsed: f32,
}

/// Press G to hand the next gig to a free (not working) sim.
#[allow(clippy::type_complexity)]
fn assign_gig_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut board: ResMut<GigBoard>,
    mut commands: Commands,
    free_sims: Query<Entity, (With<SimId>, Without<ActiveGig>, Without<AtWork>)>,
) {
    if !keyboard.just_pressed(KeyCode::KeyG) {
        return;
    }
    let Some(entity) = free_sims.iter().next() else {
        return;
    };
    if let Some(gig) = board.next_gig() {
        info!("{} gig picked up (pays {})", gig.kind.label(), gig.pay);
        commands
            .entity(entity)
            .insert(ActiveGig { gig, elapsed: 0.0 });
    }
}

/// Advance active gigs; on completion bank the pay and grant skill XP.
fn gig_progress_system(
    game_config: Res<GameConfig>,
    game_speed: Res<GameSpeed>,
    time: Res<Time>,
    mut money: ResMut<MoneyResource>,
    mut board: ResMut<GigBoard>,
    mut commands: Commands,
    mut sims: Query<(Entity, &mut ActiveGig, Option<&mut Skills>)>,
) {
    let speed = game_speed.multiplier();
    if speed == 0.0 {
        return;
    }
    let game_minutes = time.delta_seconds() * speed / game_config.real_seconds_per_game_minute;

    for (entity, mut active, skills) in &mut sims {
        active.elapsed += game_minutes;
        if active.elapsed >= active.gig.work_minutes {
            money.deposit(active.gig.pay);
            if let Some(mut skills) = skills {
                skills.add_xp(active.gig.skill(), active.gig.xp);
            }
            if active.gig.recurring {
                board.available.push(active.gig);
            }
            commands.entity(entity).remove::<ActiveGig>();
        }
    }
}

/// Registers the freelance gig systems and board (live mode only).
pub struct GigPlugin;

impl Plugin for GigPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<GigBoard>().add_systems(
            Update,
            (assign_gig_input, gig_progress_system).run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_covers_all_gig_kinds() {
        let catalog = gig_catalog();
        for kind in [
            GigKind::Programming,
            GigKind::Painting,
            GigKind::Writing,
            GigKind::Repair,
            GigKind::Delivery,
        ] {
            assert!(catalog.iter().any(|g| g.kind == kind), "missing {kind:?}");
        }
    }

    #[test]
    fn gigs_map_to_their_skill() {
        assert_eq!(GigKind::Programming.skill(), SkillType::Logic);
        assert_eq!(GigKind::Repair.skill(), SkillType::Handiness);
        assert_eq!(GigKind::Delivery.skill(), SkillType::Fitness);
    }

    #[test]
    fn board_hands_out_gigs_round_robin() {
        let mut board = GigBoard::default();
        let n = board.available.len();
        let first = board.next_gig().unwrap();
        // Cycling through the whole board returns to the first gig.
        for _ in 1..n {
            board.next_gig();
        }
        assert_eq!(board.next_gig().unwrap(), first);
    }

    #[test]
    fn gig_rewards_are_positive() {
        for gig in gig_catalog() {
            assert!(gig.pay > 0);
            assert!(gig.xp > 0.0);
            assert!(gig.work_minutes > 0.0);
        }
    }
}
