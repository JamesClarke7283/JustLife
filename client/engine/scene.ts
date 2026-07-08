// Just Life — scene setup: renderer, isometric camera rig, lighting, sky.
import * as THREE from "three";
import { THEME } from "../theme.ts";

export interface SceneCtx {
  renderer: THREE.WebGLRenderer;
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  sun: THREE.DirectionalLight;
  resize: () => void;
}

// Camera rig target — the point the camera orbits/looks at.
const camTarget = new THREE.Vector3(0, 0, 0);
let camRotation = Math.PI / 4; // 45° around Y
let camDistance = 28;
let camHeight = 22;

export function getCamTarget(): THREE.Vector3 {
  return camTarget.clone();
}

export function setCamTarget(x: number, z: number): void {
  camTarget.set(x, 0, z);
}

export function rotateCam(dir: number): void {
  camRotation += dir * (Math.PI / 2);
}

export function zoomCam(delta: number): void {
  camDistance = Math.max(14, Math.min(48, camDistance + delta));
}

export function panCam(dx: number, dz: number): void {
  // Pan in the camera's forward/right plane.
  const cos = Math.cos(camRotation);
  const sin = Math.sin(camRotation);
  camTarget.x += dx * cos + dz * sin;
  camTarget.z += -dx * sin + dz * cos;
}

export function initScene(canvas: HTMLCanvasElement): SceneCtx {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(THEME.sky);
  scene.fog = new THREE.Fog(THEME.skyFog, 30, 70);

  const camera = new THREE.PerspectiveCamera(35, window.innerWidth / window.innerHeight, 0.1, 200);

  // Lighting
  const ambient = new THREE.AmbientLight(0xb8d8e8, 0.5);
  scene.add(ambient);

  const hemi = new THREE.HemisphereLight(0xbfe3ff, 0x6b8f4a, 0.55);
  scene.add(hemi);

  const sun = new THREE.DirectionalLight(THEME.sun, 1.5);
  sun.position.set(16, 24, 12);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  sun.shadow.camera.near = 0.5;
  sun.shadow.camera.far = 80;
  sun.shadow.camera.left = -30;
  sun.shadow.camera.right = 30;
  sun.shadow.camera.top = 30;
  sun.shadow.camera.bottom = -30;
  sun.shadow.bias = -0.0004;
  scene.add(sun);

  function resize(): void {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  }
  window.addEventListener("resize", resize);

  return { renderer, scene, camera, sun, resize };
}

// Update camera position from rig parameters each frame.
export function updateCamera(camera: THREE.PerspectiveCamera): void {
  const x = camTarget.x + Math.cos(camRotation) * camDistance;
  const z = camTarget.z + Math.sin(camRotation) * camDistance;
  camera.position.set(x, camHeight, z);
  camera.lookAt(camTarget);
}