use bevy::prelude::*;

use crate::core::state::GameState;

pub mod appearance;
pub mod autonomy;
pub mod control;
pub mod death;
pub mod desperation;
pub mod emote;
pub mod interaction;
pub mod movement;
pub mod needs;

pub struct SimPlugin;

impl Plugin for SimPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((
            autonomy::AutonomyPlugin,
            interaction::InteractionQueuePlugin,
            desperation::DesperationPlugin,
            death::DeathPlugin,
            control::SimControlPlugin,
            emote::MoodEmotePlugin,
        ))
        .init_resource::<SimManager>()
        .init_resource::<needs::NeedModifiers>()
        .insert_resource(TraitDatabase::default_populated())
        .register_type::<SimId>()
        .register_type::<SimName>()
        .register_type::<needs::Needs>()
        .register_type::<needs::NeedState>()
        .register_type::<moodlet::Moodlet>()
        .register_type::<moodlet::ActiveMoodlets>()
        .register_type::<moodlet::Mood>()
        .register_type::<SimAge>()
        .register_type::<SimGender>()
        .register_type::<SimTraits>()
        .register_type::<Trait>()
        .register_type::<TraitDatabase>()
        .register_type::<TraitInfo>()
        .register_type::<appearance::SimAppearance>()
        .register_type::<appearance::SimBody>()
        .register_type::<appearance::SimBodyPart>()
        .register_type::<appearance::BodyPart>()
        .register_type::<appearance::SimVoice>()
        .register_type::<movement::MoveTo>()
        .register_type::<movement::PathState>()
        .register_type::<AnimationState>()
        .init_resource::<SimConfig>()
        .add_systems(OnEnter(GameState::LiveMode), spawn_player_sim)
        .add_systems(Update, needs::decay_needs)
        .add_systems(Update, needs::update_need_moodlets)
        .add_systems(Update, moodlet::update_moodlets)
        .add_systems(Update, movement::move_to_system)
        .add_systems(Update, movement::path_follow_system)
        .add_systems(Update, animation_system);
    }
}

/// Timer data for procedural animation timing.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct AnimationTimer {
    pub elapsed: f32,
}

/// Simple procedural animation: bob walk cycle, idle sway, head look.
fn animation_system(
    mut sims: Query<(&Transform, &AnimationState, &SimAge, &Children)>,
    mut parts: Query<(&appearance::SimBodyPart, &mut Transform), Without<AnimationState>>,
    time: Res<Time>,
) {
    let idle_freq = 1.5;
    let walk_freq = 8.0;

    for (_sim_transform, animation, age, children) in &mut sims {
        let scale = age.height_scale();
        let is_moving = matches!(animation, AnimationState::Walking | AnimationState::Running);
        let is_running = matches!(animation, AnimationState::Running);

        let speed = if is_running { 1.5 } else { 1.0 };
        let freq = if is_moving { walk_freq } else { idle_freq };
        let t = time.elapsed_seconds() * freq * speed;
        let bob = if is_moving {
            (t.sin().abs() * 0.08 + 0.02) * scale
        } else {
            (t.sin() * 0.02 + 0.01) * scale
        };
        let sway = if is_moving {
            (t * 0.5).sin() * 0.06 * scale
        } else {
            (t * 0.25).sin() * 0.03 * scale
        };

        for child in children.iter() {
            if let Ok((part, mut transform)) = parts.get_mut(*child) {
                match part.part {
                    appearance::BodyPart::Head => {
                        let look = Quat::from_rotation_y(sway) * Quat::from_rotation_x(bob * 0.3);
                        transform.rotation = look;
                    }
                    appearance::BodyPart::LeftArm | appearance::BodyPart::RightArm => {
                        let sign = if part.part == appearance::BodyPart::LeftArm {
                            1.0
                        } else {
                            -1.0
                        };
                        let arm_swing = if is_moving {
                            t.sin() * 0.5 * sign
                        } else {
                            t.sin() * 0.05 * sign
                        };
                        transform.rotation = Quat::from_rotation_x(arm_swing);
                    }
                    appearance::BodyPart::LeftLeg | appearance::BodyPart::RightLeg => {
                        let sign = if part.part == appearance::BodyPart::LeftLeg {
                            1.0
                        } else {
                            -1.0
                        };
                        let leg_swing = if is_moving { t.sin() * 0.4 * sign } else { 0.0 };
                        transform.rotation = Quat::from_rotation_x(leg_swing);
                    }
                }
            }
        }
    }
}

