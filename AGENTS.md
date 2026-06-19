# Just Life — Agent Notes

## Project Operations

- **Package manager:** `cargo`
- **Build:** `cargo build`
- **Run:** `cargo run`
- **Tests:** `cargo test`
- **Lint:** `cargo clippy`
- **Format:** `cargo fmt`
- **WASM build:** `./build-wasm.sh [profile]`. Default profile `wasm-release` (LTO, `opt-level="s"`) is optimized but SLOW and memory-hungry — under load it has taken **15+ min and been OOM-killed**. For VERIFICATION builds use the fast profile: **`./build-wasm.sh wasm-dev`** (no LTO, `opt-level=1`, 16 codegen-units) — first run compiles all deps (~10 min) but is then incremental and ~2-3 min; the wasm is bigger/less-optimized (~50 MB vs 25 MB) but runs fine for screenshots. Use `wasm-release` only for final/shippable builds.
- Requires `wasm-bindgen` CLI in `~/.cargo/bin` (ensure it's on `PATH`). **Don't rely on background builds across loop ticks** — they get killed when the session suspends, leaving a stale wasm. Either build in the foreground, or `nohup` it and actively wait with an `until grep -qa "<new-string>" web/just-life_bg.wasm; do sleep 8; done` poll so the turn stays alive until the wasm updates. Confirm a build actually landed by grepping the wasm for a string unique to your change before screenshotting.
- The local HTTP server (`python3 -m http.server 8000` in `web/`) also dies on suspend — restart it (and `curl` localhost:8000 to confirm) before navigating.
- **WASM profile:** `Cargo.toml` defines `[profile.wasm-release]` with `opt-level = "s"` and `lto = true`
- **WASM test:** serve `web/`, open in browser, verify with screenshot using chrome-devtools
- **Object catalog:** buy-mode objects are data-driven in `assets/data/catalog.ron`
  (a list of `CatalogItem`, see `src/world/catalog.rs`). It's embedded via
  `include_str!` and parsed at startup, so **adding/editing items requires a
  rebuild** (not just an asset reload). Each item assembles its mesh from coloured
  primitive `parts` (cuboid/cylinder/sphere/cone, local space, y up, origin at the
  footprint centre on the floor). `spawn_catalog_item` builds the entity tree and
  tags it `PlacedObject` + `Interactable` + `Sellable`. Preview thumbnails live in
  `assets/textures/catalog/<id>.png`. Occupancy/depreciation live in
  `src/world/placed.rs` (`ObjectGrid`, `footprint_cells`, `DepreciationTimer`).

## Bevy Version

This project currently uses **Bevy 0.14.2**. Bevy 0.18.x introduced API changes that broke the project skeleton (e.g., `Mesh3d`/`MeshMaterial3d` renamed, `add_event` chain behavior changed, `EventWriter` import issues). Stay on 0.14.x for stability while the project is in early phases.

## WASM Build Notes

- `wasm32-unknown-unknown` target is required (`rustup target add wasm32-unknown-unknown`).
- Bevy pulls in `getrandom` and `uuid`; for WASM these need:
  - `getrandom = { version = "0.3.4", features = ["wasm_js"] }` as a `wasm32-unknown-unknown` dependency.
  - `uuid = { version = "1.23.3", features = ["js"] }` as a `wasm32-unknown-unknown` dependency.
- `.cargo/config.toml` should set the `getrandom_backend` cfg for the wasm target:
  ```toml
  [target.wasm32-unknown-unknown]
  rustflags = ["--cfg", "getrandom_backend=\"wasm_js\""]
  ```
- If `build-wasm.sh` reports that `wasm-bindgen` is not found, ensure `~/.cargo/bin` is on `PATH`.

## Rendering & Visibility Gotchas (learned the hard way)

These caused a fully blank (clear-color-only) browser screen — debug with the
chrome-devtools MCP (serve `web/` then reload/screenshot/console):

- **Bind Bevy to the page canvas.** `DefaultPlugins.set(WindowPlugin { primary_window:
  Some(Window { canvas: Some("#game-canvas".into()), fit_canvas_to_parent: true, .. }) })`.
  Without it, Bevy appends its *own* second canvas and the two break page layout.
  Do NOT also set `canvas.width/height` from JS — it fights `fit_canvas_to_parent`
  and yields an unstable tiny render buffer. Let Bevy own the size.
- **Orthographic camera: use `ScalingMode::WindowSize(px_per_unit)`** (≈40) with
  `scale` tied to zoom. `ScalingMode::FixedVertical` was tried and rendered nothing
  in this project — avoid it.
- **B0004 / parent-child mesh rendering.** Any entity that receives `PbrBundle`
  *children* (walls, doors, windows, the sim, the lot) MUST itself carry the
  spatial+visibility components — spawn it with `SpatialBundle`
  (`SpatialBundle::from_transform(..)` / `::default()`), never a bare `Transform`
  or data-only tuple. A `warning[B0004]` in the console means a child has
  `InheritedVisibility` but its parent doesn't → the child won't render.
- The `Uncaught (in promise)` from `winit ... throw` on web is normal (event-loop
  unwind), as are `.meta`/favicon 404s and SSAO/DoF "not supported" logs.

## Input & UI Verification (headless WASM)

- **Synthetic mouse events do NOT reach winit** in the chrome-devtools harness
  (`click`/`drag`/`hover` dispatch DOM events the Bevy canvas ignores), but
  **`press_key` DOES** once the canvas is focused. So: give any UI you need to
  screenshot a **keyboard entry point**, then verify by
  `evaluate_script` → `canvas.focus()` → `press_key`. Example: the pie menu
  (`src/ui/pie_menu.rs`) opens with `Q` and selects wedges with number keys
  `1-9` (in addition to the mouse path), which is what made it screenshot-able.
- **Bevy 0.14 UI overlays**: position absolutely with `Style { position_type:
  Absolute, left/top: Val::Px(..) }` over the 3D view; `NodeBundle` supports
  `border_radius: BorderRadius::all(..)` for circular buttons, and `Color` has
  `.lighter(f)` / `.with_alpha(f)` for hover states. `TextStyle { font_size,
  color, ..default() }` uses the bundled default font (no asset handle needed).
  Immediate-mode menus (despawn-all + respawn each frame from a resource) work
  fine and keep render logic stateless — mirror `placement.rs`'s ghost pattern.
- **Lifetime-based UI (toasts, timed popups): clamp `time.delta_seconds()`.**
  The heavy `LiveMode`-enter transition (sim spawn + HUD + systems starting) can
  produce a single multi-second frame delta. A timed element that subtracts the
  raw delta drains its whole lifetime in one tick and despawns before it ever
  renders — it'll log as spawned but never appear. Clamp the per-tick step (e.g.
  `time.delta_seconds().min(0.1)`). Symptom that points here: the element's
  spawn log fires once, no panic, but nothing shows. (Cost me ~7 build cycles on
  the toast system; a long temporary lifetime + a despawn log isolated it.)
