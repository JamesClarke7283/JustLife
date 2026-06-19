//! Game settings (Phase 11.5).
//!
//! A persisted [`GameSettings`] resource plus a keyboard-driven settings overlay
//! (toggle with `O` in live mode; Up/Down to pick a row, Left/Right to change it,
//! Esc/O to close). Settings are saved to `localStorage` (web) or a file (native)
//! whenever they change and reloaded at startup.
//!
//! Applied now: audio volumes (drive [`AudioState`]), needs-decay rate
//! (see `sim::needs::decay_needs`) and camera zoom speed. Stored for later /
//! partial application: autonomy level, sim aging speed, camera invert-Y &
//! rotation speed (the isometric camera has no free-look axis), graphics quality
//! presets, resolution/fullscreen (not meaningful on the web canvas) and key
//! remapping.

use bevy::prelude::*;
use serde::{Deserialize, Serialize};

use crate::audio::AudioState;
use crate::core::state::GameState;

const SETTINGS_KEY: &str = "justlife_settings";

/// Autonomy level for sim AI.
#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum AutonomyLevel {
    #[default]
    Full,
    High,
    Low,
    Off,
}

/// Graphics quality preset.
#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Quality {
    Low,
    Medium,
    #[default]
    High,
}

/// Persisted player settings.
#[derive(Resource, Serialize, Deserialize, Clone, PartialEq, Debug)]
pub struct GameSettings {
    pub master_volume: f32,
    pub music_volume: f32,
    pub sfx_volume: f32,
    pub ambient_volume: f32,
    pub autonomy: AutonomyLevel,
    /// Needs-decay rate multiplier (0.5 = slow, 2.0 = fast).
    pub needs_decay: f32,
    /// Sim aging speed multiplier (stored; applied by the aging system).
    pub aging_speed: f32,
    pub invert_y: bool,
    /// Camera rotation/pan speed multiplier (stored).
    pub camera_speed: f32,
    /// Camera zoom speed multiplier (applied to the scroll step).
    pub zoom_speed: f32,
    pub quality: Quality,
    /// UI language code (see `i18n::available_languages`).
    #[serde(default = "default_language")]
    pub language: String,
}

fn default_language() -> String {
    "en".to_string()
}

impl Default for GameSettings {
    fn default() -> Self {
        Self {
            master_volume: 1.0,
            music_volume: 0.7,
            sfx_volume: 0.8,
            ambient_volume: 0.5,
            autonomy: AutonomyLevel::Full,
            needs_decay: 1.0,
            aging_speed: 1.0,
            invert_y: false,
            camera_speed: 1.0,
            zoom_speed: 1.0,
            quality: Quality::High,
            language: default_language(),
        }
    }
}

/// Whether the settings overlay is open and which row is highlighted.
#[derive(Resource, Default)]
struct SettingsMenu {
    open: bool,
    cursor: usize,
}

#[derive(Component)]
struct SettingsRoot;

/// The adjustable rows, in display order.
#[derive(Clone, Copy, PartialEq)]
enum Row {
    Master,
    Music,
    Sfx,
    Ambient,
    Autonomy,
    NeedsDecay,
    AgingSpeed,
    ZoomSpeed,
    CameraSpeed,
    InvertY,
    Quality,
    Language,
}

const ROWS: [Row; 12] = [
    Row::Master,
    Row::Music,
    Row::Sfx,
    Row::Ambient,
    Row::Autonomy,
    Row::NeedsDecay,
    Row::AgingSpeed,
    Row::ZoomSpeed,
    Row::CameraSpeed,
    Row::InvertY,
    Row::Quality,
    Row::Language,
];

impl Row {
    fn label(self) -> &'static str {
        match self {
            Row::Master => "Master Volume",
            Row::Music => "Music Volume",
            Row::Sfx => "SFX Volume",
            Row::Ambient => "Ambient Volume",
            Row::Autonomy => "Autonomy",
            Row::NeedsDecay => "Needs Decay",
            Row::AgingSpeed => "Aging Speed",
            Row::ZoomSpeed => "Zoom Speed",
            Row::CameraSpeed => "Camera Speed",
            Row::InvertY => "Invert Camera Y",
            Row::Quality => "Graphics Quality",
            Row::Language => "Language",
        }
    }

    fn value(self, s: &GameSettings) -> String {
        match self {
            Row::Master => pct(s.master_volume),
            Row::Music => pct(s.music_volume),
            Row::Sfx => pct(s.sfx_volume),
            Row::Ambient => pct(s.ambient_volume),
            Row::Autonomy => format!("{:?}", s.autonomy),
            Row::NeedsDecay => format!("{:.1}x", s.needs_decay),
            Row::AgingSpeed => format!("{:.1}x", s.aging_speed),
            Row::ZoomSpeed => format!("{:.1}x", s.zoom_speed),
            Row::CameraSpeed => format!("{:.1}x", s.camera_speed),
            Row::InvertY => if s.invert_y { "On" } else { "Off" }.to_string(),
            Row::Quality => format!("{:?}", s.quality),
            Row::Language => crate::i18n::language_name(&s.language).to_string(),
        }
    }

    /// Adjust this row by `dir` (-1 / +1).
    fn adjust(self, s: &mut GameSettings, dir: i32) {
        let d = dir as f32;
        match self {
            Row::Master => s.master_volume = step01(s.master_volume, d),
            Row::Music => s.music_volume = step01(s.music_volume, d),
            Row::Sfx => s.sfx_volume = step01(s.sfx_volume, d),
            Row::Ambient => s.ambient_volume = step01(s.ambient_volume, d),
            Row::Autonomy => s.autonomy = cycle_autonomy(s.autonomy, dir),
            Row::NeedsDecay => s.needs_decay = step_mult(s.needs_decay, d),
            Row::AgingSpeed => s.aging_speed = step_mult(s.aging_speed, d),
            Row::ZoomSpeed => s.zoom_speed = step_mult(s.zoom_speed, d),
            Row::CameraSpeed => s.camera_speed = step_mult(s.camera_speed, d),
            Row::InvertY => s.invert_y = !s.invert_y,
            Row::Quality => s.quality = cycle_quality(s.quality, dir),
            Row::Language => s.language = cycle_language(&s.language, dir),
        }
    }
}