#[derive(Resource, Default, Debug)]
pub struct SimManager {
    pub sims: Vec<Entity>,
    pub next_id: u64,
}

impl SimManager {
    pub fn next_id(&mut self) -> SimId {
        let id = self.next_id;
        self.next_id += 1;
        SimId(id)
    }
}

/// Unique identifier for a Sim.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect)]
#[reflect(Component)]
pub struct SimId(pub u64);

/// Display name of a Sim.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct SimName {
    pub first: String,
    pub last: String,
}

impl SimName {
    pub fn full_name(&self) -> String {
        format!("{} {}", self.first, self.last)
    }
}

#[derive(Bundle, Default, Debug, Clone)]
pub struct SimBundle {
    pub sim_id: SimId,
    pub name: SimName,
    pub age: SimAge,
    pub gender: SimGender,
    pub traits: SimTraits,
    pub appearance: appearance::SimAppearance,
    pub voice: appearance::SimVoice,
    pub needs: needs::Needs,
    pub need_state: needs::NeedState,
    pub moodlets: moodlet::ActiveMoodlets,
    pub animation: AnimationState,
}

#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub enum SimGender {
    #[default]
    Male,
    Female,
    Custom,
}

#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub enum SimAge {
    #[default]
    Baby,
    Toddler,
    Child,
    Teen,
    YoungAdult,
    Adult,
    Elder,
}

impl SimAge {
    /// Height multiplier relative to an adult Sim.
    pub fn height_scale(self) -> f32 {
        match self {
            SimAge::Baby => 0.25,
            SimAge::Toddler => 0.45,
            SimAge::Child => 0.65,
            SimAge::Teen => 0.9,
            SimAge::YoungAdult => 1.0,
            SimAge::Adult => 1.0,
            SimAge::Elder => 0.97,
        }
    }

    /// Base walk speed multiplier for this life stage.
    pub fn speed_multiplier(self) -> f32 {
        match self {
            SimAge::Baby => 0.0,
            SimAge::Toddler => 0.4,
            SimAge::Child => 0.7,
            SimAge::Teen => 1.0,
            SimAge::YoungAdult => 1.05,
            SimAge::Adult => 1.0,
            SimAge::Elder => 0.8,
        }
    }
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct SimTraits {
    pub traits: Vec<Trait>,
}

impl SimTraits {
    /// Check for conflicting traits in the current set.
    pub fn has_conflict(&self) -> bool {
        self.traits
            .iter()
            .any(|&t| TraitDatabase::has_conflict(&self.traits, t))
    }

    /// Add a trait if it is not already present and does not create a conflict.
    pub fn try_add(&mut self, trait_value: Trait) -> bool {
        if self.traits.contains(&trait_value) {
            return true;
        }
        if TraitDatabase::has_conflict(&self.traits, trait_value) {
            return false;
        }
        self.traits.push(trait_value);
        true
    }
}

#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub enum AnimationState {
    #[default]
    Idle,
    Walking,
    Running,
    Sitting,
    Sleeping,
    Talking,
    Eating,
    Cooking,
    Working,
    Playing,
    UsingObject,
    Socializing,
}

/// Personality traits that modify needs, autonomy, and social outcomes.
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect)]
#[reflect]
pub enum Trait {
    #[default]
    Active,
    Lazy,
    Cheerful,
    Gloomy,
    Creative,
    Genius,
    Neat,
    Slob,
    Outgoing,
    Introvert,
    Romantic,
    Unflirty,
    Ambitious,
    Good,
    Evil,
    SelfAssured,
    SelfDeprecating,
    Foodie,
    Glutton,
    HotHeaded,
    Calm,
    FamilyOriented,
    Loner,
    SocialButterfly,
}

