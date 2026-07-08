// Just Life — theming system.
// Single source of truth for all colors. At boot, injectCSSVars() writes
// these to :root CSS variables so the HTML/CSS HUD and the three.js scene
// materials share identical values — no drift between UI and 3D.

export interface Palette {
  primary: number;
  accent: number;
  accent2: number;
  surface: number;
  surfaceAlt: number;
  text: number;
  textDim: number;
  danger: number;
  warning: number;
  success: number;
  grass: number;
  grassDark: number;
  path: number;
  sky: number;
  skyFog: number;
  sun: number;
  wall: number;
  roof: number;
  wood: number;
  glass: number;
  skin: number;
  hair: number;
  shirt: number;
  pants: number;
}

export const NEEDS = ['Hunger', 'Energy', 'Social', 'Fun', 'Hygiene', 'Bladder'] as const;
export type NeedKey = (typeof NEEDS)[number];

export const NEED_COLORS: Record<NeedKey, number> = {
  Hunger: 0xe53935, // red
  Energy: 0x1e88e5, // blue
  Social: 0xd81b60, // pink
  Fun: 0x43a047, // green
  Hygiene: 0x00acc1, // cyan
  Bladder: 0x8e24aa, // purple
};

export const NEED_ICONS: Record<NeedKey, string> = {
  Hunger: '&#127858;',
  Energy: '&#9889;',
  Social: '&#128172;',
  Fun: '&#127922;',
  Hygiene: '&#128703;',
  Bladder: '&#128701;',
};

export const NEED_DECAY: Record<NeedKey, number> = {
  Hunger: 0.45,
  Energy: 0.30,
  Social: 0.20,
  Fun: 0.25,
  Hygiene: 0.18,
  Bladder: 0.35,
};

export const THEME: Palette = {
  primary: 0xffd27a,
  accent: 0xff9d6c,
  accent2: 0x6fd3e8,
  surface: 0x1c2836,
  surfaceAlt: 0x283648,
  text: 0xf4f7fb,
  textDim: 0x9fb0c0,
  danger: 0xe53935,
  warning: 0xfb8c00,
  success: 0x43a047,
  grass: 0x7cb342,
  grassDark: 0x689f38,
  path: 0xb0a8e0,
  sky: 0x9fd3e8,
  skyFog: 0x9fd3e8,
  sun: 0xfff3d6,
  wall: 0xf5e6c8,
  roof: 0xb5483a,
  wood: 0x5d4037,
  glass: 0xffe082,
  skin: 0xe8b88a,
  hair: 0x4e342e,
  shirt: 0x3949ab,
  pants: 0x37474f,
};

// Material palette used by build mode (floors/walls) — names map to textures
// we restored, but for the vertical slice we use flat colors keyed here.
export const FLOOR_MATERIALS: Record<string, number> = {
  hardwood_oak: 0x8d6e63,
  hardwood_light: 0xbcaaa4,
  carpet_beige: 0xd7ccc8,
  carpet_gray: 0xb0bec5,
  tile_cream: 0xfff8e1,
  tile_white: 0xf5f5f5,
  stone: 0x9e9e9e,
  concrete: 0x757575,
  pool_tile: 0x4fc3f7,
};

export const WALL_MATERIALS: Record<string, number> = {
  plaster_light: 0xf5e6c8,
  brick_red: 0xb5483a,
  wood_panel: 0x8d6e63,
};

// Per-tile price for flooring (charged when painting a floor tile or room).
export const FLOOR_MATERIAL_PRICES: Record<string, number> = {
  hardwood_oak: 25,
  hardwood_light: 22,
  carpet_beige: 15,
  carpet_gray: 14,
  tile_cream: 30,
  tile_white: 35,
  stone: 40,
  concrete: 12,
  pool_tile: 50,
};

// Per-cell price for walls (charged per cell length of a wall segment).
export const WALL_MATERIAL_PRICES: Record<string, number> = {
  plaster_light: 20,
  brick_red: 35,
  wood_panel: 30,
};

// Refund fraction when selling/deleting build elements (matches object sell rate).
export const REFUND_RATE = 0.6;

// Convert a hex number to a CSS color string.
export function hex(n: number): string {
  return '#' + n.toString(16).padStart(6, '0');
}

// Inject all theme values as CSS custom properties on :root.
export function injectCSSVars(): void {
  const root = document.documentElement;
  for (const [key, val] of Object.entries(THEME)) {
    root.style.setProperty(`--c-${key.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase())}`, hex(val));
  }
  for (const need of NEEDS) {
    root.style.setProperty(`--need-${need.toLowerCase()}`, hex(NEED_COLORS[need]));
  }
  root.style.setProperty('--accent', hex(THEME.primary));
  root.style.setProperty('--accent-2', hex(THEME.accent2));
}
