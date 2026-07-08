// Just Life — objects: build three.js meshes from catalog JSON parts,
// placement with rotation/occupancy, sell/refund.
import * as THREE from "three";
import type { CatalogItem, CatalogPart, PlacedObject } from "./types.ts";
export type { PlacedObject };
import { World, LOT_W, LOT_H } from "./world.ts";

let nextId = 1;

export function rgbToHex(rgb: [number, number, number]): number {
  const r = Math.round(rgb[0] * 255);
  const g = Math.round(rgb[1] * 255);
  const b = Math.round(rgb[2] * 255);
  return (r << 16) | (g << 8) | b;
}

function makePartMesh(part: CatalogPart): THREE.Mesh {
  const color = rgbToHex(part.color);
  const mat = new THREE.MeshStandardMaterial({ color, roughness: 0.85, flatShading: true });
  let geo: THREE.BufferGeometry;
  const [sx, sy, sz] = part.size;
  switch (part.shape) {
    case "Cuboid":
      geo = new THREE.BoxGeometry(sx, sy, sz);
      break;
    case "Cylinder":
      geo = new THREE.CylinderGeometry(sx / 2, sx / 2, sy, 12);
      break;
    case "Sphere":
      geo = new THREE.SphereGeometry(sx / 2, 14, 10);
      break;
    case "Cone":
      geo = new THREE.ConeGeometry(sx / 2, sy, 12);
      break;
    default:
      geo = new THREE.BoxGeometry(sx, sy, sz);
  }
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.set(part.offset[0], part.offset[1], part.offset[2]);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  return mesh;
}

export function buildObjectMesh(item: CatalogItem): THREE.Group {
  const group = new THREE.Group();
  for (const part of item.parts) {
    group.add(makePartMesh(part));
  }
  return group;
}

// Footprint cells occupied by an object at grid (gx,gz) with rotation 0-3.
export function footprintCells(
  item: CatalogItem,
  gx: number,
  gz: number,
  rotation: number,
): [number, number][] {
  let [w, h] = item.footprint;
  if (rotation % 2 === 1) [w, h] = [h, w];
  const cells: [number, number][] = [];
  // footprint centered on (gx, gz)
  const halfW = Math.floor(w / 2);
  const halfH = Math.floor(h / 2);
  for (let dx = -halfW; dx < w - halfW; dx++) {
    for (let dz = -halfH; dz < h - halfH; dz++) {
      cells.push([gx + dx, gz + dz]);
    }
  }
  return cells;
}

export function canPlace(world: World, item: CatalogItem, gx: number, gz: number, rotation: number): boolean {
  const cells = footprintCells(item, gx, gz, rotation);
  for (const [cx, cz] of cells) {
    if (!world.inBounds(cx, cz)) return false;
    if (world.isBlocked(cx, cz)) return false;
  }
  return true;
}

export function placeObject(
  world: World,
  scene: THREE.Scene,
  item: CatalogItem,
  gx: number,
  gz: number,
  rotation: number,
): PlacedObject | null {
  if (!canPlace(world, item, gx, gz, rotation)) return null;
  const group = buildObjectMesh(item);
  const [wx, wz] = world.gridToWorld(gx, gz);
  group.position.set(wx, 0, wz);
  group.rotation.y = rotation * (Math.PI / 2);
  scene.add(group);
  // Mark cells blocked
  for (const [cx, cz] of footprintCells(item, gx, gz, rotation)) {
    world.setBlocked(cx, cz, true);
  }
  const obj: PlacedObject = { id: nextId++, catalogId: item.id, gridX: gx, gridZ: gz, rotation, group };
  // Tag meshes so raycaster can find the parent object
  group.traverse((c) => {
    if (c instanceof THREE.Mesh) c.userData.placedId = obj.id;
  });
  group.userData.placedId = obj.id;
  group.userData.item = item;
  return obj;
}

export function removeObject(world: World, scene: THREE.Scene, obj: PlacedObject): void {
  scene.remove(obj.group);
  const item = obj.group.userData.item as CatalogItem;
  for (const [cx, cz] of footprintCells(item, obj.gridX, obj.gridZ, obj.rotation)) {
    world.setBlocked(cx, cz, false);
  }
}

export function ghostMesh(item: CatalogItem, valid: boolean): THREE.Group {
  const group = buildObjectMesh(item);
  group.traverse((c) => {
    if (c instanceof THREE.Mesh) {
      c.material = new THREE.MeshStandardMaterial({
        color: valid ? 0x4caf50 : 0xf44336,
        transparent: true,
        opacity: 0.5,
        flatShading: true,
      });
      c.castShadow = false;
    }
  });
  return group;
}

export { LOT_W, LOT_H, nextId };