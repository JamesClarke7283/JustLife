# Just Life — Agent Notes

## Project Operations

- **Runtime:** Deno 2.x (`deno --version` to confirm)
- **Desktop window:** `deno desktop main.ts` compiles a native binary that
  opens a window pointed at a local `Deno.serve()` HTTP handler. For fast
  iteration use `deno desktop --hmr main.ts` (hot-reload on file change).
- **Client bundle:** `deno task bundle` — bundles `client/main.ts` (which
  imports `three` from the deno.json import map) into a single
  `public/main.js` served to the desktop window. Re-run after client changes
  unless using `--hmr`.
- **Run (dev):** `deno task dev` → `deno desktop --hmr main.ts`
- **Run (ship):** `deno task start` → `deno desktop main.ts` (produces
  `./MyApp` / `MyApp.exe` / `MyApp.app`)
- **Lint:** `deno lint`
- **Format:** `deno fmt`
- **Tests:** `deno test`

## Stack

- **Server:** `main.ts` uses `Deno.serve()` to serve static files from
  `public/` (`/` → `index.html`, `/main.js`, `/styles.css`). The desktop
  backend wires the native window to this local server automatically — no
  manual port needed.
- **3D:** Three.js (imported as `npm:three` via the deno.json import map).
  Client entry is `client/main.ts`; it is bundled to `public/main.js` because
  browsers can't resolve npm/jsr specifiers directly.
- **UI:** HTML/CSS overlay (`public/index.html`, `public/styles.css`) on top
  of the full-viewport three.js canvas. Use semantic HTML + CSS for menus/HUD
  rather than an in-canvas UI library.
- **TypeScript types** for three.js come from
  `npm:@types/three@^0.180.0` (dev-only, in deno.json `imports`).

## Project Structure

- `main.ts` — server entry (`Deno.serve`), desktop app entrypoint
- `deno.json` — import map (three + types), tasks, compiler/lint/fmt config
- `client/` — browser-side TypeScript (imports three.js), bundled to `public/`
- `public/` — static assets served to the desktop window
  - `index.html` — page shell + menu overlay markup
  - `styles.css` — menu / HUD styling
  - `main.js` — generated bundle (gitignored), do not edit by hand
- `assets/` — runtime game assets (textures, models, fonts, sounds, music)
- `src/` — server-side / shared game logic modules (game state, save data, etc.)

## Conventions

- Keep the server (`main.ts`, `src/`) and client (`client/`, `public/`) split
  clear: the server serves files and (later) persists save data; the client
  runs three.js and all game rendering/interaction in the desktop window.
- The three.js scene is the source of truth for the 3D world; menus/HUD are
  HTML overlays positioned with CSS over the canvas.
- Prefer re-bundling (`deno task bundle`) and reloading the desktop window to
  verify changes. `deno desktop --hmr` avoids manual re-bundles during dev.