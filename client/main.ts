// Just Life — client entry. Wires engine modules + HTML/CSS UI into a
// playable vertical slice: menu → live mode with sims, click-to-move,
// build/buy, jobs/money, needs, autonomy.
// Bundled to public/main.js (browsers can't resolve npm: specifiers).

import * as THREE from 'three';
import {
  FLOOR_MATERIALS,
  hex,
  injectCSSVars,
  NEED_COLORS,
  NEED_ICONS,
  type NeedKey,
  NEEDS,
  WALL_MATERIALS,
} from './theme.ts';
import { initScene, updateCamera } from './engine/scene.ts';
import { LOT_H, LOT_W, World } from './engine/world.ts';
import { footprintCells, type PlacedObject, placeObject } from './engine/objects.ts';
import { getThumbnail } from './engine/thumbnails.ts';
import { Sim } from './engine/sim.ts';
import { Needs, simNeeds } from './engine/needs.ts';
import { Career, Household, simCareer } from './engine/career.ts';
import { type AutonomyState, autonomyTick, findObjectForNeed, makeAutonomy } from './engine/ai.ts';
import { Input } from './engine/input.ts';
import { BuildMode, type BuildTool } from './engine/build.ts';
import type { CareerTrack, CatalogItem, GameMode, GameSpeed } from './engine/types.ts';
import catalogData from './data/catalog.json' with { type: 'json' };
import careersData from './data/careers.json' with { type: 'json' };
import localeData from './data/locale.json' with { type: 'json' };

const CATALOG: CatalogItem[] = catalogData as CatalogItem[];
const CAREERS: CareerTrack[] = careersData as CareerTrack[];
const LOCALE: Record<string, string> = localeData as Record<string, string>;
const t = (key: string): string => LOCALE[key] ?? key;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
let mode: GameMode = 'menu';
let speed: GameSpeed = 1;
const household = new Household();
const objects: PlacedObject[] = [];
const sims: Sim[] = [];
const autonomyStates: AutonomyState[] = [];
let selectedSim: Sim | null = null;
let lastDayForPromo = 1;

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
injectCSSVars();
const canvas = document.getElementById('game-canvas') as HTMLCanvasElement;
const ctx = initScene(canvas);
const world = new World(ctx.scene);
const build = new BuildMode(ctx.scene, world, objects);

// starter lot: a simple house shell + a few starter objects
function buildStarterLot(): void {
  // house room: grid 6..14 x, 6..14 z → 4 walls + floor
  const x0 = 6, x1 = 14, z0 = 6, z1 = 14;
  world.addWall({ axis: 'x', line: z0, start: x0, end: x1, material: 'plaster_light' });
  world.addWall({ axis: 'x', line: z1, start: x0, end: x1, material: 'plaster_light' });
  world.addWall({ axis: 'z', line: x0, start: z0, end: z1, material: 'plaster_light' });
  world.addWall({ axis: 'z', line: x1, start: z0, end: z1, material: 'plaster_light' });
  world.paintRoom(x0, z0, x1, z1, 'hardwood_oak');
  // leave a door gap by un-blocking two cells on the south wall (z0) — we can't
  // truly cut the wall mesh in this slice, so place objects inside instead.

  // starter furniture
  const bed = CATALOG.find((c) => c.id === 'bed_double')!;
  placeItem(bed, 8, 7);
  const sofa = CATALOG.find((c) => c.id === 'sofa_loveseat')!;
  placeItem(sofa, 12, 8);
  const fridge = CATALOG.find((c) => c.id === 'fridge')!;
  placeItem(fridge, 7, 13);
  const toilet = CATALOG.find((c) => c.id === 'toilet')!;
  placeItem(toilet, 13, 13);
  const tv = CATALOG.find((c) => c.id === 'tv_flatscreen')!;
  placeItem(tv, 11, 7);
  const shower = CATALOG.find((c) => c.id === 'shower')!;
  placeItem(shower, 7, 12);

  // outdoor: a tree + bush
  const tree = CATALOG.find((c) => c.id === 'tree_oak')!;
  placeItem(tree, 3, 3);
  const bush = CATALOG.find((c) => c.id === 'bush_round')!;
  placeItem(bush, 16, 16);
}

