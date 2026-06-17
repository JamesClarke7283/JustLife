use bevy::prelude::*;

pub mod economy;

pub struct CareerPlugin;

impl Plugin for CareerPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(economy::EconomyPlugin)
            .init_resource::<CareerDatabase>()
            .register_type::<Career>()
            .register_type::<JobPerformance>()
            .register_type::<Skills>();
    }
}

/// All career tracks, loaded from the embedded RON data at startup.
///
/// (No `Default` derive: it provides `FromWorld` to load the embedded RON, which
/// would conflict with Bevy's blanket `FromWorld for T: Default`.)
#[derive(Resource, Debug)]
pub struct CareerDatabase {
    pub careers: Vec<CareerDefinition>,
}

impl CareerDatabase {
    /// Parse the career tracks from a RON string (a list of `CareerDefinition`).
    pub fn parse_ron(src: &str) -> Result<Self, ron::error::SpannedError> {
        let careers: Vec<CareerDefinition> = ron::from_str(src)?;
        Ok(Self { careers })
    }

    /// Look up a career track by name.
    pub fn get(&self, name: &str) -> Option<&CareerDefinition> {
        self.careers.iter().find(|c| c.name == name)
    }
}

impl FromWorld for CareerDatabase {
    fn from_world(_world: &mut World) -> Self {
        const RON: &str = include_str!("../../assets/data/careers.ron");
        match Self::parse_ron(RON) {
            Ok(db) => {
                info!("Loaded {} career tracks", db.careers.len());
                db
            }
            Err(err) => {
                error!("Failed to parse careers.ron: {err}");
                Self {
                    careers: Vec::new(),
                }
            }
        }
    }
}

#[derive(Default, Debug, Clone, PartialEq, Reflect, serde::Serialize, serde::Deserialize)]
#[reflect]
pub struct CareerDefinition {
    pub name: String,
    pub levels: Vec<CareerLevel>,
}

impl CareerDefinition {
    /// The level data for a 1-based career level, if it exists.
    pub fn level_at(&self, level: u8) -> Option<&CareerLevel> {
        if level == 0 {
            return None;
        }
        self.levels.get(level as usize - 1)
    }

    /// The highest level in this track (its length).
    pub fn max_level(&self) -> u8 {
        self.levels.len() as u8
    }
}

#[derive(Default, Debug, Clone, PartialEq, Reflect, serde::Serialize, serde::Deserialize)]
#[reflect]
pub struct CareerLevel {
    pub title: String,
    pub salary: u32,
    pub work_days: Vec<u8>,
    pub start_hour: u8,
    pub end_hour: u8,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Career {
    pub name: String,
    pub level: u8,
    pub daily_performance: f32,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct JobPerformance {
    pub score: f32,
    pub days_missed: u32,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Skills {
    pub levels: bevy::utils::HashMap<SkillType, u8>,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect)]
#[reflect]
pub enum SkillType {
    #[default]
    Cooking,
    Handiness,
    Charisma,
    Fitness,
    Logic,
    Creativity,
    Gardening,
    Fishing,
    Programming,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> CareerDatabase {
        const RON: &str = include_str!("../../assets/data/careers.ron");
        CareerDatabase::parse_ron(RON).expect("careers.ron parses")
    }

    #[test]
    fn all_eight_tracks_load() {
        let db = db();
        assert_eq!(db.careers.len(), 8);
        for name in [
            "Tech",
            "Culinary",
            "Entertainment",
            "Business",
            "Athletic",
            "Creative",
            "Medical",
            "Criminal",
        ] {
            assert!(db.get(name).is_some(), "missing career {name}");
        }
    }

    #[test]
    fn levels_are_ordered_and_salaries_rise() {
        let tech = db().get("Tech").cloned().expect("Tech track");
        assert_eq!(tech.level_at(1).unwrap().title, "QA Tester");
        assert_eq!(tech.level_at(tech.max_level()).unwrap().title, "CTO");
        // Out-of-range levels return None.
        assert!(tech.level_at(0).is_none());
        assert!(tech.level_at(tech.max_level() + 1).is_none());
        // Salary increases up the track.
        for w in tech.levels.windows(2) {
            assert!(w[1].salary > w[0].salary);
        }
    }
}
