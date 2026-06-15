# Just Life — Agent Notes

## Project Operations

- **Package manager:** `cargo`
- **Build:** `cargo build`
- **Run:** `cargo run`
- **Tests:** `cargo test`
- **Lint:** `cargo clippy`
- **Format:** `cargo fmt`
- **WASM build:** `./build-wasm.sh` (requires `wasm-bindgen` CLI in `~/.cargo/bin`; ensure `~/.cargo/bin` is on `PATH`)
- **WASM profile:** `Cargo.toml` defines `[profile.wasm-release]` with `opt-level = "s"` and `lto = true`
- **WASM test:** serve `web/`, open in browser, verify with screenshot using chrome-devtools

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
