import { useLayoutEffect, useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";

// 夜空を旋回する小さなカモメ。航海中の世界(VoyagingWorld)と
// ホームの目的地カード(VoyageScene)で共有する。
//
// 翼は片方ぶんの三角形一枚。低ポリ+フラットの言語に合わせ、砂色の薄い塗りで
// 夜空に浮かせる(霧は切る。遠さは大きさで表す)。左右のメッシュをx反転で
// 対にしてあるので、同じ rotation.z で対称に羽ばたく。
//
// 動きは直線に流すのではなく、ある点のまわりをゆっくり旋回させる。横切る方式は
// 視野の狭い構図だと「一瞬横切って、あとは長い空白」になってしまう。旋回なら
// 常にどれかが空にいる。
//
// 半径・高さ・大きさは構図ごとに投影して決める必要があるので、群れの定義は
// 呼び出し側から渡す(GullFlock)。カメラに近すぎる軌道を通すと巨大に映るので、
// 半径を広げるときは必ず画面上の翼幅を確かめること。

const SAND = "#EADEBD";

const GULL_WING_GEO = (() => {
  const g = new THREE.BufferGeometry();
  // 付け根(0,0,0) → 翼端(1, 0.06, -0.12) → 後縁(0.34, 0, 0.24)
  g.setAttribute(
    "position",
    new THREE.Float32BufferAttribute([0, 0, 0, 1, 0.06, -0.12, 0.34, 0, 0.24], 3),
  );
  g.computeVertexNormals();
  return g;
})();

/// 翼を上げ気味に保つ基準角(負で上がる)。平たいままだと紙飛行機に見える。
const WING_REST = -0.22;

/// カモメ一羽の軌道。
export interface GullOrbit {
  /// 旋回の半径。
  r: number;
  /// 高さ。
  y: number;
  /// 角速度(rad/s)。負で逆回り。
  omega: number;
  /// 大きさ。翼幅は scale * 2。
  scale: number;
  /// 羽ばたきの速さ。
  flap: number;
  /// 位相。羽ばたきと旋回の開始位置をずらす。
  phase: number;
}

export type GullFlock = readonly GullOrbit[];

function Gull({
  scale,
  flap,
  phase,
  animate,
}: {
  scale: number;
  flap: number;
  phase: number;
  animate: boolean;
}) {
  const wings = useRef<(THREE.Mesh | null)[]>([]);

  // 静止時(reduced-motion)でも翼はV字で止めておく。
  useLayoutEffect(() => {
    if (wings.current[0]) wings.current[0].rotation.z = WING_REST;
    if (wings.current[1]) wings.current[1].rotation.z = -WING_REST;
  });

  useFrame((state) => {
    if (!animate) return;
    const t = state.clock.elapsedTime * flap + phase;
    const beat = WING_REST + Math.sin(t) * 0.34;
    if (wings.current[0]) wings.current[0].rotation.z = beat;
    if (wings.current[1]) wings.current[1].rotation.z = -beat;
  });

  return (
    <group scale={scale}>
      {[0, 1].map((i) => (
        <mesh
          key={i}
          ref={(m) => {
            wings.current[i] = m;
          }}
          geometry={GULL_WING_GEO}
          scale={[i === 0 ? -1 : 1, 1, 1]}
        >
          <meshBasicMaterial
            color={SAND}
            side={THREE.DoubleSide}
            transparent
            opacity={0.5}
            fog={false}
          />
        </mesh>
      ))}
    </group>
  );
}

/// 夜空をゆっくり旋回するカモメたち。
/// center を渡すとその真上を回る(既定は原点)。
export function Gulls({
  flock,
  animate,
  center = [0, 0, 0],
}: {
  flock: GullFlock;
  animate: boolean;
  center?: [number, number, number];
}) {
  const birds = useRef<(THREE.Group | null)[]>([]);

  const place = (node: THREE.Group, g: GullOrbit, time: number) => {
    const a = g.phase + time * g.omega;
    node.position.set(
      center[0] + Math.cos(a) * g.r,
      // ゆるやかな上下。羽ばたきとは別の周期にする。
      center[1] + g.y + Math.sin(time * 0.4 + g.phase) * 0.22,
      center[2] + Math.sin(a) * g.r,
    );
    // 進む向きへ機首を向ける。翼の形は -z を前として作ってある。
    const vx = -Math.sin(a) * g.omega;
    const vz = Math.cos(a) * g.omega;
    node.rotation.y = Math.atan2(-vx, -vz);
    // 旋回の内側へわずかに傾ける。
    node.rotation.z = g.omega > 0 ? -0.18 : 0.18;
  };

  // 静止時でも、ちゃんと空にいる位置に置く。
  useLayoutEffect(() => {
    flock.forEach((g, i) => {
      const node = birds.current[i];
      if (node) place(node, g, 0);
    });
  });

  useFrame((state) => {
    if (!animate) return;
    const time = state.clock.elapsedTime;
    flock.forEach((g, i) => {
      const node = birds.current[i];
      if (node) place(node, g, time);
    });
  });

  return (
    <>
      {flock.map((g, i) => (
        <group
          key={i}
          ref={(node) => {
            birds.current[i] = node;
          }}
        >
          <Gull scale={g.scale} flap={g.flap} phase={g.phase} animate={animate} />
        </group>
      ))}
    </>
  );
}
