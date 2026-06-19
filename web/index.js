import init from './just-life.js';

// Register the service worker for offline caching (Phase 12.4). Registered
// eagerly (not on `load`) because the heavy WASM fetch delays the load event.
// Best-effort: failures (e.g. file:// or unsupported browsers) are ignored.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('./sw.js').catch(() => {});
}

// Bevy (WindowPlugin `fit_canvas_to_parent: true`) owns the canvas buffer size,
// so we must NOT set canvas.width/height here — doing so fought Bevy's sizing
// and produced an unstable, tiny render buffer.
init();