impl Trait {
    /// Return the user-facing name of this trait.
    pub fn display_name(self) -> &'static str {
        match self {
            Trait::Active => "Active",
            Trait::Lazy => "Lazy",
            Trait::Cheerful => "Cheerful",
            Trait::Gloomy => "Gloomy",
            Trait::Creative => "Creative",
            Trait::Genius => "Genius",
            Trait::Neat => "Neat",
            Trait::Slob => "Slob",
            Trait::Outgoing => "Outgoing",
            Trait::Introvert => "Introvert",
            Trait::Romantic => "Romantic",
            Trait::Unflirty => "Unflirty",
            Trait::Ambitious => "Ambitious",
            Trait::Good => "Good",
            Trait::Evil => "Evil",
            Trait::SelfAssured => "Self-Assured",
            Trait::SelfDeprecating => "Self-Deprecating",
            Trait::Foodie => "Foodie",
            Trait::Glutton => "Glutton",
            Trait::HotHeaded => "Hot-Headed",
            Trait::Calm => "Calm",
            Trait::FamilyOriented => "Family-Oriented",
            Trait::Loner => "Loner",
            Trait::SocialButterfly => "Social Butterfly",
        }
    }

    /// Return a short description of how this trait affects gameplay.
    pub fn description(self) -> &'static str {
        match self {
            Trait::Active => "Slower energy decay; prefers active interactions.",
            Trait::Lazy => "Faster energy decay; prefers sitting and relaxing.",
            Trait::Cheerful => "More likely to become Happy; fun decays a bit faster.",
            Trait::Gloomy => "More likely to become Sad; fun decays slower.",
            Trait::Creative => "Gains creativity skill faster; enjoys art and music.",
            Trait::Genius => "Gains logic skill faster; enjoys logic puzzles.",
            Trait::Neat => "Hygiene decays faster; autonomously cleans.",
            Trait::Slob => "Hygiene decays slower; doesn't mind mess.",
            Trait::Outgoing => "Social decays faster; thrives on company.",
            Trait::Introvert => "Social decays slower; prefers solitude.",
            Trait::Romantic => "Social and romantic interactions are more effective.",
            Trait::Unflirty => "Romantic interactions are less effective.",
            Trait::Ambitious => "Better job performance; wants promotions.",
            Trait::Good => "Friendly interactions are more effective; avoids mean.",
            Trait::Evil => "Mean interactions are more effective; enjoys mischief.",
            Trait::SelfAssured => "Confident moodlets last longer.",
            Trait::SelfDeprecating => "Embarrassed moodlets last longer.",
            Trait::Foodie => "Hunger decays faster; better meal quality.",
            Trait::Glutton => "Hunger and bladder decay faster.",
            Trait::HotHeaded => "Angry moodlets appear more often.",
            Trait::Calm => "Angry moodlets appear less often.",
            Trait::FamilyOriented => "Family interactions give bigger mood boosts.",
            Trait::Loner => "Social decays slower; prefers being alone.",
            Trait::SocialButterfly => "Social decays much faster; loves crowds.",
        }
    }

    /// Return the trait that conflicts with this one, if any.
    pub fn conflict(self) -> Option<Trait> {
        match self {
            Trait::Active => Some(Trait::Lazy),
            Trait::Lazy => Some(Trait::Active),
            Trait::Neat => Some(Trait::Slob),
            Trait::Slob => Some(Trait::Neat),
            Trait::Outgoing => Some(Trait::Loner),
            Trait::Loner => Some(Trait::Outgoing),
            Trait::Romantic => Some(Trait::Unflirty),
            Trait::Unflirty => Some(Trait::Romantic),
            Trait::Good => Some(Trait::Evil),
            Trait::Evil => Some(Trait::Good),
            Trait::HotHeaded => Some(Trait::Calm),
            Trait::Calm => Some(Trait::HotHeaded),
            _ => None,
        }
    }
}

/// Static database of trait metadata available at runtime.
#[derive(Resource, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct TraitDatabase {
    pub traits: Vec<TraitInfo>,
}

/// Metadata describing a selectable trait.
#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct TraitInfo {
    pub trait_value: Trait,
    pub display_name: String,
    pub description: String,
    pub conflicts_with: Vec<Trait>,
}