fn cycle_language(current: &str, dir: i32) -> String {
    let langs = crate::i18n::available_languages();
    let i = langs.iter().position(|(c, _)| *c == current).unwrap_or(0) as i32;
    let n = langs.len() as i32;
    langs[(((i + dir) % n + n) % n) as usize].0.to_string()
}

fn pct(v: f32) -> String {
    format!("{}%", (v * 100.0).round() as i32)
}
fn step01(v: f32, d: f32) -> f32 {
    (v + 0.1 * d).clamp(0.0, 1.0)
}
fn step_mult(v: f32, d: f32) -> f32 {
    (v + 0.1 * d).clamp(0.25, 3.0)
}
fn cycle_autonomy(a: AutonomyLevel, dir: i32) -> AutonomyLevel {
    let order = [
        AutonomyLevel::Full,
        AutonomyLevel::High,
        AutonomyLevel::Low,
        AutonomyLevel::Off,
    ];
    cycle(&order, a, dir)
}
fn cycle_quality(q: Quality, dir: i32) -> Quality {
    let order = [Quality::Low, Quality::Medium, Quality::High];
    cycle(&order, q, dir)
}
fn cycle<T: Copy + PartialEq>(order: &[T], current: T, dir: i32) -> T {
    let i = order.iter().position(|&x| x == current).unwrap_or(0) as i32;
    let n = order.len() as i32;
    order[(((i + dir) % n + n) % n) as usize]
}

// ---- storage (localStorage on web, file natively) --------------------------

#[cfg(target_arch = "wasm32")]
fn write_settings(data: &str) {
    if let Some(Ok(Some(ls))) = web_sys::window().map(|w| w.local_storage()) {
        let _ = ls.set_item(SETTINGS_KEY, data);
    }
}
#[cfg(target_arch = "wasm32")]
fn read_settings() -> Option<String> {
    let ls = web_sys::window()?.local_storage().ok()??;
    ls.get_item(SETTINGS_KEY).ok()?
}
#[cfg(not(target_arch = "wasm32"))]
fn write_settings(data: &str) {
    let _ = std::fs::create_dir_all("saves");
    let _ = std::fs::write(format!("saves/{SETTINGS_KEY}.ron"), data);
}
#[cfg(not(target_arch = "wasm32"))]
fn read_settings() -> Option<String> {
    std::fs::read_to_string(format!("saves/{SETTINGS_KEY}.ron")).ok()
}

// ---- systems ---------------------------------------------------------------

/// Load persisted settings at startup (falling back to defaults).
fn load_settings(mut settings: ResMut<GameSettings>) {
    if let Some(raw) = read_settings()
        && let Ok(loaded) = ron::from_str::<GameSettings>(&raw)
    {
        *settings = loaded;
    }
}

/// Persist settings whenever they change (skipping the initial insert).
fn persist_settings(settings: Res<GameSettings>, mut started: Local<bool>) {
    if !*started {
        *started = true;
        return;
    }
    if settings.is_changed()
        && let Ok(data) = ron::to_string(&*settings)
    {
        write_settings(&data);
    }
}

/// Keep the live `AudioState` in sync with the settings.
fn apply_audio(settings: Res<GameSettings>, mut audio: ResMut<AudioState>) {
    if !settings.is_changed() {
        return;
    }
    audio.master_volume = settings.master_volume;
    audio.music_volume = settings.music_volume;
    audio.sfx_volume = settings.sfx_volume;
    audio.ambient_volume = settings.ambient_volume;
}

