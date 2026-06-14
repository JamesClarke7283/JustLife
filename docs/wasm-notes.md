# WASM Build Notes for Just Life

This project targets both native desktop and browser (WASM) builds with Bevy 0.14.2.

## Required toolchain

- `rustup target add wasm32-unknown-unknown`
- `cargo install wasm-bindgen-cli` (binary lands in `~/.cargo/bin`)
- Ensure `~/.cargo/bin` is on `PATH` when running `./build-wasm.sh`.

## Cargo configuration

`.cargo/config.toml` must set the `getrandom_backend` cfg flag for the wasm target:

```toml
[target.wasm32-unknown-unknown]
rustflags = ["--cfg", "getrandom_backend=\"wasm_js\""]
```

## Target-specific dependencies

`Cargo.toml` needs wasm-only dependencies so `getrandom` and `uuid` know how to source randomness in the browser:

```toml
[target.wasm32-unknown-unknown.dependencies]
wasm-bindgen = "0.2.125"
wasm-bindgen-futures = "0.4.75"
web-sys = "0.3.102"
getrandom = { version = "0.3.4", features = ["wasm_js"] }
uuid = { version = "1.23.3", features = ["js"] }
```

## Build script

`./build-wasm.sh` performs the following steps:

1. Compiles the project with `cargo build --profile wasm-release --target wasm32-unknown-unknown`.
2. Runs `wasm-bindgen --out-dir web/ --target web --no-typescript` on the produced `.wasm` file.

The browser shell is in `web/`:
- `index.html` loads the canvas, styles, and `index.js`.
- `index.js` imports the wasm-bindgen glue and passes the canvas.
- `styles.css` makes the canvas full-screen.

## Testing

1. Serve `web/` with any static HTTP server, e.g. `python3 -m http.server 8000 --directory web/`.
2. Open `http://localhost:8000` in a browser.
3. Verify the scene renders (green ground plane + blue cube + directional light).

## Troubleshooting

- `wasm-bindgen not found`: add `~/.cargo/bin` to `PATH`.
- `getrandom` compile error about `wasm_js`: verify `.cargo/config.toml` rustflags and the `getrandom` wasm dependency feature.
- `uuid` compile error about randomness: add `uuid = { version = "1.23.3", features = ["js"] }` under the wasm target dependencies.
- Bevy 0.18.x changed the 3D bundle API (`Mesh3d`/`MeshMaterial3d` instead of `PbrBundle`). This project stays on Bevy 0.14.2 to avoid that churn while the project skeleton is stabilizing.