function placeItem(item: CatalogItem, gx: number, gz: number): void {
  const obj = placeObject(world, ctx.scene, item, gx, gz, 0);
  if (obj) objects.push(obj);
}

function spawnSims(): void {
  const sim1 = new Sim(ctx.scene, world, {
    name: 'Alex',
    shirtColor: 0x3949ab,
    hairColor: 0x4e342e,
  });
  sim1.setGridPos(10, 10);
  const sim2 = new Sim(ctx.scene, world, {
    name: 'Sam',
    shirtColor: 0xd81b60,
    hairColor: 0x212121,
    skinTone: 0xd4a373,
  });
  sim2.setGridPos(11, 10);
  sims.push(sim1, sim2);
  autonomyStates.push(makeAutonomy(), makeAutonomy());
  // give them starting careers = unemployed
  simCareer(sim1);
  simCareer(sim2);
}

// ---------------------------------------------------------------------------
// Input wiring
// ---------------------------------------------------------------------------
const input = new Input(canvas, ctx.camera, world, sims, objects, {
  onSelectSim: (sim) => {
    selectedSim = sim;
    updateSimPanel();
  },
  onMoveSim: (gx, gz) => {
    if (!selectedSim) return;
    const ok = selectedSim.moveTo(gx, gz);
    if (ok) toast(`${selectedSim.name} is moving...`);
  },
  onObjectClick: () => {},
  onGroundRightClick: () => {},
  onPieMenu: (obj, px, py) => showPieMenu(obj, px, py),
});

// Build-mode click interception on the canvas
canvas.addEventListener('click', (e) => {
  if (mode !== 'build' && mode !== 'buy') return;
  const rect = canvas.getBoundingClientRect();
  const ndc = new THREE.Vector2(
    ((e.clientX - rect.left) / rect.width) * 2 - 1,
    -((e.clientY - rect.top) / rect.height) * 2 + 1,
  );
  const ray = new THREE.Raycaster();
  ray.setFromCamera(ndc, ctx.camera);
  const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const pt = new THREE.Vector3();
  if (ray.ray.intersectPlane(plane, pt)) {
    const [gx, gz] = world.worldToGrid(pt.x, pt.z);
    if (mode === 'buy' && build.pendingItem) {
      build.onClick(gx, gz);
    } else if (mode === 'build') {
      build.onClick(gx, gz);
    }
  }
});

// hover for ghost preview in buy mode
canvas.addEventListener('mousemove', (e) => {
  if (mode !== 'buy' && mode !== 'build') return;
  const rect = canvas.getBoundingClientRect();
  const ndc = new THREE.Vector2(
    ((e.clientX - rect.left) / rect.width) * 2 - 1,
    -((e.clientY - rect.top) / rect.height) * 2 + 1,
  );
  const ray = new THREE.Raycaster();
  ray.setFromCamera(ndc, ctx.camera);
  const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const pt = new THREE.Vector3();
  if (ray.ray.intersectPlane(plane, pt)) {
    const [gx, gz] = world.worldToGrid(pt.x, pt.z);
    build.updateHover(gx, gz);
  }
});

// R to rotate in buy mode
window.addEventListener('keydown', (e) => {
  if (e.key.toLowerCase() === 'r' && mode === 'buy') build.rotate();
  if (e.key === 'Escape') {
    if (mode === 'buy' || mode === 'build') setMode('live');
    hidePieMenu();
    hideCareerDialog();
  }
});

// ---------------------------------------------------------------------------
// Build mode callbacks
// ---------------------------------------------------------------------------
build.onPlace = (item, _obj) => {
  household.money -= item.price;
  toast(`Placed ${item.name} (-§${item.price})`, 'good');
  updateHUD();
};
build.onSell = (item, _obj) => {
  const refund = Math.floor(item.price * 0.6);
  household.money += refund;
  toast(`Sold ${item.name} (+§${refund})`, 'good');
  updateHUD();
};
build.onPlaceFail = () => toast("Can't place that here.", 'bad');

