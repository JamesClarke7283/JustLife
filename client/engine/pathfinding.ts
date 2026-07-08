// Just Life — grid A* pathfinding around walls/objects.
import { LOT_H, LOT_W, World } from './world.ts';

export interface PathResult {
  waypoints: [number, number][]; // grid cells
  found: boolean;
}

const dirs: [number, number][] = [
  [0, 1],
  [1, 0],
  [0, -1],
  [-1, 0], // cardinal
  [1, 1],
  [1, -1],
  [-1, 1],
  [-1, -1], // diagonal
];

interface Node {
  gx: number;
  gz: number;
  f: number;
  g: number;
  parent: Node | null;
}

export function findPath(
  world: World,
  startGx: number,
  startGz: number,
  goalGx: number,
  goalGz: number,
): PathResult {
  if (!world.inBounds(goalGx, goalGz) || !world.inBounds(startGx, startGz)) {
    return { waypoints: [], found: false };
  }
  // If goal blocked, find nearest unblocked cell to goal
  let gx = goalGx, gz = goalGz;
  if (world.isBlocked(gx, gz)) {
    const near = nearestFree(world, goalGx, goalGz);
    if (!near) return { waypoints: [], found: false };
    [gx, gz] = near;
  }
  if (gx === startGx && gz === startGz) return { waypoints: [[gx, gz]], found: true };

  const open: Node[] = [];
  const closed = new Set<string>();
  const key = (x: number, z: number) => `${x},${z}`;
  const h = (x: number, z: number) => Math.hypot(x - gx, z - gz);

  open.push({ gx: startGx, gz: startGz, f: h(startGx, startGz), g: 0, parent: null });

  let iter = 0;
  while (open.length && iter < 5000) {
    iter++;
    // pick lowest f
    let bestIdx = 0;
    for (let i = 1; i < open.length; i++) {
      if (open[i].f < open[bestIdx].f) bestIdx = i;
    }
    const cur = open.splice(bestIdx, 1)[0];
    const ck = key(cur.gx, cur.gz);
    if (closed.has(ck)) continue;
    closed.add(ck);

    if (cur.gx === gx && cur.gz === gz) {
      // reconstruct
      const wp: [number, number][] = [];
      let n: Node | null = cur;
      while (n) {
        wp.push([n.gx, n.gz]);
        n = n.parent;
      }
      wp.reverse();
      return { waypoints: wp, found: true };
    }

    for (const [dx, dz] of dirs) {
      const nx = cur.gx + dx, nz = cur.gz + dz;
      if (!world.inBounds(nx, nz)) continue;
      if (world.isBlocked(nx, nz) && !(nx === gx && nz === gz)) continue;
      // prevent diagonal corner cutting
      if (dx !== 0 && dz !== 0) {
        if (world.isBlocked(cur.gx + dx, cur.gz) || world.isBlocked(cur.gx, cur.gz + dz)) continue;
      }
      const nk = key(nx, nz);
      if (closed.has(nk)) continue;
      const move = (dx !== 0 && dz !== 0) ? 1.414 : 1;
      open.push({ gx: nx, gz: nz, g: cur.g + move, f: cur.g + move + h(nx, nz), parent: cur });
    }
  }
  return { waypoints: [], found: false };
}

function nearestFree(world: World, gx: number, gz: number): [number, number] | null {
  if (!world.isBlocked(gx, gz)) return [gx, gz];
  for (let r = 1; r < 6; r++) {
    for (let dx = -r; dx <= r; dx++) {
      for (let dz = -r; dz <= r; dz++) {
        if (Math.max(Math.abs(dx), Math.abs(dz)) !== r) continue;
        const nx = gx + dx, nz = gz + dz;
        if (world.inBounds(nx, nz) && !world.isBlocked(nx, nz)) return [nx, nz];
      }
    }
  }
  return null;
}

export { LOT_H, LOT_W };
