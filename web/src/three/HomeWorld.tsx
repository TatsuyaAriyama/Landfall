import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Stars } from "@react-three/drei";
import * as THREE from "three";
import type { TimeOfDay } from "../timeOfDay";
import { Gulls, type GullFlock } from "./Gulls";
import IOSHomeIsland from "./IOSHomeIsland";
import IOSHomeOcean from "./IOSHomeOcean";
import IOSHomeVessel from "./IOSHomeVessel";
import { Moon, Sun } from "./SeaParts";

const HOME_CAMERA: [number, number, number] = [0.74, 2.02, 0.34];
const ISLAND_SCALE = 1.24;
const HOME_LIGHT: Record<TimeOfDay, {
  sky: string;
  fog: string;
  reflection: string;
  ambient: string;
  keyLight: string;
  fillLight: string;
  stars: number;
  celestial: "sun" | "moon";
}> = {
  morning: {
    sky: "#EDC49D", fog: "#A9CCC2", reflection: "#FFE3B7",
    ambient: "#FFE1C1", keyLight: "#FFD39E", fillLight: "#BDE5D9",
    stars: 0, celestial: "sun",
  },
  day: {
    sky: "#8BCFDB", fog: "#93C9C8", reflection: "#FFF0C2",
    ambient: "#E7FAF5", keyLight: "#FFF2C5", fillLight: "#A5E1D8",
    stars: 0, celestial: "sun",
  },
  evening: {
    sky: "#C97668", fog: "#916F68", reflection: "#FFD092",
    ambient: "#F5BEA2", keyLight: "#FFC382", fillLight: "#83B8AE",
    stars: 90, celestial: "sun",
  },
  night: {
    sky: "#183F3B", fog: "#37625D", reflection: "#D8EBDD",
    ambient: "#F4E4C9", keyLight: "#F0E5CC", fillLight: "#73AE95",
    stars: 430, celestial: "moon",
  },
};
const HOME_GULLS: GullFlock = [
  { r: 3.2, y: 4.8, omega: 0.08, scale: 0.22, flap: 1.8, phase: 0.2 },
  { r: 4.6, y: 5.4, omega: -0.06, scale: 0.2, flap: 2.1, phase: 2.1 },
  { r: 3.8, y: 4.3, omega: 0.1, scale: 0.24, flap: 2.3, phase: 4.2 },
];

export function homeDestinationDistance(ratio: number): number {
  const progress = Math.min(1, Math.max(0, ratio));
  if (progress === 0) return 110;
  if (progress === 1) return 18;
  return 110 + (18 - 110) * Math.pow(progress, 2.15);
}

function destinationFocusHeight(distance: number): number {
  const proximity = Math.min(1, Math.max(0, (110 - distance) / (110 - 18)));
  return 0.32 + 2 * proximity * proximity;
}

function Camera({ distance, animate }: { distance: number; animate: boolean }) {
  const camera = useThree((state) => state.camera);
  const invalidate = useThree((state) => state.invalidate);
  const size = useThree((state) => state.size);
  const target = useMemo(
    () => new THREE.Vector3(distance, destinationFocusHeight(distance), 0),
    [distance],
  );
  const currentDistance = useRef(distance);

  useLayoutEffect(() => {
    const portrait = size.width / Math.max(size.height, 1) < 0.76;
    camera.position.set(portrait ? 0.8 : 0.74, portrait ? 2.18 : 2.02, 0.34);
    camera.lookAt(target);
    camera.updateProjectionMatrix();
    invalidate();
  }, [camera, invalidate, size.height, size.width, target]);

  useFrame(({ clock }, delta) => {
    currentDistance.current = animate
      ? THREE.MathUtils.damp(currentDistance.current, distance, 0.8, delta)
      : distance;
    const time = clock.elapsedTime;
    const portrait = size.width / Math.max(size.height, 1) < 0.76;
    const rise = animate ? Math.sin(time * 0.68 + 0.7) * 0.035 : 0;
    const roll = animate ? Math.sin(time * 0.52) * 0.012 : 0;
    camera.position.set(
      portrait ? 0.8 : 0.74,
      (portrait ? 2.18 : 2.02) + rise,
      0.34,
    );
    camera.lookAt(
      currentDistance.current,
      destinationFocusHeight(currentDistance.current),
      0,
    );
    camera.rotateZ(roll);
  });
  return null;
}

function Scene({
  ratio,
  timeOfDay,
  animate,
}: {
  ratio: number;
  timeOfDay: TimeOfDay;
  animate: boolean;
}) {
  const light = HOME_LIGHT[timeOfDay];
  const distance = homeDestinationDistance(ratio);
  const celestial: [number, number, number] = [
    timeOfDay === "morning" ? 42 : timeOfDay === "day" ? 48 : 46,
    timeOfDay === "day" ? 14 : timeOfDay === "evening" ? 7 : 10,
    -2.5,
  ];

  return (
    <>
      <color attach="background" args={[light.sky]} />
      <fog attach="fog" args={[light.fog, 65, 220]} />
      <Camera distance={distance} animate={animate} />
      <ambientLight color={light.ambient} intensity={timeOfDay === "day" ? 1 : 0.68} />
      <directionalLight color={light.keyLight} intensity={timeOfDay === "day" ? 1.55 : 1.25} position={[-6, 11, 7]} />
      <directionalLight color={light.fillLight} intensity={0.42} position={[18, 7, -9]} />
      {light.stars > 0 && (
        <Stars radius={118} depth={70} count={light.stars} factor={2.1} saturation={0} fade speed={animate ? 0.25 : 0} />
      )}
      {light.celestial === "moon" ? (
        <Moon position={celestial} />
      ) : (
        <Sun position={celestial} color={light.reflection} />
      )}
      <IOSHomeOcean animate={animate} />
      <IOSHomeVessel animate={animate} />
      {timeOfDay !== "night" && (
        <Gulls flock={HOME_GULLS} animate={animate} center={[18, 0, -3]} />
      )}
      <IOSHomeIsland
        position={[distance, 0, 0]}
        rotation={[0, Math.PI / 2 - 0.16, 0]}
        scale={ISLAND_SCALE}
        animate={animate}
      />
    </>
  );
}

export default function HomeWorld({
  ratio,
  timeOfDay,
  paused = false,
  onContextLost,
}: {
  ratio: number;
  timeOfDay: TimeOfDay;
  paused?: boolean;
  onContextLost?: () => void;
}) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const rootRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const root = rootRef.current;
    if (!root || !onContextLost) return;
    const handleContextLost = (event: Event) => {
      event.preventDefault();
      onContextLost();
    };
    root.addEventListener("webglcontextlost", handleContextLost, true);
    return () => root.removeEventListener("webglcontextlost", handleContextLost, true);
  }, [onContextLost]);
  return (
    <div
      ref={rootRef}
      className="home-world-canvas"
      aria-hidden="true"
    >
      <Canvas
        camera={{ position: HOME_CAMERA, fov: 46, near: 0.08, far: 640 }}
        dpr={[1, 1.8]}
        frameloop={paused || !animate ? "demand" : "always"}
        gl={{ antialias: true, alpha: false, powerPreference: "high-performance" }}
      >
        <Scene ratio={ratio} timeOfDay={timeOfDay} animate={animate && !paused} />
      </Canvas>
    </div>
  );
}
