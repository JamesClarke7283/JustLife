//! Save / load (Phase 11.4).
//!
//! Captures the household to a RON snapshot and stores it in browser
//! `localStorage` (WASM) or a `saves/` file (native), across 3 slots. Saving
//! and loading are driven by keys (F5 save, F9 load) so they work in the
//! headless harness, plus an auto-save every 10 in-game minutes. On load the
//! resources are applied and the sims + placed objects are rebuilt through the
//! same spawn paths the game uses normally.
//!
//! Scope: money, time, lot, play-time, sims (identity / appearance / traits /
//! needs / position / career) and placed objects. Relationships, skills and
//! inventory are not yet serialized (the `version` field allows extending the
//! format later).

use bevy::prelude::*;
use serde::{Deserialize, Serialize};

use crate::career::{Career, JobPerformance};
use crate::core::events::ToastEvent;
use crate::core::resources::{GameTime, MoneyResource};
use crate::core::state::GameState;
use crate::sim::appearance::appearance_from_indices;
use crate::sim::needs::Needs;
use crate::sim::{
    SimAge, SimConfig, SimGender, SimManager, SimName, SimTraits, Trait, spawn_one_sim,
};
use crate::ui::create_a_sim::voice_pitch;
use crate::ui::lot_select::PurchasedLot;
use crate::world::catalog::{CatalogDatabase, spawn_catalog_item};
use crate::world::placed::ObjectGrid;
use crate::world::{ObjectCondition, PlacedObject};

/// Number of save slots (0 is the auto-save slot).
pub const SLOTS: usize = 3;
/// Current save-format version.
const VERSION: u32 = 1;
/// Auto-save cadence, in in-game minutes.
const AUTOSAVE_MINUTES: i64 = 10;

/// Wall-clock time the current household has been played (live mode only).
#[derive(Resource, Default)]
pub struct PlayClock {
    pub seconds: f32,
}

/// Tracks the last in-game minute mark an auto-save fired on.
#[derive(Resource)]
struct AutoSave {
    last_total: i64,
}

impl Default for AutoSave {
    fn default() -> Self {
        Self {
            last_total: i64::MIN, // first frame establishes the baseline
        }
    }
}

/// Pending save/load slot requests (set by keys/auto-save, drained by the
/// perform systems). One resource keeps both system signatures small.
#[derive(Resource, Default)]
struct SaveIo {
    saves: Vec<usize>,
    loads: Vec<usize>,
}

/// A full serialized household snapshot.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct SaveGame {
    pub version: u32,
    pub money: i64,
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
    pub lot: String,
    pub play_seconds: f32,
    pub sims: Vec<SavedSim>,
    pub objects: Vec<SavedObject>,
}

/// One sim's persisted state.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct SavedSim {
    pub first: String,
    pub last: String,
    pub gender: SimGender,
    pub age: SimAge,
    pub traits: Vec<Trait>,
    // Create-A-Sim appearance preset indices.
    pub skin: usize,
    pub hair_color: usize,
    pub hair_style: usize,
    pub shirt: usize,
    pub voice: usize,
    pub needs: [f32; 6],
    pub pos: [f32; 3],
    pub career: Option<(String, u8)>,
}

/// One placed object's persisted state.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct SavedObject {
    pub catalog_id: String,
    pub pos: [f32; 3],
    pub yaw: f32,
    pub condition: ObjectCondition,
    pub powered: bool,
}

/// Human-readable summary of a save, for slot displays.
pub fn summarize(save: &SaveGame) -> String {
    let names = save
        .sims
        .iter()
        .map(|s| s.first.clone())
        .collect::<Vec<_>>()
        .join(", ");
    let names = if names.is_empty() {
        "—".into()
    } else {
        names
    };
    format!(
        "{} · {} · Day {} · {}",
        save.lot,
        names,
        save.day,
        format_playtime(save.play_seconds)
    )
}