/// Open/close the overlay and edit the highlighted row.
fn settings_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut menu: ResMut<SettingsMenu>,
    mut settings: ResMut<GameSettings>,
) {
    if keyboard.just_pressed(KeyCode::KeyO) {
        menu.open = !menu.open;
        return;
    }
    if !menu.open {
        return;
    }
    if keyboard.just_pressed(KeyCode::Escape) {
        menu.open = false;
        return;
    }
    if keyboard.any_just_pressed([KeyCode::ArrowDown, KeyCode::KeyS]) {
        menu.cursor = (menu.cursor + 1) % ROWS.len();
    }
    if keyboard.any_just_pressed([KeyCode::ArrowUp, KeyCode::KeyW]) {
        menu.cursor = (menu.cursor + ROWS.len() - 1) % ROWS.len();
    }
    let row = ROWS[menu.cursor];
    if keyboard.any_just_pressed([KeyCode::ArrowRight, KeyCode::KeyD]) {
        row.adjust(&mut settings, 1);
    }
    if keyboard.any_just_pressed([KeyCode::ArrowLeft, KeyCode::KeyA]) {
        row.adjust(&mut settings, -1);
    }
}

/// Rebuild the overlay (immediate-mode) when it's open and something changed.
fn render_settings(
    mut commands: Commands,
    menu: Res<SettingsMenu>,
    settings: Res<GameSettings>,
    roots: Query<Entity, With<SettingsRoot>>,
) {
    if !menu.is_changed() && !settings.is_changed() {
        return;
    }
    for entity in &roots {
        commands.entity(entity).despawn_recursive();
    }
    if !menu.open {
        return;
    }
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Percent(50.0),
                    top: Val::Percent(50.0),
                    width: Val::Px(420.0),
                    margin: UiRect::new(Val::Px(-210.0), Val::ZERO, Val::Px(-220.0), Val::ZERO),
                    flex_direction: FlexDirection::Column,
                    padding: UiRect::all(Val::Px(18.0)),
                    row_gap: Val::Px(4.0),
                    ..default()
                },
                background_color: Color::srgba(0.06, 0.08, 0.13, 0.97).into(),
                border_radius: BorderRadius::all(Val::Px(8.0)),
                z_index: ZIndex::Global(90),
                ..default()
            },
            SettingsRoot,
            Name::new("Settings Menu"),
        ))
        .with_children(|root| {
            text(root, "Settings", 26.0, Color::WHITE);
            text(
                root,
                "Up/Down select   Left/Right change   [Esc/O] close",
                13.0,
                Color::srgba(0.8, 0.86, 0.95, 0.85),
            );
            for (i, row) in ROWS.iter().enumerate() {
                let selected = i == menu.cursor;
                let marker = if selected { ">" } else { " " };
                let color = if selected {
                    Color::srgb(0.5, 0.95, 0.6)
                } else {
                    Color::srgb(0.82, 0.88, 0.95)
                };
                text(
                    root,
                    &format!("{marker} {:<18} < {} >", row.label(), row.value(&settings)),
                    18.0,
                    color,
                );
            }
        });
}

fn text(parent: &mut ChildBuilder, value: &str, size: f32, color: Color) {
    parent.spawn(TextBundle::from_section(
        value,
        TextStyle {
            font_size: size,
            color,
            ..default()
        },
    ));
}

/// Registers game settings + the overlay.
pub struct SettingsPlugin;

impl Plugin for SettingsPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<GameSettings>()
            .init_resource::<SettingsMenu>()
            .add_systems(Startup, load_settings)
            .add_systems(
                Update,
                (
                    settings_input.run_if(in_state(GameState::LiveMode)),
                    render_settings,
                    apply_audio,
                    persist_settings,
                )
                    .chain(),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_ron_round_trips() {
        let mut s = GameSettings::default();
        s.master_volume = 0.4;
        s.autonomy = AutonomyLevel::Low;
        s.quality = Quality::Medium;
        s.invert_y = true;
        let text = ron::to_string(&s).unwrap();
        let back: GameSettings = ron::from_str(&text).unwrap();
        assert_eq!(s, back);
    }

    #[test]
    fn volume_steps_clamp_to_unit() {
        assert_eq!(step01(0.95, 1.0), 1.0);
        assert_eq!(step01(0.05, -1.0), 0.0);
        assert!((step01(0.5, 1.0) - 0.6).abs() < 1e-6);
    }

    #[test]
    fn enum_cycles_wrap_both_ways() {
        assert_eq!(cycle_autonomy(AutonomyLevel::Off, 1), AutonomyLevel::Full);
        assert_eq!(cycle_autonomy(AutonomyLevel::Full, -1), AutonomyLevel::Off);
        assert_eq!(cycle_quality(Quality::High, 1), Quality::Low);
    }

    #[test]
    fn adjust_routes_to_the_right_field() {
        let mut s = GameSettings::default();
        Row::Sfx.adjust(&mut s, -1);
        assert!((s.sfx_volume - 0.7).abs() < 1e-6);
        Row::InvertY.adjust(&mut s, 1);
        assert!(s.invert_y);
    }
}