// ---------------------------------------------------------------------------
// Pie menu (object interactions)
// ---------------------------------------------------------------------------
function showPieMenu(obj: PlacedObject, px: number, py: number): void {
  const item = obj.group.userData.item as CatalogItem;
  const el = document.getElementById('pie-menu')!;
  el.innerHTML = '';
  el.style.left = `${px}px`;
  el.style.top = `${py}px`;
  if (item.actions.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'pie-item';
    empty.textContent = 'No interactions';
    empty.style.opacity = '0.6';
    el.appendChild(empty);
  }
  for (const action of item.actions) {
    const btn = document.createElement('button');
    btn.className = 'pie-item';
    btn.innerHTML = `${action.name}<span class="pie-need">${action.need}</span>`;
    btn.addEventListener('click', () => {
      hidePieMenu();
      interactWithObject(obj, action.name, action.need, action.rate);
    });
    el.appendChild(btn);
  }
  el.classList.remove('hidden');
  // clamp to viewport
  const r = el.getBoundingClientRect();
  if (r.right > window.innerWidth) el.style.left = `${px - r.width}px`;
  if (r.bottom > window.innerHeight) el.style.top = `${py - r.height}px`;
}

function hidePieMenu(): void {
  document.getElementById('pie-menu')!.classList.add('hidden');
}

function interactWithObject(
  obj: PlacedObject,
  actionName: string,
  need: NeedKey,
  rate: number,
): void {
  if (!selectedSim) {
    toast('Select a sim first (left-click).', 'bad');
    return;
  }
  const item = obj.group.userData.item as CatalogItem;
  const [w, h] = item.footprint;
  const halfH = Math.floor(h / 2);
  const frontGz = obj.gridZ - halfH - 1;
  const duration = Math.min(20, (100 - simNeeds(selectedSim).get(need)) / rate * 60);
  const ok = selectedSim.walkToInteract(obj.gridX, frontGz, actionName, duration);
  if (ok) {
    selectedSim.group.userData.activeNeed = need;
    selectedSim.group.userData.activeRate = rate;
    toast(`${selectedSim.name}: ${actionName}`);
  } else {
    toast("Can't reach that.", 'bad');
  }
}

// click outside pie closes it
window.addEventListener('click', (e) => {
  const el = document.getElementById('pie-menu')!;
  if (!el.classList.contains('hidden') && !el.contains(e.target as Node)) hidePieMenu();
});

// ---------------------------------------------------------------------------
// HUD / UI updates
// ---------------------------------------------------------------------------
function fmtMoney(n: number): string {
  return n.toLocaleString('en-US');
}

function updateHUD(): void {
  document.getElementById('money-val')!.textContent = fmtMoney(household.money);
  document.getElementById('clock-day')!.textContent = `Day ${household.day}`;
  document.getElementById('clock-time')!.textContent = `${
    String(household.hour).padStart(2, '0')
  }:${String(Math.floor(household.minute)).padStart(2, '0')}`;
}

function updateSimPanel(): void {
  const panel = document.getElementById('sim-panel')!;
  if (!selectedSim) {
    panel.classList.add('hidden');
    return;
  }
  panel.classList.remove('hidden');
  document.getElementById('sim-name')!.textContent = selectedSim.name;
  document.getElementById('sim-state')!.textContent = selectedSim.state === 'atWork'
    ? t('ui.hud.working')
    : selectedSim.state === 'interacting'
    ? selectedSim.interactAction
    : selectedSim.state === 'walking'
    ? 'Walking'
    : t('ui.hud.idle');
  const career = simCareer(selectedSim);
  document.getElementById('sim-job')!.textContent = career.title;

  const bars = document.getElementById('needs-bars')!;
  bars.innerHTML = '';
  const needs = simNeeds(selectedSim);
  for (const need of NEEDS) {
    const val = needs.get(need);
    const row = document.createElement('div');
    row.className = 'need-row';
    row.innerHTML = `<span class="need-icon">${NEED_ICONS[need]}</span>` +
      `<div class="need-bar-track"><div class="need-bar-fill" style="width:${val}%;background:${
        hex(NEED_COLORS[need])
      }"></div></div>` +
      `<span class="need-val">${Math.round(val)}</span>`;
    bars.appendChild(row);
  }
}

