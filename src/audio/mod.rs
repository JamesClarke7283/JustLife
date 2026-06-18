//! Audio: state-based background music with fade, volume control, and sound
//! effects (Phase 11.1 + 11.2).
//!
//! Music switches with the game state (menu / live / build), fading in. An
//! `SfxEvent` plays a one-shot sound; toast notifications trigger one. Volumes
//! come from `AudioState`. (Audio can't be verified in the headless harness, so
//! the routing/volume logic is unit-tested and the tracks are simple generated
//! ambient loops.)

use bevy::audio::Volume;
use bevy::prelude::*;

use crate::core::events::ToastEvent;
use crate::core::state::GameState;

pub struct AudioPlugin;

impl Plugin for AudioPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<AudioState>()
            .register_type::<AudioState>()
            .add_event::<SfxEvent>()
            .add_systems(
                Update,
                (
                    switch_music,
                    fade_in_music,
                    play_sfx,
                    notification_sfx,
                    ui_click_sfx,
                ),
            );
    }
}

/// Mixer levels and the current track.
#[derive(Resource, Debug, Clone, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct AudioState {
    pub master_volume: f32,
    pub music_volume: f32,
    pub sfx_volume: f32,
    pub ambient_volume: f32,
    pub current_track: Option<String>,
}

impl Default for AudioState {
    fn default() -> Self {
        Self {
            master_volume: 1.0,
            music_volume: 0.7,
            sfx_volume: 0.8,
            ambient_volume: 0.5,
            current_track: None,
        }
    }
}

impl AudioState {
    /// Effective music volume (master * music).
    pub fn music_level(&self) -> f32 {
        (self.master_volume * self.music_volume).clamp(0.0, 1.0)
    }
    /// Effective sfx volume (master * sfx).
    pub fn sfx_level(&self) -> f32 {
        (self.master_volume * self.sfx_volume).clamp(0.0, 1.0)
    }
}

/// Request to play a one-shot sound effect (asset path under `assets/`).
#[derive(Event)]
pub struct SfxEvent(pub &'static str);

/// Marks the looping background-music entity, with its fade target/progress.
#[derive(Component)]
struct BackgroundMusic {
    track: &'static str,
    target: f32,
    elapsed: f32,
}

/// The looping music track for a game state (None = silence).
pub fn music_for_state(state: GameState) -> Option<&'static str> {
    match state {
        GameState::MainMenu | GameState::CreateASim | GameState::LotSelect => {
            Some("audio/menu.ogg")
        }
        GameState::LiveMode => Some("audio/live.ogg"),
        GameState::BuildMode | GameState::BuyMode => Some("audio/build.ogg"),
        GameState::Loading => None,
    }
}

/// Swap the background music when the desired track changes with the state.
fn switch_music(
    state: Res<State<GameState>>,
    audio: Res<AudioState>,
    asset_server: Res<AssetServer>,
    mut commands: Commands,
    existing: Query<(Entity, &BackgroundMusic)>,
) {
    let next = music_for_state(*state.get());
    let playing = existing.iter().next().map(|(_, m)| m.track);
    if next == playing {
        return; // already playing the right track (or both None)
    }
    for (entity, _) in &existing {
        commands.entity(entity).despawn();
    }
    if let Some(track) = next {
        commands.spawn((
            AudioBundle {
                source: asset_server.load(track),
                settings: PlaybackSettings::LOOP.with_volume(Volume::new(0.0)),
            },
            BackgroundMusic {
                track,
                target: audio.music_level(),
                elapsed: 0.0,
            },
        ));
    }
}

/// Fade newly-started music up to its target volume over ~1.5s.
fn fade_in_music(time: Res<Time>, mut music: Query<(&mut BackgroundMusic, &AudioSink)>) {
    for (mut bg, sink) in &mut music {
        if bg.elapsed >= 1.5 {
            continue;
        }
        bg.elapsed += time.delta_seconds();
        let t = (bg.elapsed / 1.5).clamp(0.0, 1.0);
        sink.set_volume(bg.target * t);
    }
}

/// Play a one-shot sound effect per `SfxEvent`.
fn play_sfx(
    mut events: EventReader<SfxEvent>,
    audio: Res<AudioState>,
    asset_server: Res<AssetServer>,
    mut commands: Commands,
) {
    for SfxEvent(path) in events.read() {
        commands.spawn(AudioBundle {
            source: asset_server.load(*path),
            settings: PlaybackSettings::DESPAWN.with_volume(Volume::new(audio.sfx_level())),
        });
    }
}

/// Play a notification chime whenever a toast appears (Phase 10.7's sound).
fn notification_sfx(mut toasts: EventReader<ToastEvent>, mut sfx: EventWriter<SfxEvent>) {
    for _ in toasts.read() {
        sfx.send(SfxEvent("audio/success.ogg"));
    }
}

/// Click sound when any UI button is pressed.
fn ui_click_sfx(
    buttons: Query<&Interaction, (Changed<Interaction>, With<Button>)>,
    mut sfx: EventWriter<SfxEvent>,
) {
    for interaction in &buttons {
        if *interaction == Interaction::Pressed {
            sfx.send(SfxEvent("audio/click.ogg"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn music_maps_states_to_tracks() {
        assert_eq!(music_for_state(GameState::MainMenu), Some("audio/menu.ogg"));
        assert_eq!(
            music_for_state(GameState::CreateASim),
            Some("audio/menu.ogg")
        );
        assert_eq!(music_for_state(GameState::LiveMode), Some("audio/live.ogg"));
        assert_eq!(
            music_for_state(GameState::BuildMode),
            Some("audio/build.ogg")
        );
        assert_eq!(music_for_state(GameState::Loading), None);
    }

    #[test]
    fn volume_levels_clamp() {
        let mut a = AudioState::default();
        a.master_volume = 2.0;
        a.music_volume = 2.0;
        assert_eq!(a.music_level(), 1.0);
        a.master_volume = 0.5;
        a.music_volume = 0.5;
        a.sfx_volume = 1.0;
        assert_eq!(a.music_level(), 0.25);
        assert_eq!(a.sfx_level(), 0.5);
    }
}
