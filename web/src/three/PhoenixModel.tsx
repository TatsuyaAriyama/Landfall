import { useEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";
import { useGLTF } from "@react-three/drei";

// The Polaris Wayfinder is authored in Blender.  The GLB keeps these named
// transform pivots so the game can retain its small, responsive procedural poses
// without rebuilding the character out of Three.js primitives.
// Versioned filename is intentional: production CDNs and installed PWAs can
// retain a same-URL GLB for hours even after the app shell has updated.
const NAVIGATOR_URL = "/models/navigator_main-v5.glb";
const FISHING_ROD_URL = "/models/fishing_rod.glb";

// Kept for compatibility with saved dress data.  The selected main-character
// design has one canonical raised hood, so both legacy values now resolve to it.
export const HOOD_SHAPES = ["peak", "down"] as const;
export type HoodShape = (typeof HOOD_SHAPES)[number];

export type PhoenixPose =
  | "idle"
  | "walk"
  | "lookout"
  | "raise"
  | "hail"
  | "point"
  | "stargaze"
  | "rest"
  | "sit"
  | "pickupRod"
  | "equipRod"
  | "holdRod"
  | "walkRod"
  | "stowRod";

interface PoseBase {
  armRx: number;
  armRz: number;
  armLx: number;
  armLz: number;
  lean: number;
  capeWind: number;
  headX: number;
  scan: number;
  scanSpeed: number;
  turn: number;
  sway: number;
  breathAmp: number;
  breathSpeed: number;
  sit: number;
}

const POSE_BASE: Record<PhoenixPose, PoseBase> = {
  idle: {
    armRx: 0, armRz: 0.12, armLx: 0, armLz: -0.12,
    lean: 0, capeWind: 1, headX: 0, scan: 0.13, scanSpeed: 0.3,
    turn: 0, sway: 1, breathAmp: 1, breathSpeed: 0.85, sit: 0,
  },
  walk: {
    armRx: 0, armRz: 0.1, armLx: 0, armLz: -0.1,
    lean: 0.09, capeWind: 1.7, headX: 0, scan: 0.04, scanSpeed: 0.3,
    turn: 0, sway: 1, breathAmp: 1, breathSpeed: 0.85, sit: 0,
  },
  lookout: {
    armRx: 0.02, armRz: 0.14, armLx: -2.3, armLz: 0.14,
    lean: 0.02, capeWind: 1.2, headX: -0.02, scan: 0.46, scanSpeed: 0.55,
    turn: 0.4, sway: 0.7, breathAmp: 1, breathSpeed: 0.8, sit: 0,
  },
  raise: {
    armRx: -2.35, armRz: 0.06, armLx: 0, armLz: -0.16,
    lean: -0.04, capeWind: 1.15, headX: -0.14, scan: 0.12, scanSpeed: 0.3,
    turn: 0, sway: 0.7, breathAmp: 1, breathSpeed: 0.85, sit: 0,
  },
  hail: {
    armRx: 0, armRz: 0.12, armLx: 0, armLz: -2.55,
    lean: 0, capeWind: 1.1, headX: 0, scan: 0.13, scanSpeed: 0.3,
    turn: 0, sway: 1, breathAmp: 1, breathSpeed: 0.85, sit: 0,
  },
  point: {
    armRx: 0.1, armRz: 0.1, armLx: -1.8, armLz: 0.06,
    lean: 0.14, capeWind: 1.45, headX: -0.08, scan: 0.02, scanSpeed: 0.2,
    turn: 0, sway: 0.25, breathAmp: 0.8, breathSpeed: 0.9, sit: 0,
  },
  stargaze: {
    armRx: 0.3, armRz: 0.18, armLx: -2.58, armLz: 0.1,
    lean: -0.1, capeWind: 0.8, headX: -0.46, scan: 0.2, scanSpeed: 0.16,
    turn: 0, sway: 0.5, breathAmp: 1.2, breathSpeed: 0.7, sit: 0,
  },
  rest: {
    armRx: -0.8, armRz: -0.3, armLx: -0.86, armLz: 0.32,
    lean: 0.07, capeWind: 0.75, headX: 0.32, scan: 0.05, scanSpeed: 0.22,
    turn: 0, sway: 0.6, breathAmp: 1.75, breathSpeed: 0.58, sit: 0,
  },
  sit: {
    armRx: 0.62, armRz: 0.3, armLx: 0.62, armLz: -0.3,
    lean: -0.12, capeWind: 0.7, headX: -0.05, scan: 0.13, scanSpeed: 0.18,
    turn: 0, sway: 0.45, breathAmp: 1.6, breathSpeed: 0.6, sit: 1,
  },
  pickupRod: {
    armRx: 0.2, armRz: 0.24, armLx: 0.42, armLz: -0.12,
    lean: 0.42, capeWind: 0.62, headX: 0.46, scan: 0.01, scanSpeed: 0.12,
    turn: 0, sway: 0.08, breathAmp: 0.65, breathSpeed: 0.66, sit: 0,
  },
  equipRod: {
    armRx: 0.34, armRz: 0.34, armLx: -0.58, armLz: 0.34,
    lean: 0.08, capeWind: 0.82, headX: 0.3, scan: 0.02, scanSpeed: 0.18,
    turn: 0, sway: 0.18, breathAmp: 0.75, breathSpeed: 0.72, sit: 0,
  },
  holdRod: {
    armRx: 0.04, armRz: 0.1, armLx: -1.12, armLz: -0.06,
    lean: 0.035, capeWind: 1, headX: -0.08, scan: 0.08, scanSpeed: 0.24,
    turn: 0, sway: 0.36, breathAmp: 0.9, breathSpeed: 0.78, sit: 0,
  },
  walkRod: {
    armRx: 0, armRz: 0.12, armLx: -1.08, armLz: -0.05,
    lean: 0.095, capeWind: 1.7, headX: -0.02, scan: 0.04, scanSpeed: 0.24,
    turn: 0, sway: 0.2, breathAmp: 1, breathSpeed: 0.85, sit: 0,
  },
  stowRod: {
    armRx: 0.24, armRz: 0.3, armLx: -0.36, armLz: 0.42,
    lean: 0.1, capeWind: 0.78, headX: 0.34, scan: 0.02, scanSpeed: 0.18,
    turn: 0, sway: 0.12, breathAmp: 0.72, breathSpeed: 0.7, sit: 0,
  },
};

interface NavigatorRig {
  core?: THREE.Object3D;
  head?: THREE.Object3D;
  armR?: THREE.Object3D;
  armL?: THREE.Object3D;
  legR?: THREE.Object3D;
  legL?: THREE.Object3D;
  cape?: THREE.Object3D;
  scarfTail?: THREE.Object3D;
  skirt?: THREE.Object3D;
  gripSocket?: THREE.Object3D;
}

interface CapeClothPiece {
  geometry: THREE.BufferGeometry;
  position: THREE.BufferAttribute;
  base: Float32Array;
}

function findRig(model: THREE.Object3D): NavigatorRig {
  return {
    core: model.getObjectByName("core"),
    head: model.getObjectByName("head"),
    armR: model.getObjectByName("armR"),
    armL: model.getObjectByName("armL"),
    legR: model.getObjectByName("legR"),
    legL: model.getObjectByName("legL"),
    cape: model.getObjectByName("cape"),
    scarfTail: model.getObjectByName("scarfTail"),
    skirt: model.getObjectByName("Coat"),
    gripSocket: model.getObjectByName("GripSocket"),
  };
}

const CONTACT_BOX = new THREE.Box3();
const CONTACT_INV = new THREE.Matrix4();
const CONTACT_EVERY = 5;
const LEG_HIP_Y = 0.46;
const SIT_DROP = 0.3;
const SIT_SPREAD = 1.24;

export default function PhoenixModel({
  animate = true,
  pose = "idle",
  hood: _hood,
  fishingRod = false,
}: {
  animate?: boolean;
  pose?: PhoenixPose;
  hood?: HoodShape;
  fishingRod?: boolean;
}) {
  const { scene } = useGLTF(NAVIGATOR_URL);
  const { scene: rodScene } = useGLTF(FISHING_ROD_URL);
  const model = useMemo(() => scene.clone(true), [scene]);
  const rod = useMemo(() => rodScene.clone(true), [rodScene]);
  const rig = useMemo(() => findRig(model), [model]);
  const capeCloth = useMemo<CapeClothPiece[]>(() => {
    const pieces: CapeClothPiece[] = [];
    rig.cape?.traverse((object) => {
      if (!(object instanceof THREE.Mesh) || !object.geometry) return;
      // GLTF clones share geometry.  The navigator instance needs its own
      // dynamic buffers so wind does not leak into other previews/scenes.
      object.geometry = object.geometry.clone();
      const position = object.geometry.getAttribute("position");
      if (!(position instanceof THREE.BufferAttribute)) return;
      position.setUsage(THREE.DynamicDrawUsage);
      pieces.push({
        geometry: object.geometry,
        position,
        base: new Float32Array(position.array as ArrayLike<number>),
      });
      const materials = Array.isArray(object.material) ? object.material : [object.material];
      for (const material of materials) {
        if (material) material.side = THREE.DoubleSide;
      }
    });
    return pieces;
  }, [rig.cape]);

  const root = useRef<THREE.Group>(null);
  const contact = useRef<THREE.Group>(null);
  const lift = useRef(0);
  const tick = useRef(0);
  const cur = useRef<PoseBase>({ ...POSE_BASE.idle });
  const phase = useRef({ breath: 0, scan: 0 });
  const lastPose = useRef<PhoenixPose>(pose);
  const heavy = useRef(false);
  const capeNormalTick = useRef(0);

  useEffect(() => {
    const socket = rig.gripSocket;
    if (!socket || !fishingRod) return;
    rod.position.set(0, 0, 0);
    rod.rotation.set(1.95, 0, -0.08);
    socket.add(rod);
    return () => {
      socket.remove(rod);
    };
  }, [fishingRod, rig.gripSocket, rod]);

  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const target = POSE_BASE[pose];
    const c = cur.current;
    if (pose !== lastPose.current) {
      heavy.current = pose === "sit" || lastPose.current === "sit";
      lastPose.current = pose;
    }
    const settle = heavy.current ? 1.5 : 6;
    const to = (key: keyof PoseBase, lambda = settle) => {
      c[key] = THREE.MathUtils.damp(c[key], target[key], lambda, delta);
    };
    to("armRx");
    to("armRz");
    to("armLx");
    to("armLz");
    to("lean");
    to("headX");
    to("scan");
    to("scanSpeed");
    to("turn");
    to("sway");
    to("breathAmp");
    to("breathSpeed");
    to("sit");
    to("capeWind", settle * 0.66);

    const ph = phase.current;
    ph.breath += delta * c.breathSpeed;
    ph.scan += delta * c.scanSpeed;

    const walking = pose === "walk" || pose === "walkRod";
    const stride = 5.4;
    const step = Math.sin(time * stride);
    const drop = c.sit * SIT_DROP;

    if (rig.core) {
      rig.core.position.y =
        (walking
          ? Math.abs(Math.cos(time * stride)) * 0.035
          : Math.sin(ph.breath) * 0.018 * c.breathAmp) - drop;
      rig.core.rotation.x = c.lean + Math.sin(ph.breath + 0.9) * 0.01 * c.breathAmp;
      rig.core.rotation.z = walking ? step * 0.03 : 0;
      rig.core.rotation.y = Math.sin(ph.scan - 0.55) * c.turn;
    }
    if (rig.head) {
      rig.head.rotation.y = Math.sin(ph.scan) * c.scan;
      rig.head.rotation.x = c.headX;
      rig.head.rotation.z = Math.sin(ph.breath + 2.1) * 0.018 * c.breathAmp;
    }

    const legSwing = walking ? 0.55 : 0;
    const legSit = -SIT_SPREAD * c.sit;
    for (const [leg, sign] of [
      [rig.legR, 1],
      [rig.legL, -1],
    ] as const) {
      if (!leg) continue;
      leg.position.y = LEG_HIP_Y - drop;
      leg.rotation.x = THREE.MathUtils.damp(
        leg.rotation.x,
        sign * step * legSwing + legSit,
        10,
        delta,
      );
    }

    const armSwing = walking
      ? -step * 0.32
      : Math.sin(ph.breath + 0.4) * 0.03 * c.sway;
    if (rig.armR) {
      rig.armR.rotation.x = c.armRx + armSwing;
      rig.armR.rotation.z = c.armRz;
    }
    if (rig.armL) {
      const wave = pose === "hail" ? Math.sin(time * 7.2) * 0.3 : 0;
      rig.armL.rotation.x =
        c.armLx + (walking ? step * 0.32 : Math.sin(ph.breath + 1.1) * 0.025 * c.sway);
      rig.armL.rotation.z = c.armLz + wave;
    }

    // The cape is a dense cloth grid.  Its shoulders stay pinned while two
    // travelling waves build toward the tips, keeping the compass silhouette
    // readable without behaving like a rigid board.
    if (rig.cape) {
      rig.cape.rotation.x = -0.012 * c.capeWind + Math.sin(time * 0.74) * 0.008;
      rig.cape.rotation.z = Math.sin(time * 0.58) * 0.006 * c.capeWind;
      for (const piece of capeCloth) {
        const { position, base } = piece;
        for (let index = 0; index < position.count; index += 1) {
          const offset = index * 3;
          const x = base[offset];
          const y = base[offset + 1];
          const z = base[offset + 2];
          const falloff = THREE.MathUtils.clamp((0.12 - z) / 0.84, 0, 1);
          const flutter = Math.pow(falloff, 1.38) * c.capeWind;
          const travelling = Math.sin(time * 2.05 - z * 8.2 + x * 3.8);
          const crosswind = Math.sin(time * 1.31 + x * 8.5 + z * 2.7);
          position.setXYZ(
            index,
            x + crosswind * 0.008 * flutter,
            y + (travelling * 0.048 + crosswind * 0.022) * flutter,
            z + Math.sin(time * 1.47 + x * 5.4) * 0.008 * flutter,
          );
        }
        position.needsUpdate = true;
      }
      if (capeNormalTick.current++ % 3 === 0) {
        for (const piece of capeCloth) piece.geometry.computeVertexNormals();
      }
    }
    if (rig.scarfTail) {
      rig.scarfTail.rotation.x = Math.sin(time * 2.0 + 0.7) * 0.045 * c.capeWind;
      rig.scarfTail.rotation.z = Math.sin(time * 1.35) * 0.06 * c.capeWind;
    }
    if (rig.skirt) {
      rig.skirt.scale.set(1 + 0.3 * c.sit, 1 - 0.22 * c.sit, 1 + 0.3 * c.sit);
    }

    const body = contact.current;
    if (body && root.current) {
      if (tick.current++ % CONTACT_EVERY === 0) {
        const applied = body.position.y;
        body.position.y = 0;
        CONTACT_BOX.setFromObject(body);
        CONTACT_INV.copy(root.current.matrixWorld).invert();
        CONTACT_BOX.applyMatrix4(CONTACT_INV);
        lift.current = Math.max(0, -CONTACT_BOX.min.y);
        body.position.y = applied;
      }
      body.position.y = THREE.MathUtils.damp(body.position.y, lift.current, 12, delta);
    }
  });

  return (
    // Blender exports the face toward +Z; game worlds use +X as the bow/forward axis.
    <group ref={root} rotation={[0, Math.PI / 2, 0]}>
      <group ref={contact}>
        <primitive object={model} />
      </group>
    </group>
  );
}

useGLTF.preload(NAVIGATOR_URL);
useGLTF.preload(FISHING_ROD_URL);
