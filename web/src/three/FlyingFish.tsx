import { useLayoutEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";
import { useGLTF } from "@react-three/drei";

const FLYING_FISH_URL = "/models/flying_fish.glb";

interface FlyingFishRoute {
  z: number;
  phase: number;
  duration: number;
  scale: number;
  direction: 1 | -1;
}

// The school remains sparse: these are small offshore encounters, not a screen
// effect. Staggered cycles also keep more than one fish from breaching at once.
const ROUTES: readonly FlyingFishRoute[] = [
  { z: 2.6, phase: 0, duration: 23, scale: 0.22, direction: 1 },
  { z: -2.2, phase: 8.4, duration: 27, scale: 0.18, direction: -1 },
  { z: 0.4, phase: 16.8, duration: 31, scale: 0.15, direction: 1 },
];

const FOLD_ANGLE = 1.22;
const START_X = -5.2;
const END_X = 6.2;
const DROPLET_GEO = new THREE.IcosahedronGeometry(0.035, 0);
const DROPLET_MAT = new THREE.MeshBasicMaterial({
  color: "#EADEBD",
  transparent: true,
  opacity: 0.7,
  depthWrite: false,
});

function ease(value: number): number {
  const v = THREE.MathUtils.clamp(value, 0, 1);
  return v * v * (3 - 2 * v);
}

function foldPart(
  part: THREE.Object3D | null,
  side: 1 | -1,
  fold: number,
): void {
  if (part) part.rotation.y = side * FOLD_ANGLE * fold;
}

function FlyingFish({
  route,
  animate,
}: {
  route: FlyingFishRoute;
  animate: boolean;
}) {
  const { scene } = useGLTF(FLYING_FISH_URL);
  const model = useMemo(() => scene.clone(true), [scene]);
  const swimmer = useRef<THREE.Group>(null);
  const splash = useRef<THREE.Group>(null);
  const tail = useRef<THREE.Object3D | null>(null);
  const pectoralLeft = useRef<THREE.Object3D | null>(null);
  const pectoralRight = useRef<THREE.Object3D | null>(null);
  const pelvicLeft = useRef<THREE.Object3D | null>(null);
  const pelvicRight = useRef<THREE.Object3D | null>(null);

  useLayoutEffect(() => {
    tail.current = model.getObjectByName("FlyingFish_Tail") ?? null;
    pectoralLeft.current = model.getObjectByName("FlyingFish_Pectoral_L") ?? null;
    pectoralRight.current = model.getObjectByName("FlyingFish_Pectoral_R") ?? null;
    pelvicLeft.current = model.getObjectByName("FlyingFish_Pelvic_L") ?? null;
    pelvicRight.current = model.getObjectByName("FlyingFish_Pelvic_R") ?? null;

    // Reduced motion still shows a real swimming posture: fins streamlined
    // backward, fish resting just above the stylized water plane.
    foldPart(pectoralLeft.current, 1, 1);
    foldPart(pectoralRight.current, -1, 1);
    foldPart(pelvicLeft.current, 1, 0.9);
    foldPart(pelvicRight.current, -1, 0.9);
    if (swimmer.current) {
      swimmer.current.position.set(route.direction * START_X, 0.07, route.z);
      swimmer.current.rotation.y = route.direction < 0 ? Math.PI : 0;
    }
  }, [model, route.direction, route.z]);

  useFrame(({ clock }) => {
    if (!animate || !swimmer.current) return;
    const fish = swimmer.current;
    const time = clock.elapsedTime + route.phase;
    const cycle = (time % route.duration) / route.duration;
    fish.visible = cycle < 0.88;
    if (!fish.visible) return;

    // A full observed behavior cycle:
    // 0–46% surface swimming/acceleration, 46–54% tail-driven taxi,
    // 54–76% rigid-wing glide, 76–88% folded-fin re-entry.
    const travel = ease(cycle / 0.88);
    const start = route.direction > 0 ? START_X : -START_X;
    const end = route.direction > 0 ? END_X : -END_X;
    fish.position.x = THREE.MathUtils.lerp(start, end, travel);
    fish.position.z =
      route.z + Math.sin(time * 0.55 + route.phase) * (cycle < 0.46 ? 0.16 : 0.06);

    let height = 0.07;
    let pitch = 0;
    let fold = 1;
    let tailBeat = 0;
    let splashAmount = 0;

    if (cycle < 0.46) {
      // Body–caudal-fin swimming: wings stay folded to reduce drag and the
      // rear body oscillates laterally.
      const accelerate = cycle / 0.46;
      height += Math.sin(time * 2.2) * 0.018;
      tailBeat = Math.sin(time * (8 + accelerate * 8)) * (0.18 + accelerate * 0.16);
    } else if (cycle < 0.54) {
      // Taxi: the body clears the surface while the long lower tail lobe keeps
      // striking the water. Pectorals open only as lift becomes available.
      const taxi = (cycle - 0.46) / 0.08;
      height = THREE.MathUtils.lerp(0.07, 0.24, ease(taxi));
      pitch = THREE.MathUtils.lerp(0.02, 0.16, taxi);
      fold = 1 - ease(taxi);
      tailBeat = Math.sin(time * 28) * 0.42;
      splashAmount = Math.sin(Math.PI * taxi);
    } else if (cycle < 0.76) {
      // Flying fish glide; they do not flap their pectorals like birds. The
      // extended fins remain almost rigid and the path stays low over the sea.
      const glide = (cycle - 0.54) / 0.22;
      height = 0.24 + Math.sin(Math.PI * glide) * 0.82;
      pitch = THREE.MathUtils.lerp(0.12, -0.1, glide);
      fold = 0;
      tailBeat = 0;
    } else {
      const entry = (cycle - 0.76) / 0.12;
      height = THREE.MathUtils.lerp(0.24, 0.055, ease(entry));
      pitch = THREE.MathUtils.lerp(-0.1, -0.02, entry);
      fold = ease(entry);
      tailBeat = Math.sin(time * 14) * 0.18 * entry;
      splashAmount = Math.sin(Math.PI * entry) * 0.72;
    }

    fish.position.y = height;
    fish.rotation.y = route.direction < 0 ? Math.PI : 0;
    fish.rotation.z = route.direction * pitch;
    if (tail.current) tail.current.rotation.y = tailBeat;
    foldPart(pectoralLeft.current, 1, fold);
    foldPart(pectoralRight.current, -1, fold);
    foldPart(pelvicLeft.current, 1, fold * 0.9);
    foldPart(pelvicRight.current, -1, fold * 0.9);

    if (splash.current) {
      splash.current.visible = splashAmount > 0.02;
      splash.current.position.set(fish.position.x - route.direction * 0.16, 0.07, fish.position.z);
      splash.current.scale.setScalar(0.5 + splashAmount * 1.1);
      splash.current.rotation.y = time * 0.8;
    }
  });

  return (
    <>
      <group ref={swimmer} scale={route.scale}>
        <primitive object={model} />
      </group>
      <group ref={splash} visible={false}>
        {[
          [-0.08, 0.02, 0],
          [0.02, 0.09, 0.08],
          [0.11, 0.04, -0.06],
        ].map((position, index) => (
          <mesh
            key={index}
            geometry={DROPLET_GEO}
            material={DROPLET_MAT}
            position={position as [number, number, number]}
            scale={index === 1 ? 1.15 : 0.8}
          />
        ))}
      </group>
    </>
  );
}

export default function FlyingFishSchool({ animate }: { animate: boolean }) {
  return (
    <group>
      {ROUTES.map((route, index) => (
        <FlyingFish key={index} route={route} animate={animate} />
      ))}
    </group>
  );
}

useGLTF.preload(FLYING_FISH_URL);
