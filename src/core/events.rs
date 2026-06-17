use bevy::prelude::*;

/// Fired when a sim's need level changes significantly.
#[derive(Event, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect]
pub struct NeedChangeEvent {
    pub entity: Entity,
    pub need: NeedType,
    pub value: f32,
    pub previous_value: f32,
}

/// Which core need changed.
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum NeedType {
    #[default]
    Hunger,
    Energy,
    Social,
    Fun,
    Hygiene,
    Bladder,
}

/// Fired when a sim starts or completes an interaction.
#[derive(Event, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct InteractionEvent {
    pub entity: Entity,
    pub interaction: String,
    pub phase: InteractionPhase,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum InteractionPhase {
    #[default]
    Started,
    Completed,
    Cancelled,
}

/// Fired each game-time tick for periodic updates.
#[derive(Event, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub struct TimeTickEvent {
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
}

/// Fired on social interaction (conversation, romance, conflict).
#[derive(Event, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect]
pub struct SocialEvent {
    pub source: Entity,
    pub target: Entity,
    pub interaction: SocialInteraction,
    pub outcome: SocialOutcome,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum SocialInteraction {
    #[default]
    Chat,
    Joke,
    Compliment,
    Hug,
    Flirt,
    Insult,
    Fight,
    Console,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum SocialOutcome {
    #[default]
    Positive,
    Neutral,
    Negative,
}

/// Fired on promotion, demotion, firing, or hiring.
#[derive(Event, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct CareerEvent {
    pub entity: Entity,
    pub change: CareerChange,
    pub career_name: String,
    pub level: u8,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum CareerChange {
    #[default]
    Promotion,
    Demotion,
    Fired,
    Hired,
    Quit,
}

/// Fired when objects are placed, moved, or deleted in build/buy mode.
#[derive(Event, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct BuildModeEvent {
    pub action: BuildAction,
    pub entity: Option<Entity>,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum BuildAction {
    #[default]
    WallPlaced,
    WallDeleted,
    ObjectPlaced,
    ObjectMoved,
    ObjectDeleted,
    RoomCreated,
    RoomDeleted,
    MaterialChanged,
}

/// Fired when a new sim is created.
#[derive(Event, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect]
pub struct SimSpawnEvent {
    pub entity: Entity,
    pub household_id: u32,
}

/// Fired when a sim dies.
#[derive(Event, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect]
pub struct SimDeathEvent {
    pub entity: Entity,
    pub cause: DeathCause,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum DeathCause {
    #[default]
    Starvation,
    OldAge,
    Fire,
    Drowning,
    Electrocution,
    EmotionalExtreme,
}

/// A transient toast notification shown top-right (Phase 10.7). Any system can
/// emit one; the UI renders and auto-dismisses them.
#[derive(Event, Debug, Clone)]
pub struct ToastEvent {
    pub message: String,
    pub kind: ToastKind,
}

impl ToastEvent {
    pub fn info(message: impl Into<String>) -> Self {
        Self::new(message, ToastKind::Info)
    }
    pub fn success(message: impl Into<String>) -> Self {
        Self::new(message, ToastKind::Success)
    }
    pub fn warning(message: impl Into<String>) -> Self {
        Self::new(message, ToastKind::Warning)
    }
    pub fn error(message: impl Into<String>) -> Self {
        Self::new(message, ToastKind::Error)
    }
    fn new(message: impl Into<String>, kind: ToastKind) -> Self {
        Self {
            message: message.into(),
            kind,
        }
    }
}

/// Severity/colour of a toast.
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToastKind {
    #[default]
    Info,
    Success,
    Warning,
    Error,
}
