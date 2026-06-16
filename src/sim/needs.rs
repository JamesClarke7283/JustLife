use bevy::prelude::*;

use super::{SimTraits, Trait, moodlet};
use crate::core::resources::{GameConfig, GameSpeed};

/// Per-Sim state controlling need decay pauses and modifiers.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct NeedState {
    /// If true, all need decay is paused (e.g. during sleep).
    pub paused: bool,
    /// Additional multiplier applied to all decay rates.
    pub decay_multiplier: f32,
}

impl NeedState {
    pub const fn new() -> Self {
        Self {
            paused: false,
            decay_multiplier: 1.0,
        }
    }
}

/// The six core needs of a Sim.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Needs {
    pub hunger: f32,
    pub energy: f32,
    pub social: f32,
    pub fun: f32,
    pub hygiene: f32,
    pub bladder: f32,
}

impl Needs {
    pub const fn new() -> Self {
        Self {
            hunger: 100.0,
            energy: 100.0,
            social: 100.0,
            fun: 100.0,
            hygiene: 100.0,
            bladder: 100.0,
        }
    }

    /// Clamp all needs to the 0-100 range.
    pub fn clamp(&mut self) {
        self.hunger = self.hunger.clamp(0.0, 100.0);
        self.energy = self.energy.clamp(0.0, 100.0);
        self.social = self.social.clamp(0.0, 100.0);
        self.fun = self.fun.clamp(0.0, 100.0);
        self.hygiene = self.hygiene.clamp(0.0, 100.0);
        self.bladder = self.bladder.clamp(0.0, 100.0);
    }

    /// Check whether any need is below the critical threshold.
    pub fn has_critical(&self) -> bool {
        self.hunger < 25.0
            || self.energy < 25.0
            || self.social < 25.0
            || self.fun < 25.0
            || self.hygiene < 25.0
            || self.bladder < 25.0
    }

    /// Get a need value by its type.
    pub fn get(&self, need: NeedType) -> f32 {
        match need {
            NeedType::Hunger => self.hunger,
            NeedType::Energy => self.energy,
            NeedType::Social => self.social,
            NeedType::Fun => self.fun,
            NeedType::Hygiene => self.hygiene,
            NeedType::Bladder => self.bladder,
        }
    }

    /// Modify a need value by its type, then clamp to [0, 100].
    pub fn modify(&mut self, need: NeedType, delta: f32) {
        match need {
            NeedType::Hunger => self.hunger += delta,
            NeedType::Energy => self.energy += delta,
            NeedType::Social => self.social += delta,
            NeedType::Fun => self.fun += delta,
            NeedType::Hygiene => self.hygiene += delta,
            NeedType::Bladder => self.bladder += delta,
        }
        self.clamp();
    }
}

/// Core need type used to identify which need changed or is affected.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect, serde::Serialize, serde::Deserialize,
)]
#[reflect]
pub enum NeedType {
    Hunger,
    Energy,
    Social,
    Fun,
    Hygiene,
    Bladder,
}

/// Global per-trait need decay modifiers.
#[derive(Resource, Debug, Clone, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct NeedModifiers {
    pub hunger: TraitModifiers,
    pub energy: TraitModifiers,
    pub social: TraitModifiers,
    pub fun: TraitModifiers,
    pub hygiene: TraitModifiers,
    pub bladder: TraitModifiers,
}

impl NeedModifiers {
    pub fn new() -> Self {
        Self::default()
    }
}

#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct TraitModifiers {
    pub active: f32,
    pub lazy: f32,
    pub cheerful: f32,
    pub gloomy: f32,
    pub creative: f32,
    pub genius: f32,
    pub neat: f32,
    pub slob: f32,
    pub outgoing: f32,
    pub introvert: f32,
    pub romantic: f32,
    pub unflirty: f32,
    pub ambitious: f32,
    pub good: f32,
    pub evil: f32,
    pub self_assured: f32,
    pub self_deprecating: f32,
    pub foodie: f32,
    pub glutton: f32,
    pub hot_headed: f32,
    pub calm: f32,
    pub family_oriented: f32,
    pub loner: f32,
    pub social_butterfly: f32,
}

