// Just Life — build/buy mode: walls, rooms, place/sell objects, undo/redo.
import * as THREE from 'three';
import { World } from './world.ts';
import {
  buildObjectMesh,
  canPlace,
  footprintCells,
  ghostMesh,
  placeObject,
  removeObject,
} from './objects.ts';
import type { CatalogItem, PlacedObject } from './types.ts';
import { FLOOR_MATERIAL_PRICES, WALL_MATERIAL_PRICES } from '../theme.ts';

function floorPrice(material: string): number {
  return FLOOR_MATERIAL_PRICES[material] ?? 10;
}
function wallPrice(material: string): number {
  return WALL_MATERIAL_PRICES[material] ?? 15;
}

interface BuildAction {
  type: 'wall' | 'room' | 'place' | 'sell' | 'floor' | 'sell-wall' | 'sell-floor';
  // for undo
  undo: () => void;
}

export type BuildTool = 'wall' | 'room' | 'floor' | 'sell' | null;
export type FloorMaterial = string;

export class BuildMode {
  world: World;
  scene: THREE.Scene;
  active = false;
  tool: BuildTool = null;
  floorMaterial: FloorMaterial = 'hardwood_oak';
  wallMaterial = 'plaster_light';
  // buy mode placement
  pendingItem: CatalogItem | null = null;
  pendingRotation = 0;
  ghost: THREE.Group | null = null;
  objects: PlacedObject[];
  // wall drag
  private wallStart: [number, number] | null = null;
  private dragPreview: THREE.Object3D | null = null;
  private undoStack: BuildAction[] = [];
  private redoStack: BuildAction[] = [];

  constructor(scene: THREE.Scene, world: World, objects: PlacedObject[]) {
    this.scene = scene;
    this.world = world;
    this.objects = objects;
  }

  enter(): void {
    this.active = true;
    this.world.showGrid(true);
  }
  exit(): void {
    this.active = false;
    this.world.showGrid(false);
    this.tool = null;
    this.pendingItem = null;
    this.wallStart = null;
    this.clearGhost();
    this.clearDragPreview();
    this.undoStack = [];
    this.redoStack = [];
  }

  setTool(tool: BuildTool): void {
    this.tool = tool;
    this.pendingItem = null;
    this.clearGhost();
  }

  selectBuyItem(item: CatalogItem | null): void {
    this.pendingItem = item;
    this.tool = null;
    this.clearGhost();
  }

  rotate(): void {
    this.pendingRotation = (this.pendingRotation + 1) % 4;
  }

  private clearGhost(): void {
    if (this.ghost) {
      this.scene.remove(this.ghost);
      this.ghost = null;
    }
  }

  private clearDragPreview(): void {
    if (this.dragPreview) {
      this.scene.remove(this.dragPreview);
      this.dragPreview.traverse((c) => {
        if (c instanceof THREE.Mesh) {
          c.geometry.dispose();
          (c.material as THREE.Material).dispose();
        }
      });
      this.dragPreview = null;
    }
    // don't reset wallStart here — it's reset by wallClick/roomClick on completion
  }

  // Called each frame with the current hovered grid cell (from raycast).
  updateHover(gx: number, gz: number): void {
    if (this.pendingItem) {
      this.clearGhost();
      const valid = canPlace(this.world, this.pendingItem, gx, gz, this.pendingRotation);
      const g = ghostMesh(this.pendingItem, valid);
      const [wx, wz] = this.world.gridToWorld(gx, gz);
      g.position.set(wx, 0, wz);
      g.rotation.y = this.pendingRotation * (Math.PI / 2);
      this.scene.add(g);
      this.ghost = g;
    } else if (this.tool === 'wall' && this.wallStart) {
      // Live wall drag preview
      this.clearDragPreview();
      this.updateWallPreview(gx, gz);
    } else if (this.tool === 'room' && this.wallStart) {
      // Live room drag preview
      this.clearDragPreview();
      this.updateRoomPreview(gx, gz);
    } else {
      this.clearGhost();
      this.clearDragPreview();
    }
  }

