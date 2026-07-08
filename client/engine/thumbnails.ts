// Just Life — thumbnail generator: renders each catalog item's 3D mesh to a
// small PNG data URL for use as a preview icon in the buy-mode catalog.
// Uses a single shared offscreen renderer to avoid WebGL context limits.
import * as THREE from 'three';
import { buildObjectMesh } from './objects.ts';
import type { CatalogItem } from './types.ts';

const SIZE = 256;

class ThumbGen {
  private renderer: THREE.WebGLRenderer;
  private scene: THREE.Scene;
  private camera: THREE.PerspectiveCamera;
  private cache = new Map<string, string>();

  constructor() {
    const canvas = document.createElement('canvas');
    canvas.width = SIZE;
    canvas.height = SIZE;
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: false,
      preserveDrawingBuffer: true,
    });
    this.renderer.setPixelRatio(1);
    this.renderer.setSize(SIZE, SIZE);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.setClearColor(0xf7f0e3, 1);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0xf7f0e3);
    // soft studio lighting
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.55));
    const key = new THREE.DirectionalLight(0xffffff, 1.3);
    key.position.set(4, 8, 5);
    key.castShadow = true;
    key.shadow.mapSize.set(256, 256);
    this.scene.add(key);
    const fill = new THREE.DirectionalLight(0xc9e8ff, 0.55);
    fill.position.set(-5, 3, -4);
    this.scene.add(fill);
    const rim = new THREE.DirectionalLight(0xffe8c4, 0.45);
    rim.position.set(0, 3, -6);
    this.scene.add(rim);

    this.camera = new THREE.PerspectiveCamera(28, 1, 0.1, 200);
  }

  generate(item: CatalogItem): string {
    const cached = this.cache.get(item.id);
    if (cached) return cached;

    const group = buildObjectMesh(item);
    group.traverse((c) => {
      if (c instanceof THREE.Mesh) {
        c.castShadow = true;
        c.receiveShadow = true;
      }
    });

    // compute bounding box / sphere to frame the camera
    const box = new THREE.Box3().setFromObject(group);
    const sphere = new THREE.Sphere();
    box.getBoundingSphere(sphere);
    const center = sphere.center;
    const radius = Math.max(sphere.radius, 0.5);

    // isometric-ish angle
    const dir = new THREE.Vector3(1, 0.7, 1).normalize();
    const verticalExtent = Math.max(box.max.y - box.min.y, radius * 1.5);
    const frameRadius = Math.max(radius, verticalExtent / 1.8);
    const dist = frameRadius / Math.sin((this.camera.fov * Math.PI) / 360) * 1.45;
    this.camera.position.copy(center).add(dir.multiplyScalar(dist));
    this.camera.lookAt(center);

    // subtle ground shadow disc
    const shadow = new THREE.Mesh(
      new THREE.CircleGeometry(frameRadius * 1.2, 24),
      new THREE.MeshBasicMaterial({ color: 0x8d8d8d, transparent: true, opacity: 0.08 }),
    );
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.set(center.x, box.min.y - 0.01, center.z);
    this.scene.add(shadow);

    this.scene.add(group);
    this.renderer.render(this.scene, this.camera);

    const url = this.renderer.domElement.toDataURL('image/png');
    this.cache.set(item.id, url);

    // clean up
    this.scene.remove(group);
    this.scene.remove(shadow);
    group.traverse((c) => {
      if (c instanceof THREE.Mesh) {
        c.geometry.dispose();
        (c.material as THREE.Material).dispose();
      }
    });
    shadow.geometry.dispose();
    (shadow.material as THREE.Material).dispose();

    return url;
  }

  generateAll(items: CatalogItem[]): Map<string, string> {
    const out = new Map<string, string>();
    for (const item of items) out.set(item.id, this.generate(item));
    return out;
  }
}

let gen: ThumbGen | null = null;

export function getThumbnail(item: CatalogItem): string {
  if (!gen) gen = new ThumbGen();
  return gen.generate(item);
}

export function generateThumbnails(items: CatalogItem[]): Map<string, string> {
  if (!gen) gen = new ThumbGen();
  return gen.generateAll(items);
}
