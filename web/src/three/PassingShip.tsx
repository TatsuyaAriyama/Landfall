import { useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";

// 遠くを横切る船の灯。
//
// 数分に一度、水平線の手前を小さな灯がゆっくり渡っていく。船体は見せない —
// 夜の海のこの距離では、他人の船は「灯ひとつ」でしかない。見えるのは、
// 同じ夜に誰かも走っているということだけ。
//
// 集中の邪魔をしないために、速い動きも中央での主張もさせない。渡りきるのに
// 約1分、間隔は数分。気づかない航海があってもいい — 長く続けた人ほど多く出会う。

const LIGHT = "#F3C065"; // ランタンと同じ灯の色

/// 灯までの距離と高さ。霧(12〜34)の外側だが、灯は fog={false} なので霞まない。
const DIST = 26;
const Y = 0.36;
/// 端から端まで。画面の外から入って外へ抜ける幅。
const SPAN = 30;
/// 渡りきるまでの秒数。1分弱 = 遠くの帆船の速さ。
const CROSS_SEC = 58;
/// 出入りのフェード(渡りの割合)。ぱっと現れると「点いた」に見えてしまう。
const FADE = 0.16;

/// 最初の1隻までと、そのあとの間隔(秒)。
const FIRST_MIN = 60;
const FIRST_MAX = 150;
const GAP_MIN = 150;
const GAP_MAX = 300;

const LAMP_GEO = new THREE.SphereGeometry(0.085, 10, 8);
const HALO_GEO = new THREE.SphereGeometry(0.24, 10, 8);
/// 水面に落ちる灯の影。月光の筋と同じく、こちらへ向かって細く伸びる。
const REFLECT_GEO = new THREE.PlaneGeometry(0.14, 1.6);

function span(min: number, max: number): number {
  return min + Math.random() * (max - min);
}

export default function PassingShip({ animate }: { animate: boolean }) {
  const group = useRef<THREE.Group>(null);
  const lamp = useRef<THREE.MeshBasicMaterial>(null);
  const halo = useRef<THREE.MeshBasicMaterial>(null);
  const reflect = useRef<THREE.MeshBasicMaterial>(null);

  const startAt = useRef<number | null>(null);
  const nextAt = useRef(span(FIRST_MIN, FIRST_MAX));
  const dir = useRef(1);

  useFrame(({ clock }) => {
    if (!animate) return;
    const g = group.current;
    if (!g) return;
    const time = clock.elapsedTime;

    // 待ち。時間が来たら、どちらの舷から渡るかを決めて動き出す。
    if (startAt.current === null) {
      if (time < nextAt.current) return;
      startAt.current = time;
      dir.current = Math.random() < 0.5 ? 1 : -1;
      return;
    }

    const p = (time - startAt.current) / CROSS_SEC;
    if (p >= 1) {
      startAt.current = null;
      nextAt.current = time + span(GAP_MIN, GAP_MAX);
      g.visible = false;
      return;
    }

    g.visible = true;
    g.position.set(
      dir.current * (SPAN / 2 - p * SPAN),
      Y + Math.sin(time * 0.7) * 0.03, // 波にわずかに上下する
      -DIST,
    );

    // 端では消えかけ、中ほどでいちばん明るい。
    const f = Math.min(1, Math.min(p, 1 - p) / FADE);
    if (lamp.current) lamp.current.opacity = 0.95 * f;
    if (halo.current) halo.current.opacity = 0.3 * f;
    if (reflect.current) reflect.current.opacity = 0.13 * f;
  });

  return (
    <group ref={group} visible={false}>
      <mesh geometry={LAMP_GEO}>
        <meshBasicMaterial
          ref={lamp}
          color={LIGHT}
          transparent
          opacity={0}
          fog={false}
          depthWrite={false}
        />
      </mesh>
      {/* にじみ。灯そのものより広く淡く、加算で重ねて「遠くの光」にする。 */}
      <mesh geometry={HALO_GEO}>
        <meshBasicMaterial
          ref={halo}
          color={LIGHT}
          transparent
          opacity={0}
          fog={false}
          depthWrite={false}
          blending={THREE.AdditiveBlending}
        />
      </mesh>
      {/* 水面の照り返し。灯の真下から手前へ伸ばす。 */}
      <mesh
        geometry={REFLECT_GEO}
        position={[0, -Y + 0.008, 0.8]}
        rotation={[-Math.PI / 2, 0, 0]}
      >
        <meshBasicMaterial
          ref={reflect}
          color={LIGHT}
          transparent
          opacity={0}
          fog={false}
          depthWrite={false}
        />
      </mesh>
    </group>
  );
}
