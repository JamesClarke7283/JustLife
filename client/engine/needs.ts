// Just Life — needs system: 6 needs (0-100), decay over game time,
// fulfillment via object actions, mood derived from averages.
import { NEED_COLORS, NEED_DECAY, type NeedKey, NEEDS } from '../theme.ts';
import type { Sim } from './sim.ts';

export class Needs {
  values: Record<NeedKey, number> = {
    Hunger: 75,
    Energy: 80,
    Social: 65,
    Fun: 70,
    Hygiene: 85,
    Bladder: 90,
  };

  // decay per real second (scaled by game speed externally)
  tick(dt: number): void {
    for (const need of NEEDS) {
      this.values[need] = Math.max(0, this.values[need] - NEED_DECAY[need] * dt);
    }
  }

  fulfill(need: NeedKey, rate: number, dt: number): void {
    this.values[need] = Math.min(100, this.values[need] + rate * dt);
  }

  // The lowest need — what autonomy targets.
  lowestNeed(): NeedKey {
    let worst: NeedKey = 'Hunger';
    let worstVal = 101;
    for (const need of NEEDS) {
      if (this.values[need] < worstVal) {
        worstVal = this.values[need];
        worst = need;
      }
    }
    return worst;
  }

  // 0 (bad mood) .. 1 (great mood)
  mood(): number {
    let sum = 0;
    for (const need of NEEDS) sum += this.values[need];
    return sum / (NEEDS.length * 100);
  }

  colorFor(need: NeedKey): number {
    return NEED_COLORS[need];
  }

  get(need: NeedKey): number {
    return this.values[need];
  }
}

// Attach a Needs instance to a sim for convenience.
export function simNeeds(sim: Sim): Needs {
  if (!sim.group.userData.needsInstance) {
    sim.group.userData.needsInstance = new Needs();
  }
  return sim.group.userData.needsInstance as Needs;
}