- **Fast WASM verification builds: `./build-wasm.sh wasm-dev`.** The default
  `wasm-release` (lto=true) takes 5–16 min and OOM-kills under memory pressure;
  the `[profile.wasm-dev]` (no LTO, opt-level 1) builds incrementally in ~2–3 min
  and is fine for screenshot verification. `build-wasm.sh` takes the profile as
  its first arg. Run it from the repo root (a stray `cd web` for the http server
  leaves the cwd wrong — use absolute paths or `cd` back).
- **Transient black screen / screenshot timeout on a state transition is usually
  NOT a real bug.** On a heavy first frame (e.g. entering `LiveMode`: menu
  despawns, HUD spawns, all sim/career systems start at once) the chrome-devtools
  `take_screenshot` RPC can time out and a follow-up capture may grab one black
  frame. Confirm it's transient before chasing it: install a capture
  (`console.error` override + `window.onerror`/`unhandledrejection`) via
  `evaluate_script`, trigger the action, then read the array back — if
  `evaluate_script` returns and the array is empty, the main thread is alive and
  there was no panic. Re-screenshot a moment later; it renders fine.

## Audio (Phase 11)

- **Assets are served via a symlink:** `web/assets -> ../assets`, so anything
  under `assets/` (incl. `assets/audio/*.ogg`) is reachable at
  `http://localhost:8000/assets/...` with no copy step. Confirm with
  `curl -o /dev/null -w '%{http_code}' .../assets/audio/menu.ogg`.