// ---------------------------------------------------------------------------
// Mode switching
// ---------------------------------------------------------------------------
function setMode(newMode: GameMode): void {
  if (newMode === mode) return;
  if (mode === 'build' || mode === 'buy') build.exit();
  mode = newMode;
  input.buildMode = newMode === 'build' || newMode === 'buy';

  document.getElementById('live-hud')!.classList.toggle('hidden', newMode === 'menu');
  // buy helper toolbar only in buy mode; build tools live in the right-hand catalog
  document.getElementById('buy-bar')!.classList.toggle('hidden', newMode !== 'buy');
  // the single catalog panel shows either build or buy content, never both
  document.getElementById('catalog-panel')!.classList.toggle(
    'hidden',
    newMode !== 'build' && newMode !== 'buy',
  );

  // mode buttons
  document.querySelectorAll<HTMLButtonElement>('.mode-btn').forEach((b) => {
    b.classList.toggle('active', b.dataset.mode === newMode);
  });

  if (newMode === 'build') {
    build.enter();
    build.setTool('wall');
    renderCatalog();
  } else if (newMode === 'buy') {
    build.enter();
    renderCatalog();
  }
}

// ---------------------------------------------------------------------------
// Toasts
// ---------------------------------------------------------------------------
function toast(msg: string, kind: '' | 'good' | 'bad' = ''): void {
  const el = document.getElementById('toasts')!;
  const d = document.createElement('div');
  d.className = 'toast' + (kind ? ' ' + kind : '');
  d.textContent = msg;
  el.appendChild(d);
  setTimeout(() => d.remove(), 3000);
}

// ---------------------------------------------------------------------------
// Catalog UI (shared panel: Buy catalog or Build catalog, never both)
// ---------------------------------------------------------------------------
let catalogCategory = 'All';

interface BuildCatalogEntry {
  id: string;
  name: string;
  type: 'tool' | 'floor' | 'wall';
  icon: string;
  value?: string;
  color?: number;
}

const BUILD_TOOLS: BuildCatalogEntry[] = [
  { id: 'wall', name: 'Wall', type: 'tool', icon: '🧱' },
  { id: 'room', name: 'Room', type: 'tool', icon: '🏠' },
  { id: 'floor', name: 'Floor', type: 'tool', icon: '🟫' },
  { id: 'sell', name: 'Sell', type: 'tool', icon: '💰' },
  { id: 'undo', name: 'Undo', type: 'tool', icon: '↩️' },
  { id: 'redo', name: 'Redo', type: 'tool', icon: '↪️' },
];

const FLOOR_SWATCHES: BuildCatalogEntry[] = Object.entries(FLOOR_MATERIALS).map(([id, color]) => ({
  id: `floor-${id}`,
  name: id.replace(/_/g, ' '),
  type: 'floor',
  icon: '',
  value: id,
  color,
}));

const WALL_SWATCHES: BuildCatalogEntry[] = Object.entries(WALL_MATERIALS).map(([id, color]) => ({
  id: `wall-${id}`,
  name: id.replace(/_/g, ' '),
  type: 'wall',
  icon: '',
  value: id,
  color,
}));

function renderCatalog(): void {
  const titleEl = document.getElementById('catalog-title')!;
  const searchEl = document.getElementById('catalog-search') as HTMLInputElement;
  const catEl = document.getElementById('catalog-cats')!;

  if (mode === 'build') {
    titleEl.textContent = 'Build Catalog';
    searchEl.classList.add('hidden');
    catEl.classList.add('hidden');
    renderBuildCatalog();
  } else {
    titleEl.textContent = 'Buy Catalog';
    searchEl.classList.remove('hidden');
    catEl.classList.remove('hidden');
    renderBuyCatalog();
  }
}