/// Format a play-time duration like "1h 23m" / "45m".
pub fn format_playtime(seconds: f32) -> String {
    let total_min = (seconds / 60.0) as u64;
    let (h, m) = (total_min / 60, total_min % 60);
    if h > 0 {
        format!("{h}h {m:02}m")
    } else {
        format!("{m}m")
    }
}

// ---- storage backend (localStorage on web, files natively) -----------------

fn slot_key(slot: usize) -> String {
    format!("justlife_save_{slot}")
}

#[cfg(target_arch = "wasm32")]
fn storage_write(slot: usize, data: &str) -> Result<(), String> {
    let win = web_sys::window().ok_or_else(|| "no window".to_string())?;
    let ls = win
        .local_storage()
        .map_err(|_| "localStorage unavailable".to_string())?
        .ok_or_else(|| "no localStorage".to_string())?;
    ls.set_item(&slot_key(slot), data)
        .map_err(|_| "set_item failed".to_string())
}

#[cfg(target_arch = "wasm32")]
fn storage_read(slot: usize) -> Option<String> {
    let win = web_sys::window()?;
    let ls = win.local_storage().ok()??;
    ls.get_item(&slot_key(slot)).ok()?
}

#[cfg(not(target_arch = "wasm32"))]
fn storage_write(slot: usize, data: &str) -> Result<(), String> {
    std::fs::create_dir_all("saves").map_err(|e| e.to_string())?;
    std::fs::write(format!("saves/{}.ron", slot_key(slot)), data).map_err(|e| e.to_string())
}

#[cfg(not(target_arch = "wasm32"))]
fn storage_read(slot: usize) -> Option<String> {
    std::fs::read_to_string(format!("saves/{}.ron", slot_key(slot))).ok()
}

/// A one-line summary of the save in `slot`, if present (for slot UIs).
pub fn slot_summary(slot: usize) -> Option<String> {
    let raw = storage_read(slot)?;
    let save: SaveGame = ron::from_str(&raw).ok()?;
    Some(summarize(&save))
}

// ---- systems ---------------------------------------------------------------

/// Accumulate played wall-clock time while in live mode.
fn tick_play_clock(time: Res<Time>, mut clock: ResMut<PlayClock>) {
    clock.seconds += time.delta_seconds();
}

/// F5 = save to slot 1, F9 = load from slot 1.
fn save_load_keys(keyboard: Res<ButtonInput<KeyCode>>, mut io: ResMut<SaveIo>) {
    if keyboard.just_pressed(KeyCode::F5) {
        io.saves.push(1);
    }
    if keyboard.just_pressed(KeyCode::F9) {
        io.loads.push(1);
    }
}

/// Auto-save to slot 0 every `AUTOSAVE_MINUTES` in-game minutes.
fn auto_save(time: Res<GameTime>, mut auto: ResMut<AutoSave>, mut io: ResMut<SaveIo>) {
    let total = (time.day as i64 * 24 + time.hour as i64) * 60 + time.minute as i64;
    if auto.last_total == i64::MIN {
        auto.last_total = total; // baseline, don't save on the first frame
    } else if total - auto.last_total >= AUTOSAVE_MINUTES {
        auto.last_total = total;
        io.saves.push(0);
    }
}

