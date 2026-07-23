import { useEffect, useMemo, useRef } from "react";
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
  varying vec2 vPos;
  void main() {
    float r = length(vPos) / 30.0;
    // 放射グラデーション: 中心は海色、縁は夜色へ(霧の代わりに背景へ溶かす)。
    vec3 col = mix(uSea, uDeep, smoothstep(0.08, 0.62, r));
    // 中心のほのかな月明かりの溜まり。
    col += (uMoon - uSea) * 0.05 * (1.0 - smoothstep(0.0, 0.45, r));
    // 月光の筋: 月の真下(uMoonX)に立ち、水平線側で強く手前で崩れる縦の光。
    float dx = vPos.x - uMoonX;
    float along = smoothstep(-5.0, 13.0, vPos.y);   // 月側(奥)ほど強い
    float width = mix(2.8, 0.7, along);             // 水平線に近いほど細い
    float band = exp(-(dx * dx) / (width * width));
    // さざ波で反射を分断する、ゆっくりした揺らぎ。
    float shimmer = 0.55 + 0.45 * sin(vPos.y * 1.1 - uTime * 1.4)
                                * sin(vPos.x * 0.9 + uTime * 0.7);
    float streak = clamp(band * along * shimmer, 0.0, 1.0) * 0.5;
    col = mix(col, uMoon, streak);
    gl_FragColor = vec4(col, 1.0);
  }
`;

/// 海。大きな円盤に、放射グラデーションと月光の筋(月の真下に立つ揺らぐ光)。
/// moonX にそのシーンの月のX座標を渡すと、反射がその真下に立つ。
export function Sea({ moonX = 0, animate = true }: { moonX?: number; animate?: boolean }) {
  const mat = useMemo(
    () =>
      new THREE.ShaderMaterial({
        vertexShader: SEA_VERT,
        fragmentShader: SEA_FRAG,
        uniforms: {
          uSea: { value: new THREE.Color(SEA_COLOR) },
          uDeep: { value: new THREE.Color(SEA_DEEP) },
          uMoon: { value: new THREE.Color(SEA_MOON) },
          uMoonX: { value: moonX },
          uTime: { value: 0 },
        },
      }),
    [moonX],
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