function renderBuyCatalog(): void {
  const cats = ['All', ...Array.from(new Set(CATALOG.map((c) => c.category)))];
  const catEl = document.getElementById('catalog-cats')!;
  catEl.innerHTML = '';
  for (const cat of cats) {
    const chip = document.createElement('button');
    chip.className = 'cat-chip' + (cat === catalogCategory ? ' active' : '');
    chip.textContent = cat;
    chip.addEventListener('click', () => {
      catalogCategory = cat;
      renderCatalog();
    });
    catEl.appendChild(chip);
  }
  const search = (document.getElementById('catalog-search') as HTMLInputElement).value
    .toLowerCase();
  const grid = document.getElementById('catalog-grid')!;
  grid.innerHTML = '';
  const filtered = CATALOG.filter((c) =>
    (catalogCategory === 'All' || c.category === catalogCategory) &&
    (c.name.toLowerCase().includes(search) || c.description.toLowerCase().includes(search))
  );
  for (const item of filtered) {
    const card = document.createElement('div');
    card.className = 'catalog-card';
    if (build.pendingItem?.id === item.id) card.classList.add('selected');
    const needStr = item.actions.length ? item.actions.map((a) => a.need).join(', ') : 'decorative';
    let thumbHTML: string;
    try {
      const url = getThumbnail(item);
      thumbHTML = `<img src="${url}" alt="${item.name}" />`;
    } catch {
      thumbHTML = `<span class="cc-thumb-ph">&#129518;</span>`;
    }
    card.innerHTML = `<div class="cc-thumb">${thumbHTML}</div>` +
      `<div class="cc-name">${item.name}</div>` +
      `<div class="cc-price">§${item.price}</div>` +
      `<div class="cc-needs">${needStr}</div>`;
    card.title = item.description;
    card.addEventListener('click', () => {
      if (household.money < item.price) {
        toast('Not enough money!', 'bad');
        return;
      }
      build.selectBuyItem(item);
      renderCatalog();
      toast(`Selected ${item.name} — click lot to place`);
    });
    grid.appendChild(card);
  }
}

function renderBuildCatalog(): void {
  const grid = document.getElementById('catalog-grid')!;
  grid.innerHTML = '';

  const toolsSection = document.createElement('div');
  toolsSection.className = 'catalog-section';
  toolsSection.textContent = 'Tools';
  grid.appendChild(toolsSection);

  for (const entry of BUILD_TOOLS) {
    const card = makeBuildCard(entry);
    if (entry.type === 'tool' && build.tool === entry.id) card.classList.add('selected');
    card.addEventListener('click', () => {
      if (entry.id === 'undo') {
        build.undo();
        return;
      }
      if (entry.id === 'redo') {
        build.redo();
        return;
      }
      build.setTool(entry.id as BuildTool);
      renderCatalog();
      toast(`${entry.name} tool selected — click lot to use`);
    });
    grid.appendChild(card);
  }

  const floorSection = document.createElement('div');
  floorSection.className = 'catalog-section';
  floorSection.textContent = 'Floor Materials';
  grid.appendChild(floorSection);

  for (const entry of FLOOR_SWATCHES) {
    const card = makeBuildCard(entry);
    if (build.floorMaterial === entry.value) card.classList.add('selected');
    card.addEventListener('click', () => {
      build.floorMaterial = entry.value!;
      build.setTool('floor');
      renderCatalog();
      toast(`Floor material: ${entry.name}`);
    });
    grid.appendChild(card);
  }

  const wallSection = document.createElement('div');
  wallSection.className = 'catalog-section';
  wallSection.textContent = 'Wall Materials';
  grid.appendChild(wallSection);

  for (const entry of WALL_SWATCHES) {
    const card = makeBuildCard(entry);
    if (build.wallMaterial === entry.value) card.classList.add('selected');
    card.addEventListener('click', () => {
      build.wallMaterial = entry.value!;
      renderCatalog();
      toast(`Wall material: ${entry.name}`);
    });
    grid.appendChild(card);
  }
}

function makeBuildCard(entry: BuildCatalogEntry): HTMLElement {
  const card = document.createElement('div');
  card.className = 'catalog-card';
  const colorStyle = entry.color !== undefined ? ` style="background:${hex(entry.color)}"` : '';
  const thumb = entry.type === 'tool'
    ? `<div class="cc-thumb"><span class="cc-thumb-ph">${entry.icon}</span></div>`
    : `<div class="cc-thumb"><div class="cc-swatch"${colorStyle}></div></div>`;
  card.innerHTML = `${thumb}<div class="cc-name">${entry.name}</div>`;
  return card;
}

