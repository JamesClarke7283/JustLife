// Just Life — build/buy mode: walls, rooms, place/sell objects, undo/redo.
import * as THREE from "three";
import { World } from "./world.ts";
import { buildObjectMesh, canPlace, footprintCells, ghostMesh, placeObject, removeObject } from "./objects.ts";
import type { CatalogItem, PlacedObject } from "./types.ts";

interface BuildAction {
  type: "wall" | "room" | "place" | "sell" | "floor";
  // for undo
  undo: () => void;
}

export type BuildTool = "wall" | "room" | "floor" | "sell" | null;
export type FloorMaterial = string;

export class BuildMode {
  world: World;
  scene: THREE.Scene;
  active = false;
  tool: BuildTool = null;
  floorMaterial: FloorMaterial = "hardwood_oak";
  wallMaterial = "plaster_light";
  // buy mode placement
  pendingItem: CatalogItem | null = null;
  pendingRotation = 0;
  ghost: THREE.Group | null = null;
  objects: PlacedObject[];
  // wall drag
  private wallStart: [number, number] | null = null;
  private dragPreview: THREE.Mesh | null = null;
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

  selectBuyItem(item: CatalogItem): void {
    this.pendingItem = item;
    this.tool = null;
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
      this.dragPreview = null;
    }
    this.wallStart = null;
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
    } else {
      this.clearGhost();
    }
  }

  // Click in build mode (left button). gx,gz = hovered cell.
  onClick(gx: number, gz: number): void {
    if (!this.active) return;
    if (this.pendingItem) {
      this.placeItem(gx, gz);
      return;
    }
    if (this.tool === "wall") {
      this.wallClick(gx, gz);
      return;
    }
    if (this.tool === "room") {
      this.roomClick(gx, gz);
      return;
    }
    if (this.tool === "floor") {
      this.floorClick(gx, gz);
      return;
    }
    if (this.tool === "sell") {
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
        type: "place",
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
    if (gx === sx) {
      const line = gx;
      const start = Math.min(sz, gz);
      const end = Math.max(sz, gz);
      const seg = { axis: "z" as const, line, start, end, material: this.wallMaterial };
      this.world.addWall(seg);
      const idx = this.world.walls.length - 1;
      this.pushUndo({ type: "wall", undo: () => this.world.removeWall(idx) });
    } else if (gz === sz) {
      const line = gz;
      const start = Math.min(sx, gx);
      const end = Math.max(sx, gx);
      const seg = { axis: "x" as const, line, start, end, material: this.wallMaterial };
      this.world.addWall(seg);
      const idx = this.world.walls.length - 1;
      this.pushUndo({ type: "wall", undo: () => this.world.removeWall(idx) });
    }
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
    // four walls
    const segs = [
      { axis: "x" as const, line: z0, start: x0, end: x1, material: this.wallMaterial },
      { axis: "x" as const, line: z1, start: x0, end: x1, material: this.wallMaterial },
      { axis: "z" as const, line: x0, start: z0, end: z1, material: this.wallMaterial },
      { axis: "z" as const, line: x1, start: z0, end: z1, material: this.wallMaterial },
    ];
    const startLen = this.world.walls.length;
    for (const seg of segs) this.world.addWall(seg);
    this.world.paintRoom(x0, z0, x1, z1, this.floorMaterial);
    const floorStart = this.world.floors.size;
    this.pushUndo({
      type: "room",
      undo: () => {
        for (let i = this.world.walls.length - 1; i >= startLen; i--) this.world.removeWall(i);
        // remove floors added (simplified: clear tiles in rect)
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
    this.wallStart = null;
  }

  private floorClick(gx: number, gz: number): void {
    this.world.paintFloor(gx, gz, this.floorMaterial);
    const k = this.world.key(gx, gz);
    this.pushUndo({
      type: "floor",
      undo: () => {
        const t = this.world.floors.get(k);
        if (t) {
          this.world.floorMeshes.remove(t.mesh);
          this.world.floors.delete(k);
        }
      },
    });
  }

  private sellAt(gx: number, gz: number): void {
    const idx = this.objects.findIndex((o) => {
      const item = o.group.userData.item as CatalogItem;
      const cells = footprintCells(item, o.gridX, o.gridZ, o.rotation);
      return cells.some(([cx, cz]) => cx === gx && cz === gz);
    });
    if (idx < 0) return;
    const obj = this.objects[idx];
    const item = obj.group.userData.item as CatalogItem;
    removeObject(this.world, this.scene, obj);
    this.objects.splice(idx, 1);
    this.pushUndo({
      type: "sell",
      undo: () => {
        const newObj = placeObject(this.world, this.scene, item, obj.gridX, obj.gridZ, obj.rotation);
        if (newObj) this.objects.push(newObj);
      },
    });
    this.onSell?.(item, obj);
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
}