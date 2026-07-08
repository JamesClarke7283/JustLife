// Just Life — shared types used across engine modules.

import type * as THREE from 'three';
import type { NeedKey } from '../theme.ts';

export interface CatalogPart {
  shape: 'Cuboid' | 'Cylinder' | 'Sphere' | 'Cone';
  size: [number, number, number];
  offset: [number, number, number];
  color: [number, number, number];
}

export interface CatalogAction {
  name: string;
  need: NeedKey;
  rate: number;
}

export interface CatalogItem {
  id: string;
  name: string;
  category: string;
  subcategory: string;
  price: number;
  description: string;
  footprint: [number, number];
  parts: CatalogPart[];
  actions: CatalogAction[];
}

export interface CareerLevel {
  title: string;
  salary: number;
  workDays: number[];
  startHour: number;
  endHour: number;
}

export interface CareerTrack {
  name: string;
  levels: CareerLevel[];
}

export interface PlacedObject {
  id: number;
  catalogId: string;
  gridX: number;
  gridZ: number;
  rotation: number; // 0,1,2,3 = quarter turns
  group: THREE.Group;
}

export interface Vec2 {
  x: number;
  z: number;
}

export type GameMode = 'menu' | 'live' | 'build' | 'buy';
export type GameSpeed = 0 | 1 | 2 | 3;