impl TraitDatabase {
    /// Build the default trait database from all enum variants.
    pub fn default_populated() -> Self {
        let traits = [
            Trait::Active,
            Trait::Lazy,
            Trait::Cheerful,
            Trait::Gloomy,
            Trait::Creative,
            Trait::Genius,
            Trait::Neat,
            Trait::Slob,
            Trait::Outgoing,
            Trait::Introvert,
            Trait::Romantic,
            Trait::Unflirty,
            Trait::Ambitious,
            Trait::Good,
            Trait::Evil,
            Trait::SelfAssured,
            Trait::SelfDeprecating,
            Trait::Foodie,
            Trait::Glutton,
            Trait::HotHeaded,
            Trait::Calm,
            Trait::FamilyOriented,
            Trait::Loner,
            Trait::SocialButterfly,
        ];

        Self {
            traits: traits
                .iter()
                .map(|&t| TraitInfo {
                    trait_value: t,
                    display_name: t.display_name().to_string(),
                    description: t.description().to_string(),
                    conflicts_with: t.conflict().into_iter().collect(),
                })
                .collect(),
        }
    }

    /// Check whether a candidate trait conflicts with an existing trait set.
    pub fn has_conflict(traits: &[Trait], candidate: Trait) -> bool {
        if let Some(conflict) = candidate.conflict()
            && traits.contains(&conflict)
        {
            return true;
        }
        traits.iter().any(|t| t.conflict() == Some(candidate))
    }
}

pub mod moodlet {
    use bevy::prelude::*;

    /// Long-term emotional state derived from active moodlets.
    #[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect)]
    #[reflect(Component)]
    pub enum Mood {
        #[default]
        Happy,
        Fine,
        Tense,
        Sad,
        Angry,
        Embarrassed,
        Energized,
        Flirty,
        Focused,
        Uncomfortable,
    }

    /// A temporary emotional modifier applied to a Sim.
    #[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
    #[reflect(Component)]
    pub struct Moodlet {
        pub name: String,
        pub description: String,
        pub mood: Mood,
        pub impact: i32,
        pub duration_seconds: f32,
        pub source: String,
    }

    impl Moodlet {
        pub fn new(
            name: &str,
            description: &str,
            mood: Mood,
            impact: i32,
            duration: f32,
            source: &str,
        ) -> Self {
            Self {
                name: name.to_string(),
                description: description.to_string(),
                mood,
                impact,
                duration_seconds: duration,
                source: source.to_string(),
            }
        }
    }

    /// Collection of active moodlets on a Sim.
    #[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
    #[reflect(Component)]
    pub struct ActiveMoodlets {
        pub moodlets: Vec<Moodlet>,
    }

    impl ActiveMoodlets {
        /// Calculate the dominant mood from active moodlet totals.
        pub fn dominant_mood(&self) -> Mood {
            let mut scores: std::collections::HashMap<Mood, i32> = std::collections::HashMap::new();
            for moodlet in &self.moodlets {
                *scores.entry(moodlet.mood).or_insert(0) += moodlet.impact;
            }
            scores
                .into_iter()
                .max_by_key(|(_, score)| *score)
                .map(|(mood, _)| mood)
                .unwrap_or(Mood::Fine)
        }

        /// Add a moodlet, replacing an existing one with the same name if present.
        pub fn add(&mut self, moodlet: Moodlet) {
            if let Some(existing) = self.moodlets.iter_mut().find(|m| m.name == moodlet.name) {
                *existing = moodlet;
            } else {
                self.moodlets.push(moodlet);
            }
        }

        /// Remove moodlets whose duration has expired.
        pub fn expire(&mut self, delta_seconds: f32) {
            for moodlet in &mut self.moodlets {
                moodlet.duration_seconds -= delta_seconds;
            }
            self.moodlets.retain(|m| m.duration_seconds > 0.0);
        }
    }

    pub fn update_moodlets(mut query: Query<&mut ActiveMoodlets>, time: Res<Time>) {
        for mut active in &mut query {
            active.expire(time.delta_seconds());
        }
    }
}