/// Drain save requests: snapshot the world and write it to storage.
#[allow(clippy::too_many_arguments, clippy::type_complexity)]
fn perform_save(
    mut io: ResMut<SaveIo>,
    money: Res<MoneyResource>,
    time: Res<GameTime>,
    lot: Res<PurchasedLot>,
    clock: Res<PlayClock>,
    config: Res<SimConfig>,
    sims: Query<(
        &SimName,
        &SimGender,
        &SimAge,
        &SimTraits,
        &Needs,
        &Transform,
        Option<&Career>,
    )>,
    objects: Query<&PlacedObject>,
    mut toasts: EventWriter<ToastEvent>,
) {
    if io.saves.is_empty() {
        return;
    }
    let slots = std::mem::take(&mut io.saves);

    let saved_sims = sims
        .iter()
        .map(
            |(name, gender, age, traits, needs, transform, career)| SavedSim {
                first: name.first.clone(),
                last: name.last.clone(),
                gender: *gender,
                age: *age,
                traits: traits.traits.clone(),
                skin: config.skin,
                hair_color: config.hair_color,
                hair_style: config.hair_style,
                shirt: config.shirt,
                voice: config.voice,
                needs: [
                    needs.hunger,
                    needs.energy,
                    needs.social,
                    needs.fun,
                    needs.hygiene,
                    needs.bladder,
                ],
                pos: transform.translation.to_array(),
                career: career.map(|c| (c.name.clone(), c.level)),
            },
        )
        .collect();

    let saved_objects = objects
        .iter()
        .map(|obj| SavedObject {
            catalog_id: obj.catalog_id.clone(),
            pos: obj.position.to_array(),
            yaw: obj.rotation.to_euler(EulerRot::YXZ).0,
            condition: obj.condition,
            powered: obj.powered,
        })
        .collect();

    let save = SaveGame {
        version: VERSION,
        money: money.amount,
        day: time.day,
        hour: time.hour,
        minute: time.minute,
        lot: lot.name.clone(),
        play_seconds: clock.seconds,
        sims: saved_sims,
        objects: saved_objects,
    };

    let Ok(data) = ron::to_string(&save) else {
        toasts.send(ToastEvent::error("Save failed (serialize)"));
        return;
    };
    for slot in slots {
        match storage_write(slot, &data) {
            Ok(()) if slot == 0 => {} // auto-save: silent
            Ok(()) => {
                toasts.send(ToastEvent::success("Game saved"));
            }
            Err(e) => {
                toasts.send(ToastEvent::error(format!("Save failed: {e}")));
            }
        }
    }
}

/// Drain load requests: read a snapshot and rebuild the household.
#[allow(clippy::too_many_arguments)]
fn perform_load(
    mut commands: Commands,
    mut io: ResMut<SaveIo>,
    asset_server: Res<AssetServer>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    catalog: Res<CatalogDatabase>,
    mut money: ResMut<MoneyResource>,
    mut time: ResMut<GameTime>,
    mut lot: ResMut<PurchasedLot>,
    mut clock: ResMut<PlayClock>,
    mut config: ResMut<SimConfig>,
    mut manager: ResMut<SimManager>,
    mut grid: ResMut<ObjectGrid>,
    existing_sims: Query<Entity, With<SimName>>,
    existing_objects: Query<Entity, With<PlacedObject>>,
    mut toasts: EventWriter<ToastEvent>,
) {
    if io.loads.is_empty() {
        return;
    }
    let slot = io.loads.remove(0);
    io.loads.clear();

    let Some(raw) = storage_read(slot) else {
        toasts.send(ToastEvent::warning("No save in that slot"));
        return;
    };
    let save: SaveGame = match ron::from_str(&raw) {
        Ok(s) => s,
        Err(e) => {
            toasts.send(ToastEvent::error(format!("Load failed: {e}")));
            return;
        }
    };

    // Apply resources.
    money.amount = save.money;
    time.day = save.day;
    time.hour = save.hour;
    time.minute = save.minute;
    lot.name = save.lot.clone();
    clock.seconds = save.play_seconds;

    // Clear the current household.
    for entity in &existing_sims {
        commands.entity(entity).despawn_recursive();
    }
    for entity in &existing_objects {
        commands.entity(entity).despawn_recursive();
    }
    manager.sims.clear();
    grid.occupied.clear();

    // Rebuild sims.
    let skin_texture: Handle<Image> = asset_server.load("textures/sim_skin_tone.png");
    for (i, s) in save.sims.iter().enumerate() {
        if i == 0 {
            // Keep the SimConfig in sync with the (player) sim's appearance.
            config.first = s.first.clone();
            config.last = s.last.clone();
            config.gender = s.gender;
            config.age = s.age;
            config.traits = s.traits.clone();
            config.skin = s.skin;
            config.hair_color = s.hair_color;
            config.hair_style = s.hair_style;
            config.shirt = s.shirt;
            config.voice = s.voice;
        }
        let appearance = appearance_from_indices(s.skin, s.hair_color, s.hair_style, s.shirt);
        spawn_one_sim(
            &mut commands,
            &mut manager,
            &mut meshes,
            &mut materials,
            skin_texture.clone(),
            (s.first.as_str(), s.last.as_str()),
            s.gender,
            s.age,
            voice_pitch(s.voice),
            &s.traits,
            appearance,
            Vec3::from_array(s.pos),
            Needs {
                hunger: s.needs[0],
                energy: s.needs[1],
                social: s.needs[2],
                fun: s.needs[3],
                hygiene: s.needs[4],
                bladder: s.needs[5],
            },
        );
        if let Some((name, level)) = &s.career {
            // The freshly-spawned sim is the most recent one in the manager.
            if let Some(&entity) = manager.sims.last() {
                commands.entity(entity).insert((
                    Career {
                        name: name.clone(),
                        level: *level,
                        daily_performance: 0.0,
                    },
                    JobPerformance::default(),
                ));
            }
        }
    }

    // Rebuild placed objects.
    for o in &save.objects {
        let Some(item) = catalog.get(&o.catalog_id) else {
            continue;
        };
        let position = Vec3::from_array(o.pos);
        let rotation = Quat::from_rotation_y(o.yaw);
        let entity = spawn_catalog_item(
            &mut commands,
            &mut meshes,
            &mut materials,
            item,
            position,
            rotation,
        );
        // Restore mutable fields the default spawn resets.
        commands.entity(entity).insert(PlacedObject {
            catalog_id: o.catalog_id.clone(),
            position,
            rotation,
            condition: o.condition,
            footprint: item.footprint,
            powered: o.powered,
        });
    }

    toasts.send(ToastEvent::success("Game loaded"));
}

