// Just Life — input: raycaster for left-click select, right-click move,
// right-click object → pie menu. Camera controls (scroll zoom, Q/E rotate,
// WASD/middle-drag pan).
import * as THREE from 'three';
import type { Sim } from './sim.ts';
import type { PlacedObject } from './types.ts';
import { World } from './world.ts';

export interface InputCallbacks {
  onSelectSim: (sim: Sim | null) => void;
  onMoveSim: (gx: number, gz: number) => void;
  onObjectClick: (obj: PlacedObject, gx: number, gz: number) => void;
  onGroundRightClick: (gx: number, gz: number) => void;
  onPieMenu: (obj: PlacedObject, x: number, y: number) => void;
}

export class Input {
  raycaster = new THREE.Raycaster();
  pointer = new THREE.Vector2();
  sims: Sim[];
  world: World;
  camera: THREE.PerspectiveCamera;
  canvas: HTMLCanvasElement;
  cb: InputCallbacks;
  selected: Sim | null = null;
  objects: PlacedObject[];
  buildMode = false;

  // middle-drag panning
  private panning = false;
  private lastX = 0;
  private lastY = 0;
  // keys
  private keys = new Set<string>();

  constructor(
    canvas: HTMLCanvasElement,
    camera: THREE.PerspectiveCamera,
    world: World,
    sims: Sim[],
    objects: PlacedObject[],
    cb: InputCallbacks,
  ) {
    this.canvas = canvas;
    this.camera = camera;
    this.world = world;
    this.sims = sims;
    this.objects = objects;
    this.cb = cb;
    this.bind();
  }

  setObjects(objects: PlacedObject[]): void {
    this.objects = objects;
  }

  private ndc(event: MouseEvent): THREE.Vector2 {
    const rect = this.canvas.getBoundingClientRect();
    this.pointer.set(
      ((event.clientX - rect.left) / rect.width) * 2 - 1,
      -((event.clientY - rect.top) / rect.height) * 2 + 1,
    );
    return this.pointer;
  }

  private raycastGround(): [number, number] | null {
    this.raycaster.setFromCamera(this.pointer, this.camera);
    // intersect the ground plane y=0
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    const point = new THREE.Vector3();
    if (this.raycaster.ray.intersectPlane(plane, point)) {
      return this.world.worldToGrid(point.x, point.z);
    }
    return null;
  }

  private raycastSims(): Sim | null {
    this.raycaster.setFromCamera(this.pointer, this.camera);
    let closest: Sim | null = null;
    let closestDist = Infinity;
    for (const sim of this.sims) {
      const hits = this.raycaster.intersectObject(sim.group, true);
      if (hits.length && hits[0].distance < closestDist) {
        closestDist = hits[0].distance;
        closest = sim;
      }
    }
    return closest;
  }

  private raycastObject(): { obj: PlacedObject; point: THREE.Vector3 } | null {
    this.raycaster.setFromCamera(this.pointer, this.camera);
    let closestObj: PlacedObject | null = null;
    let closestDist = Infinity;
    let hitPoint = new THREE.Vector3();
    for (const obj of this.objects) {
      const hits = this.raycaster.intersectObject(obj.group, true);
      if (hits.length && hits[0].distance < closestDist) {
        closestDist = hits[0].distance;
        closestObj = obj;
        hitPoint = hits[0].point;
      }
    }
    return closestObj ? { obj: closestObj, point: hitPoint } : null;
  }

  private bind(): void {
    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());

    this.canvas.addEventListener('mousedown', (e) => {
      if (e.button === 1) {
        this.panning = true;
        this.lastX = e.clientX;
        this.lastY = e.clientY;
        return;
      }
    });

    window.addEventListener('mouseup', (e) => {
      if (e.button === 1) this.panning = false;
    });

    this.canvas.addEventListener('mousemove', (e) => {
      if (this.panning) {
        const dx = e.clientX - this.lastX;
        const dy = e.clientY - this.lastY;
        this.lastX = e.clientX;
        this.lastY = e.clientY;
        // import panCam lazily to avoid circular deps at module-eval time
        import('./scene.ts').then(({ panCam }) => panCam(-dx * 0.05, dy * 0.05));
        return;
      }
    });

    this.canvas.addEventListener('click', (e) => {
      if (this.buildMode) return; // build mode handles its own clicks
      this.ndc(e);
      // left click: select sim (or deselect)
      const sim = this.raycastSims();
      if (sim) {
        this.selectSim(sim);
        return;
      }
      // clicked an object? open pie menu too on left? No — left deselects.
      this.selectSim(null);
    });

    this.canvas.addEventListener('contextmenu_prevent', () => {});

    this.canvas.addEventListener('mousedown', (e) => {
      if (e.button !== 2) return;
      if (this.buildMode) return;
      this.ndc(e);
      // right-click object → pie menu
      const hit = this.raycastObject();
      if (hit) {
        this.cb.onPieMenu(hit.obj, e.clientX, e.clientY);
        return;
      }
      // right-click ground → move selected sim
      const cell = this.raycastGround();
      if (cell) {
        if (this.selected) {
          this.cb.onMoveSim(cell[0], cell[1]);
        } else {
          this.cb.onGroundRightClick(cell[0], cell[1]);
        }
      }
    });

    // wheel zoom
    this.canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      import('./scene.ts').then(({ zoomCam }) => zoomCam(e.deltaY * 0.01));
    }, { passive: false });

    // keyboard
    window.addEventListener('keydown', (e) => {
      this.keys.add(e.key.toLowerCase());
      if (e.key.toLowerCase() === 'q') import('./scene.ts').then(({ rotateCam }) => rotateCam(-1));
      if (e.key.toLowerCase() === 'e') import('./scene.ts').then(({ rotateCam }) => rotateCam(1));
    });
    window.addEventListener('keyup', (e) => {
      this.keys.delete(e.key.toLowerCase());
    });
  }

  selectSim(sim: Sim | null): void {
    if (this.selected) this.selected.setSelected(false);
    this.selected = sim;
    if (sim) sim.setSelected(true);
    this.cb.onSelectSim(sim);
  }

  // called each frame for WASD pan
  update(): void {
    if (this.keys.has('w') || this.keys.has('arrowup')) {
      import('./scene.ts').then(({ panCam }) => panCam(0, -0.25));
    }
    if (this.keys.has('s') || this.keys.has('arrowdown')) {
      import('./scene.ts').then(({ panCam }) => panCam(0, 0.25));
    }
    if (this.keys.has('a') || this.keys.has('arrowleft')) {
      import('./scene.ts').then(({ panCam }) => panCam(-0.25, 0));
    }
    if (this.keys.has('d') || this.keys.has('arrowright')) {
      import('./scene.ts').then(({ panCam }) => panCam(0.25, 0));
    }
  }
}
