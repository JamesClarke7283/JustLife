# Just Life — Agent Notes

## Project Operations

- **Runtime:** Deno 2.x (`deno --version` to confirm)
- **Version:** `0.1.0` (set in `deno.json`)
- **Desktop window:** `deno desktop main.ts` compiles a native binary that
  opens a window pointed at a local `Deno.serve()` HTTP handler. For fast
  iteration use `deno desktop --hmr main.ts` (hot-reload on file change).
- **Client bundle:** `deno task bundle` — bundles `client/main.ts` (which
  imports `three` from the deno.json import map) into a single
  `public/main.js` served to the desktop window. Re-run after client changes
  unless using `--hmr`.
- **Run (dev):** `deno task dev` → `deno desktop --hmr --allow-read main.ts`
- **Run (ship):** `deno task start` → `deno desktop --allow-read main.ts`
- **Lint:** `deno lint`
- **Format:** `deno fmt`
- **Tests:** `deno test`

## Packaging & Distribution

`deno desktop` cross-compiles to native installers for all platforms. The
`public/` and `assets/` directories are embedded in the binary via
`--include public --include assets` so the server can serve them at runtime.

### Local packaging tasks

| Task | Output |
|------|--------|
| `deno task pack:linux` | `dist/JustLife-x86_64.{AppImage,deb,rpm}` |
| `deno task pack:linux-arm` | `dist/JustLife-aarch64.{AppImage,deb}` |
| `deno task pack:macos` | `dist/JustLife.dmg` (current arch; needs macOS host for .dmg) |
| `deno task pack:windows` | `dist/JustLife.msi` |
| `deno task pack:all` | All targets via `--all-targets` |

### Icon

- `icons/justlife.png` — 1024×1024 PNG (macOS + Linux)
- `icons/justlife.ico` — multi-size ICO (Windows: 256/128/96/64/48/32/16)
- `icons/justlife.svg` — source SVG (editable)
- Regenerate from SVG: `magick icons/justlife.svg -resize 1024x1024 icons/justlife.png`
- Regenerate ICO: `magick icons/justlife.png -define icon:auto-resize=256,128,96,64,48,32,16 icons/justlife.ico`

### CI release workflow — `.github/workflows/release.yml`

Triggers on: tag push (`v*`) or published GitHub release. Builds 8 artifacts
in parallel across a 5-runner matrix:

| Runner | Target | Artifacts |
|--------|--------|-----------|
| `ubuntu-latest` | `x86_64-unknown-linux-gnu` | `.AppImage`, `.deb`, `.rpm` |
| `ubuntu-latest` | `aarch64-unknown-linux-gnu` | `.AppImage`, `.deb` |
| `macos-14` | `aarch64-apple-darwin` | `.dmg` (Apple Silicon) |
| `macos-15-intel` | `x86_64-apple-darwin` | `.dmg` (Intel) |
| `windows-latest` | `x86_64-pc-windows-msvc` | `.msi` |

Artifacts are auto-attached to the GitHub release via
`softprops/action-gh-release@v2`.

### Releasing a new version

```sh
# 1. Update version in deno.json
# 2. Commit and push
git tag v0.1.0
git push origin main --tags
# 3. CI builds + attaches artifacts to the release automatically
```

macOS builds are **unsigned** for v0.1.0 — users right-click → Open on first
launch to bypass Gatekeeper.

## Stack

- **Server:** `main.ts` uses `Deno.serve()` to serve static files from
  `public/` (`/` → `index.html`, `/main.js`, `/styles.css`). Resolves
  `public/` from `cwd` (dev) or the embedded path (compiled binary). The
  desktop backend wires the native window to this local server automatically.
- **3D:** Three.js (imported as `npm:three` via the deno.json import map).
  Client entry is `client/main.ts`; it is bundled to `public/main.js` because
  browsers can't resolve npm/jsr specifiers directly.
- **UI:** HTML/CSS overlay (`public/index.html`, `public/styles.css`) on top
  of the full-viewport three.js canvas. Use semantic HTML + CSS for menus/HUD
  rather than an in-canvas UI library.
- **TypeScript types** for three.js come from
  `npm:@types/three@^0.180.0` (dev-only, in deno.json `imports`).
- **Desktop config:** The `desktop` block in `deno.json` sets app name,
  identifier (`com.justlife.app`), icon paths, and output paths.

## Project Structure

- `main.ts` — server entry (`Deno.serve`), desktop app entrypoint
- `deno.json` — import map (three + types), tasks, desktop config, version
- `client/` — browser-side TypeScript (imports three.js), bundled to `public/`
  - `theme.ts` — single source of truth for colors (CSS vars + 3D materials)
  - `data/` — JSON game data (catalog, careers, locale)
  - `engine/` — three.js engine modules (scene, world, objects, sim, etc.)
- `public/` — static assets served to the desktop window
  - `index.html` — page shell + menu/HUD overlay markup
  - `styles.css` — menu / HUD styling
  - `main.js` — generated bundle (gitignored), do not edit by hand
- `assets/` — runtime game assets (textures, audio)
- `icons/` — application icon (.png, .ico, .svg)
- `.github/workflows/release.yml` — CI release pipeline

## Conventions

- Keep the server (`main.ts`, `src/`) and client (`client/`, `public/`) split
  clear: the server serves files and (later) persists save data; the client
  runs three.js and all game rendering/interaction in the desktop window.
- The three.js scene is the source of truth for the 3D world; menus/HUD are
  HTML overlays positioned with CSS over the canvas.
- Prefer re-bundling (`deno task bundle`) and reloading the desktop window to
  verify changes. `deno desktop --hmr` avoids manual re-bundles during dev.
- All colors live in `client/theme.ts` — never hardcode colors in CSS or
  three.js materials; reference the theme or its CSS variables instead.