/// Registers save/load (live mode only).
pub struct SavePlugin;

impl Plugin for SavePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PlayClock>()
            .init_resource::<AutoSave>()
            .init_resource::<SaveIo>()
            .add_systems(
                Update,
                (
                    tick_play_clock,
                    save_load_keys,
                    auto_save,
                    perform_save,
                    perform_load,
                )
                    .chain()
                    .run_if(in_state(GameState::LiveMode)),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> SaveGame {
        SaveGame {
            version: VERSION,
            money: 12_345,
            day: 6,
            hour: 9,
            minute: 30,
            lot: "Cozy Starter".into(),
            play_seconds: 3_725.0,
            sims: vec![SavedSim {
                first: "Alex".into(),
                last: "Doe".into(),
                gender: SimGender::Female,
                age: SimAge::YoungAdult,
                traits: vec![Trait::Cheerful, Trait::Genius],
                skin: 1,
                hair_color: 2,
                hair_style: 0,
                shirt: 3,
                voice: 1,
                needs: [70.0, 65.0, 60.0, 60.0, 70.0, 70.0],
                pos: [0.0, 0.0, 2.0],
                career: Some(("Culinary".into(), 3)),
            }],
            objects: vec![SavedObject {
                catalog_id: "double_bed".into(),
                pos: [1.0, 0.0, 1.0],
                yaw: 1.57,
                condition: ObjectCondition::Dirty,
                powered: false,
            }],
        }
    }

    #[test]
    fn ron_round_trips() {
        let save = sample();
        let text = ron::to_string(&save).expect("serialize");
        let back: SaveGame = ron::from_str(&text).expect("deserialize");
        assert_eq!(save, back);
    }

    #[test]
    fn summary_lists_lot_sim_and_time() {
        let s = summarize(&sample());
        assert!(s.contains("Cozy Starter"));
        assert!(s.contains("Alex"));
        assert!(s.contains("Day 6"));
        assert!(s.contains("1h 02m"));
    }

    #[test]
    fn playtime_formats() {
        assert_eq!(format_playtime(45.0 * 60.0), "45m");
        assert_eq!(format_playtime(3_600.0), "1h 00m");
        assert_eq!(format_playtime(3_725.0), "1h 02m");
    }
}