- **No audio-generation MCP tool** (imagegen is images only). Placeholder music
  is generated with **ffmpeg** (`sine` + `amix` + `afade` → short ambient `.ogg`
  loops); real royalty-free music is a human asset task. SFX are tiny ffmpeg tones.
- **Audio can't be heard in the headless harness.** Verify it indirectly: build,
  load, walk to the state, then `list_console_messages` for the *absence* of
  audio-load errors (a missing/undecodable `.ogg` logs an error). The
  routing/volume logic lives in pure fns (`music_for_state`, `*_level`) and is
  unit-tested instead.
- **Browser autoplay policy:** music won't actually sound until the first user
  gesture (a key/click); the asset still *loads* immediately. Bevy plays
  `AudioBundle` via `PlaybackSettings::{LOOP,DESPAWN}` + `Volume::new()`; fade is
  a manual `AudioSink::set_volume` ramp.

## Localization (Phase 11.6)

- Locale files are `String -> String` RON maps in `assets/locales/<lang>.ron`,
  embedded via `include_str!` (instant switching, offline). `Locale::get(key)`
  falls back to the key. Active language follows `GameSettings.language`;
  `sync_locale` reloads on change, and `relocalize_hud` rebuilds the HUD live
  (verified en->es swaps the needs labels with no restart).
- **The default Bevy font (FiraSans) renders accented glyphs (í/ó/ñ) as tofu
  boxes.** Non-ASCII locales need an extended-glyph font loaded — the translation
  strings are correct, only the rendering is limited.

## Save / load (Phase 11.4)

- **Storage is split by target:** `localStorage` on `wasm32` (needs `web-sys`
  features `["Window", "Storage"]` in Cargo.toml) and a `saves/<key>.ron` file
  natively, behind `#[cfg(target_arch = "wasm32")]`. Slots are `justlife_save_<n>`
  (slot 0 = autosave). Adding a web-sys feature forces a full dep recompile (~10 min).
- **Verify save/load headlessly via JS, not just keypresses:** `evaluate_script`
  can `localStorage.getItem('justlife_save_1')` to inspect the actual serialized
  RON (proves the *save* captured state), and can **tamper** a field
  (`raw.replace('money:16000','money:50000')` + `setItem`) before pressing F9 —
  then the HUD visibly changes on load (proves the *load* applied + rebuilt the
  world). Much stronger than a same-state round-trip. localStorage persists across
  reloads too.
- **RON omits struct names by default:** `SavedSim`/`SavedObject` serialize as bare
  `(...)` tuples, so don't regex for the type name — match the fields.
- **Restore rebuilds, doesn't patch:** load despawns all `SimName`/`PlacedObject`
  entities, clears `SimManager.sims` + `ObjectGrid.occupied`, then re-spawns via
  `spawn_one_sim` / `spawn_catalog_item`. `register_placed_objects` re-populates
  the grid next frame. Appearance is restored from the CAS preset indices.

## Visual feedback (Phase 11.3)

- **Floating indicators that track a sim** (mood orb, selection ring) are spawned
  as **standalone entities repositioned each frame**, NOT as mesh children of the
  sim — child meshes hit the B0004 visibility-hierarchy trap. Hide them when the
  sim is off-lot (`transform.translation.y < -1.0`, e.g. at work).

## Project Structure

- `src/core/` — shared ECS resources, events, components, state, time
- `src/sim/` — Sim entities, needs, traits, appearance, animation
- `src/world/` — lots, walls, rooms, placed objects
- `src/ui/` — Bevy UI systems
- `src/interaction/` — interaction queue, pie menu, routing
- `src/career/` — careers, skills, economy
- `src/social/` — relationships, conversations, sentiments
- `src/audio/` — audio systems
- `src/assets/` — asset management helpers
- `src/wasm/` — wasm-specific plugin
- `assets/` — runtime assets (textures, models, fonts, sounds, music)
- `web/` — browser shell and WASM output
- `docs/` — modding documentation and project notes

## Research

Check these before web searching (load with Read tool as needed):
- `docs/wasm-notes.md` — WASM build quirks for this project
- Bevy 0.14 docs via `context7_query-docs` for API specifics
