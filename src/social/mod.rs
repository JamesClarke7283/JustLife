use bevy::prelude::*;

pub mod catalog;
pub mod conversation;

pub struct SocialPlugin;

impl Plugin for SocialPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(conversation::ConversationPlugin)
            .register_type::<Relationships>()
            .register_type::<RelationshipData>()
            .register_type::<Sentiments>()
            .register_type::<Conversation>();
    }
}

/// A sim's outgoing relationships, keyed by the *other* sim's entity.
///
/// Relationships are directional: A's view of B lives in A's `Relationships`
/// component and B's view of A in B's, so the two are tracked independently.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Relationships {
    pub relationships: bevy::utils::HashMap<Entity, RelationshipData>,
}

impl Relationships {
    /// Mutable access to the relationship with `target`, creating a default
    /// (Stranger) entry if none exists yet.
    pub fn entry_mut(&mut self, target: Entity) -> &mut RelationshipData {
        self.relationships.entry(target).or_default()
    }

    /// Read the relationship with `target`, if one has formed.
    pub fn get(&self, target: Entity) -> Option<&RelationshipData> {
        self.relationships.get(&target)
    }

    /// Apply friendship/romance deltas toward `target` and refresh its level.
    pub fn record(&mut self, target: Entity, friendship: f32, romance: f32) {
        self.entry_mut(target).apply(friendship, romance);
    }

    /// Remember a trait discovered about `target` (deduplicated).
    pub fn note_trait(&mut self, target: Entity, known: crate::sim::Trait) {
        let rel = self.entry_mut(target);
        if !rel.known_traits.contains(&known) {
            rel.known_traits.push(known);
        }
    }
}

/// Directional relationship state between one sim and another.
#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct RelationshipData {
    /// Friendship from -100 (Nemesis) through 0 (Stranger) to 100 (Best Friend).
    pub friendship_score: f32,
    /// Romance from 0 to 100.
    pub romance_score: f32,
    /// Traits this sim has learned about the other.
    pub known_traits: Vec<crate::sim::Trait>,
    /// Cached relationship level, derived from the scores.
    pub sentiment: RelationshipSentiment,
}

impl RelationshipData {
    /// Apply score deltas (clamped to range) and recompute the cached level.
    pub fn apply(&mut self, friendship: f32, romance: f32) {
        self.friendship_score = (self.friendship_score + friendship).clamp(-100.0, 100.0);
        self.romance_score = (self.romance_score + romance).clamp(0.0, 100.0);
        self.sentiment = relationship_level(self);
    }
}

/// Derive the relationship level from the friendship/romance scores. Romance
/// takes precedence once it's high; otherwise friendship (including enmity at
/// negative values) sets the tier. `Spouse` is reserved for an explicit
/// marriage life-event and is never derived here.
pub fn relationship_level(rel: &RelationshipData) -> RelationshipSentiment {
    use RelationshipSentiment::*;
    let f = rel.friendship_score;
    let r = rel.romance_score;
    if r >= 70.0 {
        Partner
    } else if r >= 40.0 {
        RomanticInterest
    } else if f <= -70.0 {
        Nemesis
    } else if f <= -40.0 {
        Enemy
    } else if f >= 70.0 {
        BestFriend
    } else if f >= 50.0 {
        GoodFriend
    } else if f >= 30.0 {
        Friend
    } else if f >= 15.0 {
        Acquaintance
    } else {
        Stranger
    }
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

/// A running conversation between two (or more) sims. Lives on its own entity;
/// participants carry an `InConversation` marker pointing back to it.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Conversation {
    pub participants: Vec<Entity>,
    pub context: ConversationContext,
    /// In-game minutes accumulated since the last exchange.
    pub timer: f32,
    /// Number of social exchanges performed so far.
    pub exchanges: u32,
    /// Running friendly/tense balance (positive = warm, negative = tense).
    pub warmth: f32,
    /// Running romantic charge accumulated from romantic exchanges.
    pub romance: f32,
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::Trait;

    fn entity(n: u32) -> Entity {
        Entity::from_raw(n)
    }

    #[test]
    fn levels_track_score_thresholds() {
        use RelationshipSentiment::*;
        let mut rel = RelationshipData::default();
        assert_eq!(relationship_level(&rel), Stranger);
        rel.friendship_score = 20.0;
        assert_eq!(relationship_level(&rel), Acquaintance);
        rel.friendship_score = 55.0;
        assert_eq!(relationship_level(&rel), GoodFriend);
        rel.friendship_score = 80.0;
        assert_eq!(relationship_level(&rel), BestFriend);
        // Romance overrides friendship tier once high enough.
        rel.romance_score = 75.0;
        assert_eq!(relationship_level(&rel), Partner);
        // Enmity at negative friendship (with no romance).
        rel.romance_score = 0.0;
        rel.friendship_score = -80.0;
        assert_eq!(relationship_level(&rel), Nemesis);
    }

    #[test]
    fn apply_clamps_and_refreshes_level() {
        let mut rel = RelationshipData::default();
        rel.apply(40.0, 0.0);
        assert_eq!(rel.friendship_score, 40.0);
        assert_eq!(rel.sentiment, RelationshipSentiment::Friend);
        // Romance clamps at 0 on the low side.
        rel.apply(0.0, -20.0);
        assert_eq!(rel.romance_score, 0.0);
        // Friendship clamps at 100 on the high side.
        rel.apply(1000.0, 0.0);
        assert_eq!(rel.friendship_score, 100.0);
    }

    #[test]
    fn relationships_are_directional_and_dedup_traits() {
        let (a_view, b) = (Relationships::default(), entity(7));
        let mut a_view = a_view;
        a_view.record(b, 25.0, 0.0);
        a_view.note_trait(b, Trait::Cheerful);
        a_view.note_trait(b, Trait::Cheerful); // duplicate ignored

        let rel = a_view.get(b).unwrap();
        assert_eq!(rel.friendship_score, 25.0);
        assert_eq!(rel.known_traits, vec![Trait::Cheerful]);
        assert_eq!(rel.sentiment, RelationshipSentiment::Acquaintance);

        // A separate sim's view starts empty (directional, independent).
        let b_view = Relationships::default();
        assert!(b_view.get(b).is_none());
    }
}