/// The player's chosen sim, configured in Create-A-Sim and spawned on the lot
/// when entering Live mode.
#[derive(Resource, Clone, Debug)]
pub struct SimConfig {
    pub first: String,
    pub last: String,
    pub gender: SimGender,
    pub age: SimAge,
    pub traits: Vec<Trait>,
    /// Create-A-Sim appearance preset indices (into the appearance palettes).
    pub skin: usize,
    pub hair_color: usize,
    pub hair_style: usize,
    pub shirt: usize,
    /// Voice pitch preset index (see Create-A-Sim `voice_presets`).
    pub voice: usize,
}

impl SimConfig {
    /// Build the chosen sim's appearance from its preset indices.
    pub fn appearance(&self) -> appearance::SimAppearance {
        appearance::appearance_from_indices(self.skin, self.hair_color, self.hair_style, self.shirt)
    }
}

impl Default for SimConfig {
    fn default() -> Self {
        Self {
            first: "Alex".to_string(),
            last: "Sample".to_string(),
            gender: SimGender::Custom,
            age: SimAge::YoungAdult,
            traits: vec![Trait::Cheerful, Trait::Outgoing],
            skin: 1,
            hair_color: 1,
            hair_style: 0,
            shirt: 0,
            voice: 1,
        }
    }
}

/// Spawn the player's single configured sim on the lot (once) when Live mode
/// begins. Guarded so re-entering Live mode (e.g. from Build mode) is a no-op.
fn spawn_player_sim(
    mut commands: Commands,
    config: Res<SimConfig>,
    mut sim_manager: ResMut<SimManager>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    if !sim_manager.sims.is_empty() {
        return;
    }
    let skin_texture: Handle<Image> = asset_server.load("textures/sim_skin_tone.png");
    spawn_one_sim(
        &mut commands,
        &mut sim_manager,
        &mut meshes,
        &mut materials,
        skin_texture,
        (config.first.as_str(), config.last.as_str()),
        config.gender,
        config.age,
        crate::ui::create_a_sim::voice_pitch(config.voice),
        &config.traits,
        config.appearance(),
        Vec3::new(0.0, 0.0, 2.0),
        needs::Needs {
            hunger: 70.0,
            energy: 65.0,
            social: 60.0,
            fun: 60.0,
            hygiene: 70.0,
            bladder: 70.0,
        },
    );
}

/// Spawn a single demo sim with the given identity, traits, position and needs.
#[allow(clippy::too_many_arguments)]
fn spawn_one_sim(
    commands: &mut Commands,
    sim_manager: &mut SimManager,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    skin_texture: Handle<Image>,
    (first, last): (&str, &str),
    gender: SimGender,
    age: SimAge,
    voice_pitch: f32,
    sim_traits: &[Trait],
    appearance: appearance::SimAppearance,
    position: Vec3,
    sim_needs: needs::Needs,
) {
    let sim_id = sim_manager.next_id();
    let name = SimName {
        first: first.to_string(),
        last: last.to_string(),
    };

    let mut traits = SimTraits::default();
    for &t in sim_traits {
        traits.try_add(t);
    }

    let entity = commands
        .spawn((
            SimBundle {
                sim_id,
                name: name.clone(),
                age,
                gender,
                traits,
                appearance: appearance.clone(),
                voice: appearance::SimVoice {
                    pitch: voice_pitch,
                    ..appearance::SimVoice::default()
                },
                needs: sim_needs,
                need_state: needs::NeedState::default(),
                moodlets: moodlet::ActiveMoodlets::default(),
                animation: AnimationState::Idle,
            },
            appearance::SimBody,
            // SpatialBundle so the sim's body-part mesh children render (B0004).
            SpatialBundle::from_transform(Transform::from_translation(position)),
            interaction::InteractionQueue::default(),
        ))
        .with_children(|parent| {
            appearance::build_sim_body(parent, meshes, materials, &appearance, skin_texture);
        })
        .id();

    sim_manager.sims.push(entity);
}

/// Generate a random Sim name for placeholder content.
pub fn random_sim_name() -> SimName {
    let first_names = [
        "Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Quinn", "Avery",
    ];
    let last_names = [
        "Smith", "Johnson", "Lee", "Garcia", "Brown", "Davis", "Miller", "Wilson",
    ];
    SimName {
        first: first_names[first_names.len() / 2].to_string(),
        last: last_names[last_names.len() / 2].to_string(),
    }
}
