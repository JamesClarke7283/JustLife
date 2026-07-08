// Just Life — career & economy: household money, career tracks, work
// schedule, salary, promotions.
import type { CareerTrack, CareerLevel } from "./types.ts";
import type { Sim } from "./sim.ts";

export class Household {
  money = 20000;
  day = 1; // in-game day
  hour = 8; // 0-24
  minute = 0;

  // Day of week: 0=Sun..6=Sat. day 1 = Monday.
  dayOfWeek(): number {
    const monIndex = (this.day - 1) % 7; // 0=Mon..6=Sun
    return monIndex === 6 ? 0 : monIndex + 1; // convert to Sun=0..Sat=6
  }
}

export class Career {
  track: CareerTrack | null = null;
  levelIndex = 0; // 0-based
  performance = 0; // 0-100, accrues while working; promotion at 100
  working = false;

  get level(): CareerLevel | null {
    return this.track ? this.track.levels[this.levelIndex] : null;
  }

  get title(): string {
    return this.level?.title ?? "Unemployed";
  }

  get salary(): number {
    return this.level?.salary ?? 0;
  }

  join(track: CareerTrack): void {
    this.track = track;
    this.levelIndex = 0;
    this.performance = 0;
  }

  // Called each game-tick while at work.
  work(dt: number): number {
    this.performance = Math.min(100, this.performance + dt * 5);
    // salary is hourly; dt is in game-minutes → hours = dt/60
    return this.salary * (dt / 60);
  }

  // Promote if performance is high enough and a higher level exists.
  maybePromote(): boolean {
    if (!this.track) return false;
    if (this.performance >= 100 && this.levelIndex < this.track.levels.length - 1) {
      this.levelIndex++;
      this.performance = 0;
      return true;
    }
    if (this.performance >= 100) this.performance = 0; // cap at top
    return false;
  }

  // Is it a work day at the given day-of-week + hour?
  // dayOfWeek: 0=Sun..6=Sat. We use this.day to derive it.
  shouldWorkNow(dayOfWeek: number, hour: number): boolean {
    const lv = this.level;
    if (!lv) return false;
    if (!lv.workDays.includes(dayOfWeek)) return false;
    if (lv.startHour < lv.endHour) {
      return hour >= lv.startHour && hour < lv.endHour;
    }
    // overnight shift (e.g. 20-2): hour >= start OR hour < end
    return hour >= lv.startHour || hour < lv.endHour;
  }
}

export function simCareer(sim: Sim): Career {
  if (!sim.group.userData.career) {
    sim.group.userData.career = new Career();
  }
  return sim.group.userData.career as Career;
}