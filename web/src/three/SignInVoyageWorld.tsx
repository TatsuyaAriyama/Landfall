import { useLayoutEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Stars } from "@react-three/drei";
import BoatModel from "./BoatModel";
import PhoenixModel from "./PhoenixModel";
import { Gulls, type GullFlock } from "./Gulls";
import { Horizon, Island, Wake } from "./VoyageScene";
import { Moon, PassingSwells, Sea, Sun } from "./SeaParts";
import { useNavigatorPose } from "./navigatorPose";
import { boatProps } from "../boat";
import { SEA_LIGHT, type TimeOfDay } from "../timeOfDay";

// ログイン画面は「アプリの外」ではなく、同じ海へ入る直前の一場面。
// タイマー中の航海と同じ部品・光・時間帯を使い、未認証でも世界観を先に見せる。

const CAMERA_TARGET = new THREE.Vector3(0.2, 0.85, -0.5);
const BOAT_POSITION: [number, number, number] = [-1.65, 0, 0.45];
const ISLAND_POSITION: [number, number, number] = [6.8, -0.05, -7.2];

const CELESTIAL_POSITION: Record<TimeOfDay, [number, number, number]> = {
  morning: [-5.4, 2.1, -8.5],
  day: [0.8, 6.1, -9.5],
  evening: [5.8, 2.0, -8.5],
  night: [5.6, 4.2, -8.5],
};

const SIGN_IN_GULLS: GullFlock = [
  { r: 4.4, y: 2.5, omega: 0.08, scale: 0.16, flap: 2.0, phase: 0.1 },
  { r: 5.2, y: 3.1, omega: -0.06, scale: 0.14, flap: 1.7, phase: 1.1 },
  { r: 4.8, y: 2.2, omega: 0.1, scale: 0.17, flap: 2.4, phase: 2.0 },
  { r: 6.0, y: 3.4, omega: 0.052, scale: 0.13, flap: 1.6, phase: 3.0 },
  { r: 4.0, y: 2.9, omega: -0.09, scale: 0.16, flap: 2.2, phase: 4.1 },
  { r: 6.4, y: 2.5, omega: 0.045, scale: 0.12, flap: 1.8, phase: 5.0 },
];

function CameraAtSea({ animate }: { animate: boolean }) {
  const camera = useThree((state) => state.camera);
  const size = useThree((state) => state.size);
  const base = useRef(new THREE.Vector3());

  useLayoutEffect(() => {
    const portrait = size.width / Math.max(size.height, 1) < 0.72;
    base.current.set(
      portrait ? -5.8 : -6.5,
      portrait ? 3.0 : 2.55,
      portrait ? 11.8 : 9.8,
    );
    camera.position.copy(base.current);
    camera.lookAt(CAMERA_TARGET);
    camera.updateProjectionMatrix();
  }, [camera, size.height, size.width]);

  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    camera.position.set(
      base.current.x + Math.sin(time * 0.17) * 0.09,
      base.current.y + Math.sin(time * 0.29 + 0.8) * 0.045,
      base.current.z,
    );
    camera.lookAt(CAMERA_TARGET);
  });

  return null;
}

function SignInVoyageSea({
  timeOfDay,
  animate,
}: {
  timeOfDay: TimeOfDay;
  animate: boolean;
}) {
  const light = SEA_LIGHT[timeOfDay];
  const celestialPosition = CELESTIAL_POSITION[timeOfDay];
  const parts = useMemo(() => boatProps(), []);
  const pose = useNavigatorPose(animate);

  return (
    <>
      <color attach="background" args={[light.sky]} />
      <fog attach="fog" args={[light.fog, 13, 35]} />
      <ambientLight color={light.ambient} intensity={timeOfDay === "day" ? 0.9 : 0.52} />
      <directionalLight
        color={light.keyLight}
        intensity={timeOfDay === "day" ? 1.5 : 1.12}
        position={[-6, 8, -5]}
      />
      <directionalLight color={light.fillLight} intensity={0.28} position={[5, 4, 7]} />

      {light.stars > 0 && (
        <Stars
          radius={44}
          depth={20}
          count={light.stars}
          factor={2}
          saturation={0}
          fade
          speed={animate ? 0.45 : 0}
        />
      )}

      <group
        position={celestialPosition}
        scale={light.celestial === "moon" ? 0.52 : 0.82}
      >
        {light.celestial === "moon" ? (
          <Moon position={[0, 0, 0]} />
        ) : (
          <Sun position={[0, 0, 0]} color={light.reflection} />
        )}
      </group>

      <Sea
        moonX={celestialPosition[0]}
        animate={animate}
        seaColor={light.sea}
        deepColor={light.seaDeep}
        lightColor={light.reflection}
        reflection={timeOfDay === "day" ? 0.34 : 0.52}
      />
      <Horizon />
      <PassingSwells animate={animate} />
      {timeOfDay !== "night" && (
        <Gulls flock={SIGN_IN_GULLS} animate={animate} center={[0, 0, -1]} opacity={0.58} />
      )}

      <group position={ISLAND_POSITION} scale={0.68}>
        <Island />
      </group>

      <group position={BOAT_POSITION} rotation={[0, 0.1, 0]} scale={0.68}>
        <Wake animate={animate} />
        <BoatModel parts={parts} animate={animate} />
        <group position={[0.88, 0.57, 0.22]} scale={0.62}>
          <PhoenixModel animate={animate} pose={pose} />
        </group>
      </group>

      <CameraAtSea animate={animate} />
    </>
  );
}

export default function SignInVoyageWorld({ timeOfDay }: { timeOfDay: TimeOfDay }) {
  const animate = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  return (
    <Canvas
      aria-hidden="true"
      dpr={[1, 1.6]}
      frameloop={animate ? "always" : "demand"}
      camera={{ position: [-6.5, 2.55, 9.8], fov: 40 }}
      gl={{ antialias: true, powerPreference: "high-performance" }}
    >
      <SignInVoyageSea timeOfDay={timeOfDay} animate={animate} />
    </Canvas>
  );
}