impl TraitModifiers {
    pub fn get(&self, trait_value: Trait) -> f32 {
        match trait_value {
            Trait::Active => self.active,
            Trait::Lazy => self.lazy,
            Trait::Cheerful => self.cheerful,
            Trait::Gloomy => self.gloomy,
            Trait::Creative => self.creative,
            Trait::Genius => self.genius,
            Trait::Neat => self.neat,
            Trait::Slob => self.slob,
            Trait::Outgoing => self.outgoing,
            Trait::Introvert => self.introvert,
            Trait::Romantic => self.romantic,
            Trait::Unflirty => self.unflirty,
            Trait::Ambitious => self.ambitious,
            Trait::Good => self.good,
            Trait::Evil => self.evil,
            Trait::SelfAssured => self.self_assured,
            Trait::SelfDeprecating => self.self_deprecating,
            Trait::Foodie => self.foodie,
            Trait::Glutton => self.glutton,
            Trait::HotHeaded => self.hot_headed,
            Trait::Calm => self.calm,
            Trait::FamilyOriented => self.family_oriented,
            Trait::Loner => self.loner,
            Trait::SocialButterfly => self.social_butterfly,
        }
    }
}

impl Default for NeedModifiers {
    fn default() -> Self {
        Self {
            hunger: TraitModifiers {
                glutton: 1.3,
                foodie: 1.1,
                ..default()
            },
            energy: TraitModifiers {
                active: 0.85,
                lazy: 1.15,
                ..default()
            },
            social: TraitModifiers {
                outgoing: 1.2,
                loner: 0.8,
                social_butterfly: 1.3,
                ..default()
            },
            fun: TraitModifiers {
                gloomy: 0.9,
                cheerful: 1.1,
                ..default()
            },
            hygiene: TraitModifiers {
                neat: 1.1,
                slob: 0.85,
                ..default()
            },
            bladder: TraitModifiers {
                glutton: 1.1,
                ..default()
            },
        }
    }
}

/// Compute the combined decay multiplier for a Sim's needs.
fn trait_decay_multiplier(traits: &[Trait], modifiers: &NeedModifiers) -> [f32; 6] {
    let mut multipliers = [1.0f32; 6];
    for trait_value in traits {
        multipliers[0] *= modifiers.hunger.get(*trait_value);
        multipliers[1] *= modifiers.energy.get(*trait_value);
        multipliers[2] *= modifiers.social.get(*trait_value);
        multipliers[3] *= modifiers.fun.get(*trait_value);
        multipliers[4] *= modifiers.hygiene.get(*trait_value);
        multipliers[5] *= modifiers.bladder.get(*trait_value);
    }
    multipliers
}

/// Fired when a need crosses a threshold that should trigger autonomy or UI feedback.
#[derive(Event, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect]
pub struct NeedThresholdEvent {
    pub entity: Entity,
    pub need: NeedType,
    pub value: f32,
}

