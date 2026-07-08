// Just Life — autonomy AI: pick the lowest need, find the nearest object
// that restores it, route the sim there, and run the interaction.
import type { CatalogItem, PlacedObject } from "./types.ts";
import type { Sim } from "./sim.ts";
import type { Needs } from "./needs.ts";
import { NEEDS, type NeedKey } from "../theme.ts";

export interface AutonomyState {
  enabled: boolean;
  // throttle: don't re-evaluate every frame
  cooldown: number;
}

export function makeAutonomy(): AutonomyState {
  return { enabled: true, cooldown: 0 };
}

// Find the nearest placed object that offers an action restoring `need`.
export function findObjectForNeed(
  need: NeedKey,
  objects: PlacedObject[],
  fromGx: number,
  fromGz: number,
): { obj: PlacedObject; item: CatalogItem; actionName: string; rate: number; frontCell: [number, number] } | null {
  let best: { obj: PlacedObject; item: CatalogItem; actionName: string; rate: number; frontCell: [number, number] } | null = null;
  let bestDist = Infinity;
  for (const obj of objects) {
    const item = obj.group.userData.item as CatalogItem;
    if (!item) continue;
    const action = item.actions.find((a) => a.need === need);
    if (!action) continue;
    // front cell = one cell in front of the object (south side)
    const [w, h] = item.footprint;
    const halfH = Math.floor(h / 2);
    const frontGz = obj.gridZ - halfH - 1;
    const front: [number, number] = [obj.gridX, frontGz];
    const dist = Math.hypot(obj.gridX - fromGx, obj.gridZ - fromGz);
    if (dist < bestDist) {
      bestDist = dist;
      best = { obj, item, actionName: action.name, rate: action.rate, frontCell: front };
    }
  }
  return best;
}

// Decide + issue an action for a sim. Returns the action description if one
// was issued, or null if idle.
export function autonomyTick(
  sim: Sim,
  needs: Needs,
  objects: PlacedObject[],
  auto: AutonomyState,
  dt: number,
): string | null {
  if (!auto.enabled) return null;
  auto.cooldown -= dt;
  if (auto.cooldown > 0) return null;
  if (sim.state !== "idle") return null;

  // only act if a need is critically low (<35)
  const worst = needs.lowestNeed();
  if (needs.get(worst) > 35) {
    auto.cooldown = 2;
    return null;
  }

  const target = findObjectForNeed(worst, objects, sim.gx, sim.gz);
  if (!target) {
    auto.cooldown = 5;
    return null;
  }
  const duration = Math.min(15, (100 - needs.get(worst)) / target.rate * 60);
  const ok = sim.walkToInteract(target.frontCell[0], target.frontCell[1], target.actionName, duration);
  if (ok) {
    sim.group.userData.activeNeed = worst;
    sim.group.userData.activeRate = target.rate;
    auto.cooldown = duration + 2;
    return `${target.actionName} (${worst})`;
  }
  auto.cooldown = 3;
  return null;
}