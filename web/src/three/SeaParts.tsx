import { useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";

// 夜の海の共有部品。BoatStudio(船スタジオ)とVoyageScene(目的地の航海)で使う。
// 配色は2Dの夜の入港(harborTeal地+sand塗り)と同じ世界。

export const NIGHT_BG = "#123830";
export const SEA_COLOR = "#1E5348";

// ジオメトリは色に依存しないので、モジュール読み込み時に一度だけ作る。
const MOON_GEO = new THREE.SphereGeometry(1.1, 20, 14);
const SEA_GEO = new THREE.CircleGeometry(30, 48);
const RIPPLE_GEO = new THREE.RingGeometry(0.9, 1.0, 48);

/// 月。遠景の発光球。霧に沈まないようfogを切る。
export function Moon({ position }: { position: [number, number, number] }) {
  return (
    <mesh geometry={MOON_GEO} position={position}>
      <meshStandardMaterial
        color={NIGHT_BG}
        emissive="#EADEBD"
        emissiveIntensity={0.95}
        fog={false}
      />
    </mesh>
  );
}

/// 海。大きな円盤。縁は霧で夜に溶ける。
export function Sea() {
  return (
    <mesh geometry={SEA_GEO} rotation={[-Math.PI / 2, 0, 0]}>
      <meshBasicMaterial color={SEA_COLOR} />
    </mesh>
  );
}

/// 波紋。船の周りをゆっくり広がって消えるリングを、位相をずらして3つ。
const RIPPLE_COUNT = 3;
const RIPPLE_PERIOD = 7;

export function Ripples({ animate }: { animate: boolean }) {
  const meshes = useRef<(THREE.Mesh | null)[]>([]);
  const mats = useRef<(THREE.MeshBasicMaterial | null)[]>([]);

  useFrame(({ clock }) => {
    if (!animate) return;
    for (let i = 0; i < RIPPLE_COUNT; i++) {
      const mesh = meshes.current[i];
      const mat = mats.current[i];
      if (!mesh || !mat) continue;
      const phase = (clock.elapsedTime / RIPPLE_PERIOD + i / RIPPLE_COUNT) % 1;
      const s = 0.8 + phase * 5.5;
      mesh.scale.set(s, s, 1);
      mat.opacity = Math.sin(Math.min(phase * 3, 1) * (Math.PI / 2)) * (1 - phase) * 0.2;
    }
  });

  return (
    <group>
      {Array.from({ length: RIPPLE_COUNT }, (_, i) => (
        <mesh
          key={i}
          ref={(m) => {
            meshes.current[i] = m;
          }}
          geometry={RIPPLE_GEO}
          rotation={[-Math.PI / 2, 0, 0]}
          position={[0, 0.02 + i * 0.004, 0]}
          scale={[1.5 + i * 1.6, 1.5 + i * 1.6, 1]}
        >
          <meshBasicMaterial
            ref={(m) => {
              mats.current[i] = m;
            }}
            color="#7FB8A6"
            transparent
            opacity={0.12 - i * 0.03}
            depthWrite={false}
          />
        </mesh>
      ))}
    </group>
  );
}
