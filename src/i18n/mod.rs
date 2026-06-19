//! Localization framework (Phase 11.6).
//!
//! UI strings are looked up by dotted key (`ui.needs.Hunger`) from a [`Locale`]
//! resource. Locale files live in `assets/locales/<lang>.ron` (a `String ->
//! String` map) and are embedded at build time, so switching language is instant
//! and works offline. The active language follows `GameSettings::language`; the
//! settings overlay has a Language row. Community translations: copy `en.ron`,
//! translate the values, and add the language to [`available_languages`] + the
//! `load_strings` match.
//!
//! Migration status: the framework is wired through the HUD needs labels (which
//! re-localize live when the language changes). Migrating every remaining
//! hard-coded string is ongoing — call `Locale::get` at each site as it's touched.

use std::collections::HashMap;

use bevy::prelude::*;

use crate::settings::GameSettings;

const EN: &str = include_str!("../../assets/locales/en.ron");
const ES: &str = include_str!("../../assets/locales/es.ron");

/// Languages the game ships with: (code, display name).
pub fn available_languages() -> &'static [(&'static str, &'static str)] {
    &[("en", "English"), ("es", "Español")]
}

/// Display name for a language code (falls back to the code).
pub fn language_name(code: &str) -> &'static str {
    available_languages()
        .iter()
        .find(|(c, _)| *c == code)
        .map(|(_, name)| *name)
        .unwrap_or("English")
}

fn load_strings(lang: &str) -> HashMap<String, String> {
    let raw = match lang {
        "es" => ES,
        _ => EN,
    };
    ron::from_str(raw).unwrap_or_default()
}

/// The active language and its loaded strings.
#[derive(Resource)]
pub struct Locale {
    pub lang: String,
    strings: HashMap<String, String>,
}

impl Default for Locale {
    fn default() -> Self {
        Self::new("en")
    }
}

impl Locale {
    pub fn new(lang: &str) -> Self {
        Self {
            lang: lang.to_string(),
            strings: load_strings(lang),
        }
    }

    /// Translate `key`, falling back to the key itself if it's missing.
    pub fn get(&self, key: &str) -> String {
        self.strings
            .get(key)
            .cloned()
            .unwrap_or_else(|| key.to_string())
    }
}

/// Reload the locale whenever the chosen language differs from the loaded one.
fn sync_locale(settings: Res<GameSettings>, mut locale: ResMut<Locale>) {
    if settings.language != locale.lang {
        *locale = Locale::new(&settings.language);
    }
}

/// Registers the localization framework.
pub struct LocalePlugin;

impl Plugin for LocalePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Locale>()
            .add_systems(Update, sync_locale);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn english_and_spanish_load_and_translate() {
        let en = Locale::new("en");
        let es = Locale::new("es");
        assert_eq!(en.get("ui.needs.Hunger"), "Hunger");
        assert_eq!(es.get("ui.needs.Hunger"), "Hambre");
        assert_eq!(es.get("ui.needs.Energy"), "Energía");
    }

    #[test]
    fn missing_key_falls_back_to_key() {
        let en = Locale::new("en");
        assert_eq!(en.get("ui.does.not.exist"), "ui.does.not.exist");
    }

    #[test]
    fn unknown_language_falls_back_to_english() {
        let xx = Locale::new("xx");
        assert_eq!(xx.get("ui.needs.Fun"), "Fun");
        assert_eq!(language_name("xx"), "English");
        assert_eq!(language_name("es"), "Español");
    }
}