document.getElementById('catalog-search')!.addEventListener('input', renderCatalog);

// ---------------------------------------------------------------------------
// Buy toolbar UI (build tools now live in the right-hand catalog panel)
// ---------------------------------------------------------------------------
document.querySelectorAll<HTMLButtonElement>('#buy-tools .tool-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    if (btn.dataset.action === 'undo') {
      build.undo();
    } else if (btn.dataset.action === 'rotate') {
      build.rotate();
    } else if (btn.dataset.action === 'clear-buy') {
      build.setTool(null);
      build.selectBuyItem(null as unknown as CatalogItem);
      renderCatalog();
    }
  });
});

// material selects (buy mode — allow painting floors/walls while placing items)
const floorSelBuy = document.getElementById('floor-material-buy') as HTMLSelectElement;
const wallSelBuy = document.getElementById('wall-material-buy') as HTMLSelectElement;
for (const name of Object.keys(FLOOR_MATERIALS)) {
  const opt = document.createElement('option');
  opt.value = name;
  opt.textContent = name.replace(/_/g, ' ');
  floorSelBuy.appendChild(opt);
}
for (const name of Object.keys(WALL_MATERIALS)) {
  const opt = document.createElement('option');
  opt.value = name;
  opt.textContent = name.replace(/_/g, ' ');
  wallSelBuy.appendChild(opt);
}
floorSelBuy.addEventListener('change', () => {
  build.floorMaterial = floorSelBuy.value;
});
wallSelBuy.addEventListener('change', () => {
  build.wallMaterial = wallSelBuy.value;
});

// mode buttons
document.querySelectorAll<HTMLButtonElement>('.mode-btn').forEach((btn) => {
  btn.addEventListener('click', () => setMode(btn.dataset.mode as GameMode));
});

// speed buttons
document.querySelectorAll<HTMLButtonElement>('.speed-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    speed = Number(btn.dataset.speed) as GameSpeed;
    document.querySelectorAll<HTMLButtonElement>('.speed-btn').forEach((b) =>
      b.classList.remove('active')
    );
    btn.classList.add('active');
  });
});

// ---------------------------------------------------------------------------
// Career dialog
// ---------------------------------------------------------------------------
const findJobBtn = document.getElementById('find-job-btn')!;
findJobBtn.addEventListener('click', showCareerDialog);

function showCareerDialog(): void {
  if (!selectedSim) return;
  const list = document.getElementById('career-list')!;
  list.innerHTML = '';
  for (const track of CAREERS) {
    const card = document.createElement('div');
    card.className = 'career-card';
    card.innerHTML = `<div class="career-card-name">${track.name}</div>` +
      `<div class="career-card-levels">${
        track.levels.map((l, i) => i === 0 ? `Start: ${l.title} (§${l.salary}/hr)` : l.title).join(
          ' → ',
        )
      }</div>`;
    card.addEventListener('click', () => {
      if (!selectedSim) return;
      const name = selectedSim.name;
      simCareer(selectedSim).join(track);
      toast(`${name} got a job: ${track.levels[0].title}`, 'good');
      hideCareerDialog();
      updateSimPanel();
    });
    list.appendChild(card);
  }
  document.getElementById('career-dialog')!.classList.remove('hidden');
}
function hideCareerDialog(): void {
  document.getElementById('career-dialog')!.classList.add('hidden');
}
document.getElementById('career-close')!.addEventListener('click', hideCareerDialog);

// ---------------------------------------------------------------------------
// Main menu
// ---------------------------------------------------------------------------
document.querySelectorAll<HTMLButtonElement>('.menu-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    const action = btn.dataset.action;
    const sub = document.getElementById('subtitle')!;
    switch (action) {
      case 'new':
        startGame();
        break;
      case 'load':
        sub.textContent = 'No saved lives yet.';
        sub.classList.add('flash');
        setTimeout(() => sub.classList.remove('flash'), 1200);
        break;
      case 'options':
        sub.textContent = 'Options coming soon.';
        sub.classList.add('flash');
        setTimeout(() => sub.classList.remove('flash'), 1200);
        break;
      case 'credits':
        sub.textContent = 'Just Life — built with Deno + Three.js';
        sub.classList.add('flash');
        setTimeout(() => sub.classList.remove('flash'), 1200);
        break;
      case 'quit':
        sub.textContent = 'Goodbye!';
        sub.classList.add('flash');
        setTimeout(() => window.close(), 800);
        break;
    }
  });
});

