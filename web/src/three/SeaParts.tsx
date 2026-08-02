import { useEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";

// 海の共有部品。既定は従来の夜色だが、航海シーンから時間帯の配色も受け取れる。

export const NIGHT_BG = "#123830";
export const SEA_COLOR = "#1E5348";

// ジオメトリは色に依存しないので、モジュール読み込み時に一度だけ作る。
const MOON_GEO = new THREE.SphereGeometry(1.1, 20, 14);
const SUN_GEO = new THREE.SphereGeometry(0.72, 20, 14);
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

/// 朝昼夕の太陽。時間帯ごとの色を受け、空の低さだけは呼び出し側で決める。
export function Sun({
  position,
  color,
}: {
  position: [number, number, number];
  color: string;
}) {
  return (
    <mesh geometry={SUN_GEO} position={position}>
      <meshBasicMaterial color={color} fog={false} />
    </mesh>
  );
}

// 海の色。中心=月明かりの溜まり、縁=夜の背景色へ溶ける。
const SEA_DEEP = "#123830"; // = NIGHT_BG。縁で背景に馴染ませる
const SEA_MOON = "#BFD6C6"; // 水面に落ちる月光のハイライト(淡い青緑)

// 円盤はXY平面。頂点座標(position.xy)をそのまま水面の2D座標として使う。
// local +Y = 世界の -Z(水平線=月の方向)、local +X = 世界の +X。
const SEA_VERT = /* glsl */ `
  varying vec2 vPos;
  void main() {
    vPos = position.xy;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;
const SEA_FRAG = /* glsl */ `
  precision mediump float;
  uniform vec3 uSea;
  uniform vec3 uDeep;
  uniform vec3 uMoon;
  uniform float uMoonX;
  uniform float uTime;
  uniform float uReflection;
  varying vec2 vPos;
  void main() {
    float r = length(vPos) / 30.0;
    // 縁だけ夜色へ溶かす(旧・霧と同じ範囲: 距離12〜30 ≒ r 0.4〜1.0)。
    // 船の周りの見える水面は海色のまま明るく保つ。
    vec3 col = mix(uSea, uDeep, smoothstep(0.42, 1.0, r));
    // 中心のほのかな月明かりの溜まりで、むしろ少し持ち上げる。
    col += (uMoon - uSea) * 0.06 * (1.0 - smoothstep(0.0, 0.5, r));
    // 月光の筋: 月の真下(uMoonX)に立ち、水平線側で強く手前で崩れる縦の光。
    float dx = vPos.x - uMoonX;
    float along = smoothstep(-5.0, 13.0, vPos.y);   // 月側(奥)ほど強い
    float width = mix(2.8, 0.7, along);             // 水平線に近いほど細い
    float band = exp(-(dx * dx) / (width * width));
    // さざ波で反射を分断する、ゆっくりした揺らぎ。
    float shimmer = 0.55 + 0.45 * sin(vPos.y * 1.1 - uTime * 1.4)
                                * sin(vPos.x * 0.9 + uTime * 0.7);
    float streak = clamp(band * along * shimmer, 0.0, 1.0) * uReflection;
    col = mix(col, uMoon, streak);
    gl_FragColor = vec4(col, 1.0);
  }
`;

/// 海。大きな円盤に、放射グラデーションと太陽/月の反射の筋。
/// moonX にそのシーンの天体のX座標を渡すと、反射がその真下に立つ。
export function Sea({
  moonX = 0,
  animate = true,
  seaColor = SEA_COLOR,
  deepColor = SEA_DEEP,
  lightColor = SEA_MOON,
  reflection = 0.5,
}: {
  moonX?: number;
  animate?: boolean;
  seaColor?: string;
  deepColor?: string;
  lightColor?: string;
  reflection?: number;
}) {
  const mat = useMemo(
    () =>
      new THREE.ShaderMaterial({
        vertexShader: SEA_VERT,
        fragmentShader: SEA_FRAG,
        uniforms: {
          uSea: { value: new THREE.Color(seaColor) },
          uDeep: { value: new THREE.Color(deepColor) },
          uMoon: { value: new THREE.Color(lightColor) },
          uMoonX: { value: moonX },
          uTime: { value: 0 },
          uReflection: { value: reflection },
        },
      }),
    [moonX, seaColor, deepColor, lightColor, reflection],
  );
  useEffect(() => () => mat.dispose(), [mat]);

  useFrame(({ clock }) => {
    if (animate) mat.uniforms.uTime.value = clock.elapsedTime;
  });

  return <mesh geometry={SEA_GEO} rotation={[-Math.PI / 2, 0, 0]} material={mat} />;
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

// ---- 後ろへ流れていく水の筋 ----
// 船を世界の原点に置いたまま「進んでいる」ことを伝える主役なので、
// はっきり見える濃さで流す(薄すぎると船が止まって見える)。
// 手前(カメラ寄り=zが大きい)を速く、奥を遅くして視差をつける。
// 速さは「ゆっくり進む帆船」に合わせる。船体は約1.3単位なので、手前の筋が
// 毎秒1.2単位 ≒ 船一隻ぶん/秒。これ以上速いとモーターボートに見える。

const SWELL_SAND = "#EADEBD";
const SWELL_GEO = new THREE.PlaneGeometry(1.6, 0.05);
/// うねりが流れる範囲。端まで行ったら反対側へ回して継ぎ目なく続ける。
const SWELL_SPAN = 34;
const SWELL_MIN_X = -17;
const SWELL_LAYERS = [
  { count: 14, zMin: -8, zSpread: 6, speed: 0.45, opacity: 0.1, len: 1.15 },
  { count: 12, zMin: 0.8, zSpread: 4.6, speed: 1.2, opacity: 0.22, len: 0.8 },
];

/// 流れる水の筋。`flow` は船足(1=通常、0=止まる)。即座に切り替えず減衰で寄せる
/// ので、錨を下ろしても舫っても、水は惰性をもって静まっていく。
export function PassingSwells({
  animate,
  flow: target = 1,
}: {
  animate: boolean;
  flow?: number;
}) {
  const layers = useRef<(THREE.Group | null)[]>([]);
  const flow = useRef(target);
  // 毎フレーム乱数を引かない。決まった散らし方で並べる。
  const swells = useMemo(
    () =>
      SWELL_LAYERS.map((layer, li) =>
        Array.from({ length: layer.count }, (_, i) => ({
          x: SWELL_MIN_X + ((i * 2.4 + li * 1.3) % SWELL_SPAN),
          z: layer.zMin + ((i * 5) % 7) * (layer.zSpread / 7),
          scale: layer.len * (0.6 + ((i * 3) % 6) / 6),
          opacity: layer.opacity * (0.7 + ((i * 7) % 4) / 6),
        })),
      ),
    [],
  );

  useFrame((_, delta) => {
    if (!animate) return;
    flow.current = THREE.MathUtils.damp(flow.current, target, 0.7, delta);
    SWELL_LAYERS.forEach((layer, li) => {
      const group = layers.current[li];
      if (!group) return;
      for (const child of group.children) {
        child.position.x -= delta * layer.speed * flow.current;
        if (child.position.x < SWELL_MIN_X) child.position.x += SWELL_SPAN;
      }
    });
  });

  return (
    <>
      {swells.map((list, li) => (
        <group
          key={li}
          ref={(g) => {
            layers.current[li] = g;
          }}
        >
          {list.map((s, i) => (
            <mesh
              key={i}
              geometry={SWELL_GEO}
              position={[s.x, 0.035 + li * 0.004, s.z]}
              rotation={[-Math.PI / 2, 0, 0]}
              scale={[s.scale, 1, 1]}
            >
              <meshBasicMaterial
                color={SWELL_SAND}
                transparent
                opacity={s.opacity}
                depthWrite={false}
              />
            </mesh>
          ))}
        </group>
      ))}
    </>
  );
}
