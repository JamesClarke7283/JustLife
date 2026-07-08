// Just Life — thumbnail generator: renders each catalog item's 3D mesh to a
// small PNG data URL for use as a preview icon in the buy-mode catalog.
// Uses a single shared offscreen renderer to avoid WebGL context limits.
import * as THREE from "three";
import { buildObjectMesh } from "./objects.ts";
import type { CatalogItem } from "./types.ts";

const SIZE = 256;

class ThumbGen {
  private renderer: THREE.WebGLRenderer;
  private scene: THREE.Scene;
  private camera: THREE.PerspectiveCamera;
  private cache = new Map<string, string>();

  constructor() {
    const canvas = document.createElement("canvas");
    canvas.width = SIZE;
    canvas.height = SIZE;
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: true,
      preserveDrawingBuffer: true,
    });
    this.renderer.setPixelRatio(1);
    this.renderer.setSize(SIZE, SIZE);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.shadowMap.enabled = false;

    this.scene = new THREE.Scene();
    // soft studio lighting
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.65));
    const key = new THREE.DirectionalLight(0xffffff, 1.4);
    key.position.set(4, 6, 3);
    this.scene.add(key);
    const fill = new THREE.DirectionalLight(0xbfe3ff, 0.5);
    fill.position.set(-4, 2, -2);
    this.scene.add(fill);

    this.camera = new THREE.PerspectiveCamera(25, 1, 0.1, 200);
  }

  generate(item: CatalogItem): string {
    const cached = this.cache.get(item.id);
    if (cached) return cached;

    const group = buildObjectMesh(item);

    // compute bounding box / sphere to frame the camera
    const box = new THREE.Box3().setFromObject(group);
    const sphere = new THREE.Sphere();
    box.getBoundingSphere(sphere);
    const center = sphere.center;
    const radius = Math.max(sphere.radius, 0.5);

    // isometric-ish angle
    const dir = new THREE.Vector3(1, 0.8, 1).normalize();
    // Give extra room: use 1.4x distance so tall objects (fridge, bookshelf,
    // shower, tree) aren't clipped at the top. Also account for the vertical
    // extent specifically, since the bounding sphere can underestimate the
    // needed vertical framing for tall thin objects.
    const verticalExtent = Math.max(box.max.y - box.min.y, radius * 1.5);
    const frameRadius = Math.max(radius, verticalExtent / 1.8);
    const dist = frameRadius / Math.sin((this.camera.fov * Math.PI) / 360) * 1.35;
    this.camera.position.copy(center).add(dir.multiplyScalar(dist));
    this.camera.lookAt(center);

    // subtle ground shadow disc
    const shadow = new THREE.Mesh(
      new THREE.CircleGeometry(radius * 1.4, 24),
      new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.12 }),
    );
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.set(center.x, box.min.y - 0.01, center.z);
    this.scene.add(shadow);

    this.scene.add(group);
    this.renderer.render(this.scene, this.camera);

    const url = this.renderer.domElement.toDataURL("image/png");
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