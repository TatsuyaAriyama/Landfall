import { useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Stars } from "@react-three/drei";
import * as THREE from "three";
import { boatProps } from "../boat";
import BoatModel, { NAVIGATOR_DECK_POSITION, NAVIGATOR_DECK_SCALE } from "./BoatModel";
import PhoenixModel from "./PhoenixModel";
import { Gulls, type GullFlock } from "./Gulls";
import { Horizon, Island, Wake } from "./VoyageScene";
import { Moon, PassingSwells, Sea, Sun } from "./SeaParts";
import { useNavigatorPose } from "./navigatorPose";
import { TIME_OF_DAY, type TimeOfDay } from "./timeOfDay";

const CAMERA_TARGET = new THREE.Vector3(0.2, 0.85, -0.5);
const LANDSCAPE_CAMERA: [number, number, number] = [-6.5, 2.55, 9.8];
const PORTRAIT_CAMERA: [number, number, number] = [-5.8, 3, 11.8];

const CELESTIAL_POSITION: Record<TimeOfDay, [number, number, number]> = {
  morning: [-5.4, 2.1, -8.5],
  day: [0.8, 6.1, -9.5],
  evening: [5.8, 2, -8.5],
  night: [5.6, 4.2, -8.5],
};

const SIGN_IN_GULLS: GullFlock = [
  { r: 3.8, y: 2.5, omega: 0.08, scale: 0.14, flap: 2.1, phase: 0 },
  { r: 4.8, y: 3.1, omega: -0.06, scale: 0.12, flap: 1.7, phase: 1.2 },
  { r: 4.2, y: 2.1, omega: 0.1, scale: 0.15, flap: 2.4, phase: 2.4 },
  { r: 5.4, y: 3.5, omega: -0.05, scale: 0.11, flap: 1.6, phase: 3.6 },
  { r: 3.5, y: 3, omega: 0.11, scale: 0.13, flap: 2.3, phase: 4.8 },
  { r: 5.8, y: 2.6, omega: 0.045, scale: 0.1, flap: 1.8, phase: 5.8 },
];

function ResponsiveCamera({ animate }: { animate: boolean }) {
  const { camera, size } = useThree();
  const base = useRef(new THREE.Vector3());

  useEffect(() => {
    const source = size.width / Math.max(size.height, 1) < 0.72 ? PORTRAIT_CAMERA : LANDSCAPE_CAMERA;
    base.current.set(...source);
    camera.position.copy(base.current);
    camera.lookAt(CAMERA_TARGET);
    camera.updateProjectionMatrix();
  }, [camera, size.height, size.width]);

  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    camera.position.set(
      base.current.x + Math.sin(time * 0.12) * 0.08,
      base.current.y + Math.sin(time * 0.2) * 0.035,
      base.current.z + Math.cos(time * 0.12) * 0.06,
    );
    camera.lookAt(CAMERA_TARGET);
  });

  return null;
}

function VoyageScene({ timeOfDay, animate }: { timeOfDay: TimeOfDay; animate: boolean }) {
  const palette = TIME_OF_DAY[timeOfDay];
  const parts = useMemo(() => boatProps(), []);
  const pose = useNavigatorPose(animate);
  const celestialPosition = CELESTIAL_POSITION[timeOfDay];

  return (
    <>
      <color attach="background" args={[palette.sky]} />
      <fog attach="fog" args={[palette.fog, 13, 35]} />
      <ambientLight color={palette.ambient} intensity={0.48} />
      <directionalLight color={palette.keyLight} intensity={1.2} position={[-6, 8, -5]} />
      <directionalLight color={palette.fillLight} intensity={0.22} position={[5, 3, 6]} />

      {palette.stars > 0 && (
        <Stars
          radius={42}
          depth={18}
          count={palette.stars}
          factor={2}
          saturation={0}
          fade
          speed={animate ? 0.45 : 0}
        />
      )}

      {palette.celestial === "moon" ? (
        <group position={celestialPosition} scale={0.38}>
          <Moon position={[0, 0, 0]} />
        </group>
      ) : (
        <Sun position={celestialPosition} color={palette.reflection} />
      )}

      <Sea
        moonX={celestialPosition[0]}
        animate={animate}
        seaColor={palette.sea}
        deepColor={palette.seaDeep}
        lightColor={palette.reflection}
        reflection={timeOfDay === "night" ? 0.5 : 0.34}
      />
      <Horizon />
      <PassingSwells animate={animate} />
      {timeOfDay !== "night" && (
        <Gulls
          flock={SIGN_IN_GULLS}
          animate={animate}
          center={[1.2, 0, -1.5]}
          opacity={0.54}
        />
      )}

      {/* Island has its own local offset. Bring it left so the desktop card never hides the destination. */}
      <group position={[0.8, -0.05, -6.3]} scale={0.82}>
        <Island />
      </group>

      <group position={[-1.65, 0, 0.45]} rotation={[0, 0.1, 0]} scale={0.68}>
        <Wake animate={animate} />
        <BoatModel parts={parts} animate={animate} />
        <group position={NAVIGATOR_DECK_POSITION} scale={NAVIGATOR_DECK_SCALE}>
          <PhoenixModel animate={animate} pose={pose} />
        </group>
      </group>

      <ResponsiveCamera animate={animate} />
    </>
  );
}

export default function SignInVoyageWorld({ timeOfDay }: { timeOfDay: TimeOfDay }) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );

  return (
    <Canvas
      aria-hidden="true"
      dpr={[1, 2]}
      frameloop={animate ? "always" : "demand"}
      camera={{ position: LANDSCAPE_CAMERA, fov: 40 }}
      gl={{ antialias: true, alpha: false, powerPreference: "high-performance" }}
    >
      <VoyageScene timeOfDay={timeOfDay} animate={animate} />
    </Canvas>
  );
}
