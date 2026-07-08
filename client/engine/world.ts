// Just Life — world: lot grid, ground, walls, floors, rooms, grid overlay.
import * as THREE from "three";
import { THEME, FLOOR_MATERIALS, WALL_MATERIALS } from "../theme.ts";

export const LOT_W = 20; // grid cells wide
export const LOT_H = 20; // grid cells deep
export const CELL = 1.0; // world units per cell

export interface WallSegment {
  // axis: 'x' runs along x at fixed z; 'z' runs along z at fixed x
  axis: "x" | "z";
  // grid coordinate of the wall line (z for x-walls, x for z-walls)
  line: number;
  // start cell index along the axis (inclusive)
  start: number;
  // end cell index along the axis (inclusive)
  end: number;
  material: string;
}

export interface FloorTile {
  gridX: number;
  gridZ: number;
  material: string;
  mesh: THREE.Mesh;
}

export class World {
  scene: THREE.Scene;
  ground: THREE.Mesh;
  gridOverlay: THREE.LineSegments;
  walls: WallSegment[] = [];
  wallMeshes: THREE.Group = new THREE.Group();
  floors: Map<string, FloorTile> = new Map();
  floorMeshes: THREE.Group = new THREE.Group();
  // Occupancy grid: cell → "wall" | "object:<id>" | null
  blocked: Map<string, boolean> = new Map();

  constructor(scene: THREE.Scene) {
    this.scene = scene;

    // Ground / lot base
    this.ground = new THREE.Mesh(
      new THREE.BoxGeometry(LOT_W * CELL, 0.5, LOT_H * CELL),
      new THREE.MeshStandardMaterial({ color: THEME.grass, roughness: 0.95 }),
    );
    this.ground.position.set(0, -0.25, 0);
    this.ground.receiveShadow = true;
    scene.add(this.ground);

    // Grass skirt
    const skirt = new THREE.Mesh(
      new THREE.BoxGeometry((LOT_W + 4) * CELL, 0.2, (LOT_H + 4) * CELL),
      new THREE.MeshStandardMaterial({ color: THEME.grassDark, roughness: 1 }),
    );
    skirt.position.set(0, -0.55, 0);
    skirt.receiveShadow = true;
    scene.add(skirt);

    // Grid overlay (hidden until build mode)
    const geo = new THREE.BufferGeometry();
    const pts: number[] = [];
    const halfW = (LOT_W * CELL) / 2;
    const halfH = (LOT_H * CELL) / 2;
    for (let i = 0; i <= LOT_W; i++) {
      const x = -halfW + i * CELL;
      pts.push(x, 0.02, -halfH, x, 0.02, halfH);
    }
    for (let j = 0; j <= LOT_H; j++) {
      const z = -halfH + j * CELL;
      pts.push(-halfW, 0.02, z, halfW, 0.02, z);
    }
    geo.setAttribute("position", new THREE.Float32BufferAttribute(pts, 3));
    this.gridOverlay = new THREE.LineSegments(
      geo,
      new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.25 }),
    );
    this.gridOverlay.visible = false;
    scene.add(this.gridOverlay);

    scene.add(this.wallMeshes);
    scene.add(this.floorMeshes);
  }

  showGrid(show: boolean): void {
    this.gridOverlay.visible = show;
  }

  // --- Coordinate helpers ---
  // world x,z → grid cell (0..LOT_W-1)
  worldToGrid(x: number, z: number): [number, number] {
    const gx = Math.floor(x + (LOT_W * CELL) / 2);
    const gz = Math.floor(z + (LOT_H * CELL) / 2);
    return [gx, gz];
  }

  // grid cell → world center x,z
  gridToWorld(gx: number, gz: number): [number, number] {
    const x = gx - (LOT_W * CELL) / 2 + CELL / 2;
    const z = gz - (LOT_H * CELL) / 2 + CELL / 2;
    return [x, z];
  }

  inBounds(gx: number, gz: number): boolean {
    return gx >= 0 && gx < LOT_W && gz >= 0 && gz < LOT_H;
  }

  key(gx: number, gz: number): string {
    return `${gx},${gz}`;
  }

  isBlocked(gx: number, gz: number): boolean {
    return this.blocked.get(this.key(gx, gz)) === true;
  }

  setBlocked(gx: number, gz: number, v: boolean): void {
    this.blocked.set(this.key(gx, gz), v);
  }

  // --- Walls ---
  addWall(seg: WallSegment): void {
    this.walls.push(seg);
    this.rebuildWalls();
    this.markWallBlocked(seg, true);
  }

  removeWall(index: number): void {
    const seg = this.walls[index];
    this.markWallBlocked(seg, false);
    this.walls.splice(index, 1);
    this.rebuildWalls();
  }

  private markWallBlocked(seg: WallSegment, blocked: boolean): void {
    const len = seg.end - seg.start + 1;
    for (let i = 0; i < len; i++) {
      if (seg.axis === "x") {
        this.setBlocked(seg.start + i, seg.line, blocked);
      } else {
        this.setBlocked(seg.line, seg.start + i, blocked);
      }
    }
  }

  rebuildWalls(): void {
    this.wallMeshes.clear();
    const wallColor = WALL_MATERIALS.plaster_light;
    for (const seg of this.walls) {
      const len = seg.end - seg.start + 1;
      const color = WALL_MATERIALS[seg.material] ?? wallColor;
      const mat = new THREE.MeshStandardMaterial({ color, roughness: 0.85 });
      if (seg.axis === "x") {
        const [wx, wz] = this.gridToWorld(seg.start, seg.line);
        const mesh = new THREE.Mesh(new THREE.BoxGeometry(len * CELL, 3, 0.15), mat);
        mesh.position.set(wx + (len - 1) * CELL / 2, 1.5, wz);
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        this.wallMeshes.add(mesh);
      } else {
        const [wx, wz] = this.gridToWorld(seg.line, seg.start);
        const mesh = new THREE.Mesh(new THREE.BoxGeometry(0.15, 3, len * CELL), mat);
        mesh.position.set(wx, 1.5, wz + (len - 1) * CELL / 2);
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        this.wallMeshes.add(mesh);
      }
    }
  }

  // --- Floors ---
  paintFloor(gx: number, gz: number, material: string): void {
    const k = this.key(gx, gz);
    const existing = this.floors.get(k);
    if (existing) this.floorMeshes.remove(existing.mesh);
    const color = FLOOR_MATERIALS[material] ?? FLOOR_MATERIALS.hardwood_oak;
    const mesh = new THREE.Mesh(
      new THREE.BoxGeometry(CELL, 0.05, CELL),
      new THREE.MeshStandardMaterial({ color, roughness: 0.8 }),
    );
    const [wx, wz] = this.gridToWorld(gx, gz);
    mesh.position.set(wx, 0.03, wz);
    mesh.receiveShadow = true;
    this.floorMeshes.add(mesh);
    this.floors.set(k, { gridX: gx, gridZ: gz, material, mesh });
  }

  paintRoom(gx0: number, gz0: number, gx1: number, gz1: number, material: string): void {
    const x0 = Math.min(gx0, gx1), x1 = Math.max(gx0, gx1);
    const z0 = Math.min(gz0, gz1), z1 = Math.max(gz0, gz1);
    for (let gx = x0; gx <= x1; gx++) {
      for (let gz = z0; gz <= z1; gz++) {
        this.paintFloor(gx, gz, material);
      }
    }
  }
}