//! Social interaction catalog (Phase 8.2).
//!
//! The authoritative list of social actions a sim can perform on another sim,
//! grouped by [`InteractionCategory`]. Each action carries its effect on the
//! directional relationship scores and any relationship gate (e.g. "Propose"
//! needs high romance). The conversation system (Phase 8.4) consumes this to
//! resolve interactions; the pie menu (8.1) surfaces the names.

use crate::interaction::InteractionCategory;
use crate::social::RelationshipData;

/// A single social action and its directional relationship effects.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SocialAction {
    pub name: &'static str,
    pub category: InteractionCategory,
    /// Change applied to the actor->target friendship score on success.
    pub friendship: f32,
    /// Change applied to the actor->target romance score on success.
    pub romance: f32,
    /// Minimum existing friendship required to offer this action.
    pub min_friendship: f32,
    /// Minimum existing romance required to offer this action.
    pub min_romance: f32,
}

impl SocialAction {
    const fn new(
        name: &'static str,
        category: InteractionCategory,
        friendship: f32,
        romance: f32,
    ) -> Self {
        Self {
            name,
            category,
            friendship,
            romance,
            min_friendship: 0.0,
            min_romance: 0.0,
        }
    }

    /// Builder: require a minimum friendship score to be offered.
    const fn gated_friendship(mut self, min: f32) -> Self {
        self.min_friendship = min;
        self
    }

    /// Builder: require a minimum romance score to be offered.
    const fn gated_romance(mut self, min: f32) -> Self {
        self.min_romance = min;
        self
    }

    /// Whether this action is unlocked for the given relationship.
    pub fn is_available(&self, rel: &RelationshipData) -> bool {
        rel.friendship_score >= self.min_friendship && rel.romance_score >= self.min_romance
    }
}

/// The full social interaction catalog.
pub fn social_catalog() -> Vec<SocialAction> {
    use InteractionCategory::*;
    vec![
        // Friendly: build friendship, a little warmth.
        SocialAction::new("Chat", Friendly, 5.0, 0.0),
        SocialAction::new("Joke", Friendly, 6.0, 0.0),
        SocialAction::new("Compliment", Friendly, 7.0, 2.0),
        SocialAction::new("Hug", Friendly, 8.0, 3.0).gated_friendship(15.0),
        SocialAction::new("Ask About Day", Friendly, 5.0, 0.0),
        SocialAction::new("Be Funny", Friendly, 6.0, 0.0),
        SocialAction::new("Console", Friendly, 9.0, 2.0),
        // Romantic: gated behind growing romance.
        SocialAction::new("Flirt", Romantic, 3.0, 8.0).gated_friendship(20.0),
        SocialAction::new("Compliment Appearance", Romantic, 2.0, 7.0),
        SocialAction::new("Hold Hands", Romantic, 4.0, 10.0).gated_romance(30.0),
        SocialAction::new("Kiss", Romantic, 5.0, 15.0).gated_romance(50.0),
        SocialAction::new("Propose", Romantic, 10.0, 20.0).gated_romance(80.0),
        SocialAction::new("Break Up", Romantic, -30.0, -40.0),
        // Mean: erode the relationship.
        SocialAction::new("Insult", Mean, -10.0, -5.0),
        SocialAction::new("Argue", Mean, -12.0, -8.0),
        SocialAction::new("Fight", Mean, -25.0, -15.0),
        SocialAction::new("Slap", Mean, -20.0, -20.0),
        SocialAction::new("Steal", Mean, -15.0, -5.0),
        SocialAction::new("Spread Rumor", Mean, -18.0, -8.0),
        // Funny: light friendship, pranks risk a little romance.
        SocialAction::new("Tell Joke", Funny, 6.0, 0.0),
        SocialAction::new("Funny Story", Funny, 6.0, 1.0),
        SocialAction::new("Prank", Funny, 2.0, -2.0),
        SocialAction::new("Silly Face", Funny, 4.0, 0.0),
        // Special: utility/relationship-building.
        SocialAction::new("Teach", Special, 5.0, 0.0),
        SocialAction::new("Advise", Special, 6.0, 0.0),
        SocialAction::new("Mentor", Special, 7.0, 0.0).gated_friendship(30.0),
        SocialAction::new("Ask for Loan", Special, -2.0, 0.0).gated_friendship(25.0),
        SocialAction::new("Propose Activity", Special, 5.0, 2.0),
    ]
}

/// All actions in a category (regardless of availability).
pub fn actions_in_category(category: InteractionCategory) -> Vec<SocialAction> {
    social_catalog()
        .into_iter()
        .filter(|a| a.category == category)
        .collect()
}

/// Actions currently unlocked for a given relationship.
pub fn available_actions(rel: &RelationshipData) -> Vec<SocialAction> {
    social_catalog()
        .into_iter()
        .filter(|a| a.is_available(rel))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_covers_every_category() {
        use InteractionCategory::*;
        for category in [Friendly, Romantic, Mean, Funny, Special] {
            assert!(
                !actions_in_category(category).is_empty(),
                "category {category:?} has no actions"
            );
        }
    }

    #[test]
    fn romance_gates_lock_until_score_is_high() {
        let catalog = social_catalog();
        let propose = catalog.iter().find(|a| a.name == "Propose").unwrap();

        let strangers = RelationshipData::default();
        assert!(!propose.is_available(&strangers));

        let lovers = RelationshipData {
            friendship_score: 70.0,
            romance_score: 85.0,
            ..Default::default()
        };
        assert!(propose.is_available(&lovers));
    }

    #[test]
    fn basic_friendly_actions_are_always_available() {
        let strangers = RelationshipData::default();
        let available = available_actions(&strangers);
        assert!(available.iter().any(|a| a.name == "Chat"));
        // Hug needs a little friendship first.
        assert!(!available.iter().any(|a| a.name == "Hug"));
    }

    #[test]
    fn mean_actions_need_no_relationship() {
        let strangers = RelationshipData::default();
        let available = available_actions(&strangers);
        for name in ["Insult", "Argue", "Fight"] {
            assert!(available.iter().any(|a| a.name == name));
        }
    }
}