function startGame(): void {
  document.getElementById('menu-overlay')!.classList.add('hidden');
  buildStarterLot();
  if (sims.length === 0) spawnSims();
  input.setObjects(objects);
  setMode('live');
  updateHUD();
  toast('Welcome to Just Life! Left-click a sim to select, right-click to move.', 'good');
}

// ---------------------------------------------------------------------------
// Game loop
// ---------------------------------------------------------------------------
const clock = new THREE.Clock();
let needsAccum = 0;
let careerAccum = 0;
let hudAccum = 0;
let autonomyAccum = 0;

function loop(): void {
  const dt = Math.min(clock.getDelta(), 0.1);
  input.update();

  // game time advances by speed multiplier (1x = 1 game-min per real sec)
  if (mode !== 'menu' && speed > 0) {
    const gameMin = dt * speed;
    household.minute += gameMin;
    while (household.minute >= 60) {
      household.minute -= 60;
      household.hour++;
      onHourTick();
      if (household.hour >= 24) {
        household.hour = 0;
        household.day++;
        onDayTick();
      }
    }

    // needs decay (per game minute)
    needsAccum += gameMin;
    if (needsAccum >= 1) {
      const decayDt = needsAccum;
      needsAccum = 0;
      for (const sim of sims) {
        if (sim.state === 'atWork') continue;
        const needs = simNeeds(sim);
        needs.tick(decayDt);
        // active interaction fulfillment
        if (sim.state === 'interacting') {
          const need = sim.group.userData.activeNeed as NeedKey | undefined;
          const rate = sim.group.userData.activeRate as number | undefined;
          if (need && rate) needs.fulfill(need, rate, decayDt);
        }
      }
    }

    // career: pay while at work
    careerAccum += gameMin;
    if (careerAccum >= 1) {
      const cdt = careerAccum;
      careerAccum = 0;
      for (const sim of sims) {
        const career = simCareer(sim);
        const dow = household.dayOfWeek();
        if (career.shouldWorkNow(dow, household.hour)) {
          if (sim.state !== 'atWork') {
            sim.state = 'atWork';
            toast(`${sim.name} went to work as ${career.title}.`);
          }
          const pay = career.work(cdt);
          household.money += Math.round(pay);
        } else {
          if (sim.state === 'atWork') sim.state = 'idle';
        }
      }
    }

    // autonomy (throttled)
    autonomyAccum += dt;
    if (autonomyAccum >= 0.2) {
      const adt = autonomyAccum;
      autonomyAccum = 0;
      for (let i = 0; i < sims.length; i++) {
        const result = autonomyTick(sims[i], simNeeds(sims[i]), objects, autonomyStates[i], adt);
        if (result) toast(`${sims[i].name}: ${result}`);
      }
    }
  }

  // update sims (movement/animation)
  for (const sim of sims) sim.update(dt);

  // HUD refresh
  hudAccum += dt;
  if (hudAccum >= 0.25) {
    hudAccum = 0;
    if (mode !== 'menu') {
      updateHUD();
      if (selectedSim) updateSimPanel();
    }
  }

  updateCamera(ctx.camera);
  ctx.renderer.render(ctx.scene, ctx.camera);
  requestAnimationFrame(loop);
}

function onHourTick(): void {}

function onDayTick(): void {
  // promotion check for each working sim
  for (const sim of sims) {
    const career = simCareer(sim);
    if (career.track) {
      const promoted = career.maybePromote();
      if (promoted) toast(`Promoted! ${sim.name} is now ${career.title}.`, 'good');
    }
  }
  // daily bills
  const bills = 50;
  household.money -= bills;
  toast(`Bills: -§${bills}`, 'bad');
}

loop();
