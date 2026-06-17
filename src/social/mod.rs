use bevy::prelude::*;

pub mod catalog;

pub struct SocialPlugin;

impl Plugin for SocialPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<Relationships>()
            .register_type::<RelationshipData>()
            .register_type::<Sentiments>()
            .register_type::<Conversation>();
    }
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Relationships {
    pub relationships: bevy::utils::HashMap<Entity, RelationshipData>,
}

#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct RelationshipData {
    pub friendship_score: f32,
    pub romance_score: f32,
    pub sentiment: RelationshipSentiment,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum RelationshipSentiment {
    #[default]
    Stranger,
    Acquaintance,
    Friend,
    GoodFriend,
    BestFriend,
    RomanticInterest,
    Partner,
    Spouse,
    Enemy,
    Nemesis,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Sentiments {
    pub sentiments: Vec<Sentiment>,
}

#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct Sentiment {
    pub name: String,
    pub strength: f32,
    pub source: Option<Entity>,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Conversation {
    pub participants: Vec<Entity>,
    pub context: ConversationContext,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum ConversationContext {
    #[default]
    Friendly,
    Romantic,
    Tense,
    Funny,
    Mean,
}
