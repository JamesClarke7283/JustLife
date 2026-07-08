// Just Life — sim entity: appearance, movement via pathfinder, animation.
import * as THREE from "three";
import { THEME } from "../theme.ts";
import { World } from "./world.ts";
import { findPath } from "./pathfinding.ts";
import type { PathResult } from "./pathfinding.ts";

export interface SimConfig {
  name: string;
  skinTone?: number;
  shirtColor?: number;
  pantsColor?: number;
  hairColor?: number;
}

export type SimState = "idle" | "walking" | "interacting" | "atWork";

export class Sim {
  name: string;
  group: THREE.Group;
  world: World;
  // grid position
  gx: number;
  gz: number;
  // movement
  path: [number, number][] = [];
  pathIdx = 0;
  speed = 2.5; // world units / sec
  state: SimState = "idle";
  // interaction target
  interactUntil = 0; // game-time seconds
  interactAction = "";
  // animation
  private t = 0;
  private body: THREE.Mesh;
  private head: THREE.Mesh;
  private ring: THREE.Mesh;
  private label: THREE.Sprite;
  selected = false;

  constructor(scene: THREE.Scene, world: World, cfg: SimConfig) {
    this.name = cfg.name;
    this.world = world;
    this.gx = 10;
    this.gz = 10;

    this.group = new THREE.Group();
    const skin = cfg.skinTone ?? THEME.skin;
    const shirt = cfg.shirtColor ?? THEME.shirt;
    const pants = cfg.pantsColor ?? THEME.pants;
    const hair = cfg.hairColor ?? THEME.hair;

    // body (torso)
    this.body = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.28, 0.6, 6, 12),
      new THREE.MeshStandardMaterial({ color: shirt, roughness: 0.8, flatShading: true }),
    );
    this.body.position.y = 0.75;
    this.body.castShadow = true;
    this.group.add(this.body);

    // legs
    const legMat = new THREE.MeshStandardMaterial({ color: pants, roughness: 0.85, flatShading: true });
    const legL = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.13, 0.6, 8), legMat);
    legL.position.set(-0.14, 0.3, 0);
    legL.castShadow = true;
    this.group.add(legL);
    const legR = legL.clone();
    legR.position.x = 0.14;
    this.group.add(legR);
    this.group.userData.legL = legL;
    this.group.userData.legR = legR;

    // head
    this.head = new THREE.Mesh(
      new THREE.SphereGeometry(0.28, 16, 12),
      new THREE.MeshStandardMaterial({ color: skin, roughness: 0.7, flatShading: true }),
    );
    this.head.position.y = 1.4;
    this.head.castShadow = true;
    this.group.add(this.head);

    // hair
    const hairMesh = new THREE.Mesh(
      new THREE.SphereGeometry(0.3, 14, 10, 0, Math.PI * 2, 0, Math.PI / 2),
      new THREE.MeshStandardMaterial({ color: hair, roughness: 0.9, flatShading: true }),
    );
    hairMesh.position.y = 1.44;
    this.group.add(hairMesh);

    // selection ring
    this.ring = new THREE.Mesh(
      new THREE.RingGeometry(0.42, 0.55, 32),
      new THREE.MeshBasicMaterial({ color: THEME.primary, side: THREE.DoubleSide, transparent: true, opacity: 0.85 }),
    );
    this.ring.rotation.x = -Math.PI / 2;
    this.ring.position.y = 0.02;
    this.ring.visible = false;
    this.group.add(this.ring);

    // name label
    const canvas = document.createElement("canvas");
    canvas.width = 256;
    canvas.height = 64;
    const ctx = canvas.getContext("2d")!;
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    ctx.fillRect(0, 22, 256, 28);
    ctx.fillStyle = "#fff";
    ctx.font = "bold 22px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(cfg.name, 128, 44);
    const tex = new THREE.CanvasTexture(canvas);
    this.label = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false }));
    this.label.position.y = 2.1;
    this.label.scale.set(1.6, 0.4, 1);
    this.group.add(this.label);

    this.setGridPos(this.gx, this.gz);
    scene.add(this.group);
  }

  setGridPos(gx: number, gz: number): void {
    this.gx = gx;
    this.gz = gz;
    const [wx, wz] = this.world.gridToWorld(gx, gz);
    this.group.position.set(wx, 0, wz);
  }

  setSelected(sel: boolean): void {
    this.selected = sel;
    this.ring.visible = sel;
  }

  // Issue a move command to a grid cell.
  moveTo(targetGx: number, targetGz: number): boolean {
    const result: PathResult = findPath(this.world, this.gx, this.gz, targetGx, targetGz);
    if (!result.found || result.waypoints.length < 2) {
      this.path = [];
      this.pathIdx = 0;
      this.state = "idle";
      return false;
    }
    this.path = result.waypoints;
    this.pathIdx = 1; // skip current cell
    this.state = "walking";
    return true;
  }

  // Walk to an object's front cell, then interact.
  walkToInteract(targetGx: number, targetGz: number, action: string, duration: number): boolean {
    const ok = this.moveTo(targetGx, targetGz);
    if (ok) {
      this.interactAction = action;
      this.interactUntil = 0; // set on arrival
      this.group.userData.pendingInteract = { duration };
    }
    return ok;
  }

  update(dt: number): void {
    this.t += dt;
    const pos = this.group.position;
    const legL = this.group.userData.legL as THREE.Mesh;
    const legR = this.group.userData.legR as THREE.Mesh;

    if (this.state === "walking" && this.path.length > 0) {
      const [tgx, tgz] = this.path[this.pathIdx];
      const [twx, twz] = this.world.gridToWorld(tgx, tgz);
      const dx = twx - pos.x;
      const dz = twz - pos.z;
      const dist = Math.hypot(dx, dz);
      if (dist < 0.06) {
        this.gx = tgx;
        this.gz = tgz;
        this.pathIdx++;
        if (this.pathIdx >= this.path.length) {
          this.path = [];
          this.state = "idle";
          // check pending interaction
          const pi = this.group.userData.pendingInteract;
          if (pi) {
            this.state = "interacting";
            this.interactUntil = this.t + pi.duration;
            this.group.userData.pendingInteract = null;
          }
        }
      } else {
        const step = Math.min(this.speed * dt, dist);
        pos.x += (dx / dist) * step;
        pos.z += (dz / dist) * step;
        // face direction
        this.group.rotation.y = Math.atan2(dx, dz);
        // walk bob
        const bob = Math.sin(this.t * 10) * 0.08;
        pos.y = bob;
        if (legL && legR) {
          legL.rotation.x = Math.sin(this.t * 10) * 0.5;
          legR.rotation.x = -Math.sin(this.t * 10) * 0.5;
        }
      }
    } else if (this.state === "interacting") {
      if (this.t >= this.interactUntil) {
        this.state = "idle";
        this.interactAction = "";
      }
      // gentle idle
      pos.y = 0;
    } else {
      // idle bob
      pos.y = Math.sin(this.t * 2) * 0.02;
      if (legL && legR) {
        legL.rotation.x *= 0.8;
        legR.rotation.x *= 0.8;
      }
    }

    // label faces camera (billboard)
    const q = new THREE.Quaternion();
    this.group.getWorldQuaternion(q);
    this.label.quaternion.copy(q).invert();
  }

  get needsRef(): unknown {
    return this.group.userData.needs;
  }
}