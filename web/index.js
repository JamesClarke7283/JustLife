import init from './just-life.js';

// Bevy (WindowPlugin `fit_canvas_to_parent: true`) owns the canvas buffer size,
// so we must NOT set canvas.width/height here — doing so fought Bevy's sizing
// and produced an unstable, tiny render buffer.
init();