pub fn decay_needs(
    mut sims: Query<(
        Entity,
        &mut Needs,
        &SimTraits,
        &NeedState,
        Option<&super::AnimationState>,
    )>,
    game_config: Res<GameConfig>,
    game_speed: Res<GameSpeed>,
    modifiers: Res<NeedModifiers>,
    time: Res<Time>,
    mut threshold_writer: EventWriter<NeedThresholdEvent>,
) {
    if game_speed.is_paused() {
        return;
    }

    let speed = game_speed.multiplier();
    let real_dt = time.delta_seconds();
    // Convert real seconds to in-game minutes based on configured scale.
    let game_minutes = real_dt * speed / game_config.real_seconds_per_game_minute;
    let rates = game_config.need_decay_rates;
    let trait_multipliers = |traits: &[Trait]| trait_decay_multiplier(traits, &modifiers);

    for (entity, mut needs, traits, state, animation) in &mut sims {
        if state.paused {
            continue;
        }

        let previous = *needs;
        let muls = trait_multipliers(&traits.traits);
        let need_animation_slow = if animation == Some(&super::AnimationState::Sleeping) {
            0.5
        } else {
            1.0
        };

        let decay = |base: f32, rate: f32, mul: f32| -> f32 {
            let total_mul = mul * state.decay_multiplier * need_animation_slow;
            base - rate * game_minutes * total_mul
        };

        needs.hunger = decay(needs.hunger, rates.hunger, muls[0]);
        needs.energy = decay(needs.energy, rates.energy, muls[1]);
        needs.social = decay(needs.social, rates.social, muls[2]);
        needs.fun = decay(needs.fun, rates.fun, muls[3]);
        needs.hygiene = decay(needs.hygiene, rates.hygiene, muls[4]);
        needs.bladder = decay(needs.bladder, rates.bladder, muls[5]);

        needs.clamp();
        emit_threshold_crossings(entity, &previous, &needs, &mut threshold_writer);
    }
}

/// Emit a threshold event when a need drops below 25% for the first time.
fn emit_threshold_crossings(
    entity: Entity,
    previous: &Needs,
    current: &Needs,
    writer: &mut EventWriter<NeedThresholdEvent>,
) {
    let threshold = 25.0;
    let pairs = [
        (NeedType::Hunger, previous.hunger, current.hunger),
        (NeedType::Energy, previous.energy, current.energy),
        (NeedType::Social, previous.social, current.social),
        (NeedType::Fun, previous.fun, current.fun),
        (NeedType::Hygiene, previous.hygiene, current.hygiene),
        (NeedType::Bladder, previous.bladder, current.bladder),
    ];

    for (need, prev, curr) in pairs {
        if prev >= threshold && curr < threshold {
            writer.send(NeedThresholdEvent {
                entity,
                need,
                value: curr,
            });
        }
    }
}

impl GameSpeed {
    fn is_paused(&self) -> bool {
        matches!(self, GameSpeed::Pause)
    }
}

/// Add/remove critical-need moodlets based on current needs.
pub fn update_need_moodlets(
    mut sims: Query<(Entity, &Needs, &mut moodlet::ActiveMoodlets)>,
    mut added: Local<std::collections::HashSet<(Entity, NeedType)>>,
) {
    added.retain(|(entity, _)| sims.get(*entity).is_ok());

    for (entity, needs, mut moodlets) in &mut sims {
        let critical_needs = [
            (
                NeedType::Hunger,
                needs.hunger,
                "Ravenous",
                "Hunger is critically low.",
                moodlet::Mood::Uncomfortable,
            ),
            (
                NeedType::Energy,
                needs.energy,
                "Exhausted",
                "Energy is critically low.",
                moodlet::Mood::Tense,
            ),
            (
                NeedType::Social,
                needs.social,
                "Lonely",
                "Social need is critically low.",
                moodlet::Mood::Sad,
            ),
            (
                NeedType::Fun,
                needs.fun,
                "Bored",
                "Fun need is critically low.",
                moodlet::Mood::Tense,
            ),
            (
                NeedType::Hygiene,
                needs.hygiene,
                "Filthy",
                "Hygiene is critically low.",
                moodlet::Mood::Uncomfortable,
            ),
            (
                NeedType::Bladder,
                needs.bladder,
                "Desperate",
                "Bladder is critically low.",
                moodlet::Mood::Uncomfortable,
            ),
        ];

        for (need, value, name, description, mood) in critical_needs {
            let key = (entity, need);
            if value < 25.0 {
                if !added.contains(&key) {
                    moodlets.add(moodlet::Moodlet::new(
                        name,
                        description,
                        mood,
                        -10,
                        f32::MAX,
                        "need_threshold",
                    ));
                    added.insert(key);
                }
            } else {
                moodlets.moodlets.retain(|m| m.name != name);
                added.remove(&key);
            }
        }
    }
}