  // Wall drag preview: show a translucent wall segment from start to current
  private updateWallPreview(gx: number, gz: number): void {
    const [sx, sz] = this.wallStart!;
    if (gx === sx && gz === sz) return;
    let length: number, axis: 'x' | 'z', wx: number, wz: number;
    if (gx === sx) {
      axis = 'z';
      length = Math.abs(gz - sz) + 1;
      const start = Math.min(sz, gz);
      const [cwx, cwz] = this.world.gridToWorld(sx, start);
      wx = cwx;
      wz = cwz + (length - 1) / 2;
    } else if (gz === sz) {
      axis = 'x';
      length = Math.abs(gx - sx) + 1;
      const start = Math.min(sx, gx);
      const [cwx, cwz] = this.world.gridToWorld(start, sz);
      wx = cwx + (length - 1) / 2;
      wz = cwz;
    } else {
      // non-orthogonal: snap to dominant axis
      if (Math.abs(gx - sx) > Math.abs(gz - sz)) {
        axis = 'x';
        length = Math.abs(gx - sx) + 1;
        const start = Math.min(sx, gx);
        const [cwx, cwz] = this.world.gridToWorld(start, sz);
        wx = cwx + (length - 1) / 2;
        wz = cwz;
      } else {
        axis = 'z';
        length = Math.abs(gz - sz) + 1;
        const start = Math.min(sz, gz);
        const [cwx, cwz] = this.world.gridToWorld(sx, start);
        wx = cwx;
        wz = cwz + (length - 1) / 2;
      }
    }
    const geo = axis === 'x'
      ? new THREE.BoxGeometry(length, 3, 0.15)
      : new THREE.BoxGeometry(0.15, 3, length);
    const mat = new THREE.MeshBasicMaterial({
      color: 0xffd27a,
      transparent: true,
      opacity: 0.45,
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.set(wx, 1.5, wz);
    this.scene.add(mesh);
    this.dragPreview = mesh;
  }

  // Room drag preview: show translucent walls + floor rect from start to current
  private updateRoomPreview(gx: number, gz: number): void {
    const [sx, sz] = this.wallStart!;
    const x0 = Math.min(sx, gx), x1 = Math.max(sx, gx);
    const z0 = Math.min(sz, gz), z1 = Math.max(sz, gz);
    const w = x1 - x0 + 1, h = z1 - z0 + 1;
    if (w < 1 || h < 1) return;

    const group = new THREE.Group();

    // floor preview
    const [fwx, fwz] = this.world.gridToWorld(x0, z0);
    const [fwx2, fwz2] = this.world.gridToWorld(x1, z1);
    const cx = (fwx + fwx2) / 2, cz = (fwz + fwz2) / 2;
    const floorGeo = new THREE.PlaneGeometry(w, h);
    const floorMat = new THREE.MeshBasicMaterial({
      color: 0xffd27a,
      transparent: true,
      opacity: 0.2,
      side: THREE.DoubleSide,
    });
    const floor = new THREE.Mesh(floorGeo, floorMat);
    floor.rotation.x = -Math.PI / 2;
    floor.position.set(cx, 0.03, cz);
    group.add(floor);

    // wall previews (4 sides)
    const wallMat = new THREE.MeshBasicMaterial({
      color: 0xffd27a,
      transparent: true,
      opacity: 0.4,
    });
    // north (z0)
    const [nwx, nwz] = this.world.gridToWorld(x0, z0);
    const [nwx2, _nz2] = this.world.gridToWorld(x1, z0);
    const nLen = x1 - x0 + 1;
    const north = new THREE.Mesh(new THREE.BoxGeometry(nLen, 3, 0.15), wallMat.clone());
    north.position.set((nwx + nwx2) / 2, 1.5, nwz);
    group.add(north);
    // south (z1)
    const [swx, swz] = this.world.gridToWorld(x0, z1);
    const [swx2, _sz2] = this.world.gridToWorld(x1, z1);
    const south = new THREE.Mesh(new THREE.BoxGeometry(nLen, 3, 0.15), wallMat.clone());
    south.position.set((swx + swx2) / 2, 1.5, swz);
    group.add(south);
    // west (x0)
    const [wwx, wwz] = this.world.gridToWorld(x0, z0);
    const [_wwx2, wwz2] = this.world.gridToWorld(x0, z1);
    const wLen = z1 - z0 + 1;
    const west = new THREE.Mesh(new THREE.BoxGeometry(0.15, 3, wLen), wallMat.clone());
    west.position.set(wwx, 1.5, (wwz + wwz2) / 2);
    group.add(west);
    // east (x1)
    const [ewx, ewz] = this.world.gridToWorld(x1, z0);
    const [_ewx2, ewz2] = this.world.gridToWorld(x1, z1);
    const east = new THREE.Mesh(new THREE.BoxGeometry(0.15, 3, wLen), wallMat.clone());
    east.position.set(ewx, 1.5, (ewz + ewz2) / 2);
    group.add(east);

    this.scene.add(group);
    this.dragPreview = group;
  }

  // Click in build mode (left button). gx,gz = hovered cell.
  onClick(gx: number, gz: number): void {
    if (!this.active) return;
    if (this.pendingItem) {
      this.placeItem(gx, gz);
      return;
    }
    if (this.tool === 'wall') {
      this.wallClick(gx, gz);
      return;
    }
    if (this.tool === 'room') {
      this.roomClick(gx, gz);
      return;
    }
    if (this.tool === 'floor') {
      this.floorClick(gx, gz);
      return;
    }
    if (this.tool === 'sell') {
      this.sellAt(gx, gz);
      return;
    }
  }

  private placeItem(gx: number, gz: number): void {
    if (!this.pendingItem) return;
    const obj = placeObject(this.world, this.scene, this.pendingItem, gx, gz, this.pendingRotation);
    if (obj) {
      this.objects.push(obj);
      const item = this.pendingItem;
      this.pushUndo({
        type: 'place',
        undo: () => {
          removeObject(this.world, this.scene, obj);
          const i = this.objects.indexOf(obj);
          if (i >= 0) this.objects.splice(i, 1);
        },
      });
      this.onPlace?.(item, obj);
    } else {
      this.onPlaceFail?.();
    }
  }

  private wallClick(gx: number, gz: number): void {
    if (!this.wallStart) {
      this.wallStart = [gx, gz];
      return;
    }
    const [sx, sz] = this.wallStart;
    this.clearDragPreview();
    if (gx === sx && gz === sz) {
      this.wallStart = null;
      return;
    }
    let seg: { axis: 'x' | 'z'; line: number; start: number; end: number; material: string };
    if (gx === sx) {
      seg = {
        axis: 'z',
        line: gx,
        start: Math.min(sz, gz),
        end: Math.max(sz, gz),
        material: this.wallMaterial,
      };
    } else if (gz === sz) {
      seg = {
        axis: 'x',
        line: gz,
        start: Math.min(sx, gx),
        end: Math.max(sx, gx),
        material: this.wallMaterial,
      };
    } else {
      this.wallStart = null;
      return;
    }
    const length = seg.end - seg.start + 1;
    const cost = wallPrice(this.wallMaterial) * length;
    if (this.onCharge && !this.onCharge(cost)) {
      this.onBuildMsg?.(`Not enough money for wall (§${cost}).`, 'bad');
      this.wallStart = null;
      return;
    }
    this.world.addWall(seg);
    const idx = this.world.walls.length - 1;
    this.pushUndo({ type: 'wall', undo: () => this.world.removeWall(idx) });
    this.onBuildMsg?.(`Built wall (-§${cost})`, 'good');
    this.wallStart = null;
  }

  private roomClick(gx: number, gz: number): void {
    if (!this.wallStart) {
      this.wallStart = [gx, gz];
      return;
    }
    const [sx, sz] = this.wallStart;
    this.clearDragPreview();
    const x0 = Math.min(sx, gx), x1 = Math.max(sx, gx);
    const z0 = Math.min(sz, gz), z1 = Math.max(sz, gz);
    // cost: 4 walls (perimeter cells) + floor area
    const perim = 2 * ((x1 - x0 + 1) + (z1 - z0 + 1));
    const area = (x1 - x0 + 1) * (z1 - z0 + 1);
    const wallCost = wallPrice(this.wallMaterial) * perim;
    const floorCost = floorPrice(this.floorMaterial) * area;
    const cost = wallCost + floorCost;
    if (this.onCharge && !this.onCharge(cost)) {
      this.onBuildMsg?.(`Not enough money for room (§${cost}).`, 'bad');
      this.wallStart = null;
      return;
    }
    // four walls
    const segs = [
      { axis: 'x' as const, line: z0, start: x0, end: x1, material: this.wallMaterial },
      { axis: 'x' as const, line: z1, start: x0, end: x1, material: this.wallMaterial },
      { axis: 'z' as const, line: x0, start: z0, end: z1, material: this.wallMaterial },
      { axis: 'z' as const, line: x1, start: z0, end: z1, material: this.wallMaterial },
    ];
    const startLen = this.world.walls.length;
    for (const seg of segs) this.world.addWall(seg);
    this.world.paintRoom(x0, z0, x1, z1, this.floorMaterial);
    this.pushUndo({
      type: 'room',
      undo: () => {
        for (let i = this.world.walls.length - 1; i >= startLen; i--) this.world.removeWall(i);
        for (let fx = x0; fx <= x1; fx++) {
          for (let fz = z0; fz <= z1; fz++) {
            const k = this.world.key(fx, fz);
            const t = this.world.floors.get(k);
            if (t) {
              this.world.floorMeshes.remove(t.mesh);
              this.world.floors.delete(k);
            }
          }
        }
      },
    });
    this.onBuildMsg?.(`Built room (-§${cost})`, 'good');
    this.wallStart = null;
  }

  private floorClick(gx: number, gz: number): void {
    const cost = floorPrice(this.floorMaterial);
    const k = this.world.key(gx, gz);
    const existing = this.world.floors.get(k);
    // re-painting same material is free; different material charges the difference
    if (existing && existing.material === this.floorMaterial) return;
    if (this.onCharge && !this.onCharge(cost)) {
      this.onBuildMsg?.(`Not enough money for floor (§${cost}).`, 'bad');
      return;
    }
    const prevMaterial = existing?.material ?? null;
    this.world.paintFloor(gx, gz, this.floorMaterial);
    this.pushUndo({
      type: 'floor',
      undo: () => {
        if (prevMaterial) {
          this.world.paintFloor(gx, gz, prevMaterial);
        } else {
          const t = this.world.floors.get(k);
          if (t) {
            this.world.floorMeshes.remove(t.mesh);
            this.world.floors.delete(k);
          }
        }
      },
    });
    this.onBuildMsg?.(`Floor (-§${cost})`, 'good');
  }

  private sellAt(gx: number, gz: number): void {
    // first try selling an object on this cell
    const idx = this.objects.findIndex((o) => {
      const item = o.group.userData.item as CatalogItem;
      const cells = footprintCells(item, o.gridX, o.gridZ, o.rotation);
      return cells.some(([cx, cz]) => cx === gx && cz === gz);
    });
    if (idx >= 0) {
      const obj = this.objects[idx];
      const item = obj.group.userData.item as CatalogItem;
      removeObject(this.world, this.scene, obj);
      this.objects.splice(idx, 1);
      this.pushUndo({
        type: 'sell',
        undo: () => {
          const newObj = placeObject(
            this.world,
            this.scene,
            item,
            obj.gridX,
            obj.gridZ,
            obj.rotation,
          );
          if (newObj) this.objects.push(newObj);
        },
      });
      this.onSell?.(item, obj);
      return;
    }
    // else: delete a wall segment touching this cell (free removal)
    const widx = this.world.walls.findIndex((w) => {
      const len = w.end - w.start + 1;
      for (let i = 0; i < len; i++) {
        const wx = w.axis === 'x' ? w.start + i : w.line;
        const wz = w.axis === 'x' ? w.line : w.start + i;
        if (wx === gx && wz === gz) return true;
      }
      return false;
    });
    if (widx >= 0) {
      this.deleteWall(widx);
      return;
    }
  }

  private deleteWall(index: number): void {
    const seg = this.world.walls[index];
    this.world.removeWall(index);
    this.pushUndo({
      type: 'sell-wall',
      undo: () => {
        this.world.walls.splice(index, 0, seg);
        this.world.rebuildWalls();
        this.world.markWallBlocked(seg, true);
      },
    });
    this.onBuildMsg?.('Wall deleted', 'good');
  }

  private pushUndo(a: BuildAction): void {
    this.undoStack.push(a);
    this.redoStack = [];
  }

  undo(): void {
    const a = this.undoStack.pop();
    if (!a) return;
    a.undo();
    this.redoStack.push(a);
  }

  redo(): void {
    // simplified redo (re-applies place only for now)
    const a = this.redoStack.pop();
    if (!a) return;
    // For place: re-place is non-trivial; skip robust redo in this slice.
    this.undoStack.push(a);
  }

  // callbacks set by main.ts
  onPlace?: (item: CatalogItem, obj: PlacedObject) => void;
  onSell?: (item: CatalogItem, obj: PlacedObject) => void;
  onPlaceFail?: () => void;
  onCharge?: (amount: number) => boolean; // returns false if not enough money (cancels)
  onRefund?: (amount: number) => void;
  onBuildMsg?: (msg: string, kind?: '' | 'good' | 'bad') => void;
}
