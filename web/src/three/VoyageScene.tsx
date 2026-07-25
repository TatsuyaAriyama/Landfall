import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import * as THREE from "three";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Stars } from "@react-three/drei";
import BoatModel from "./BoatModel";
import PhoenixModel from "./PhoenixModel";
import { Moon, NIGHT_BG, Ripples, Sea } from "./SeaParts";
import { Gulls, type GullFlock } from "./Gulls";
import { boatProps, navigatorPose } from "../boat";
import { shortDateLabel } from "../i18n";

// 目的地の航海シーン。自分の船が、夜の海を島へ向かって走っている。
// 記録するほど(ratioが増えるほど)船が島に近づく。BoatStudioと同じ
// 品質言語(低ポリ+flatShading、夜の海、星、月、波紋)に従う。

/// 航路に置くステップ1つ分。達成の有無と、いつ辿り着いたか
/// (iOS の VoyageStep と同じ形)。
export interface VoyageStep {
  done: boolean;
  doneAt?: Date;
}

export interface VoyageSceneProps {
  name: string;
  ratio: number; // 0..1(島までの近さ)
  label: string; // 残り表示(「あと3時間」など)
  onClick?: () => void;
  /// ステップ目標のとき、各ステップの達成状況(順序どおり)。航路に小島が浮かぶ。
  steps?: VoyageStep[];
  /// 見出しの下に添える小さな一言(直近で辿り着いた小島と日付など)。
  footnote?: string;
  /// 見出しに重ねる追加UI(完了ゴールのチェックボタンなど)。
  children?: ReactNode;
}

const SAND = "#EADEBD";
const BEACH = "#DCCFA9";

// カメラは固定の斜め視点。航路は左(X_START)から島の手前(X_END)まで。
// (VoyageWorld=没入エディタが同じ構図から入場するため、位置関係を共有する)
// カード(ホームの主役)の establishing 構図。航海の全景を引きで一望する
// (没入エディタの入場もここから始まる。iOS cardCam と同値)。
const CAM_POS: [number, number, number] = [0.6, 7.2, 12.5];
const CAM_TARGET = new THREE.Vector3(-2.2, 0.5, 0.2);
const CAM_FOV = 42;
// ステップの島は「そう簡単には届かない目標」なので、航路を長くとって一つ一つを
// 遠くに置く(島の間に開けた海を残す)。iOS VoyageSceneKit と同値。
// カードの空を旋回するカモメ。半径・高さ・大きさはこの構図(横長327x200・fov42・
// 見下ろし)に投影して決めた: カメラのtargetの真上を回らせ、水平線(sy≈29)より下、
// 船の航路(sy≈87〜111)より上の水面帯に収まる組み合わせ。5羽とも常に画面内で、
// 翼幅は9〜19px(中央値12px)。カードは小さいので、ここは控えめな数に留める。
const CARD_GULLS: GullFlock = [
  { r: 3.0, y: 3.0, omega: 0.09, scale: 0.3, flap: 2.1, phase: 0.0 },
  { r: 4.0, y: 3.6, omega: -0.07, scale: 0.28, flap: 1.8, phase: 1.3 },
  { r: 3.0, y: 3.6, omega: 0.12, scale: 0.28, flap: 2.4, phase: 2.6 },
  { r: 5.0, y: 3.0, omega: -0.055, scale: 0.32, flap: 1.6, phase: 3.9 },
  { r: 4.0, y: 2.4, omega: 0.1, scale: 0.34, flap: 2.2, phase: 5.2 },
];
/// カモメが旋回する中心。カメラが見ている先(CAM_TARGET)の真上。
const CARD_GULL_CENTER: [number, number, number] = [-2.2, 0, 0.2];

export const X_START = -9.0;
export const X_END = 4.2;

// ジオメトリは色に依存しないので、モジュール読み込み時に一度だけ作る。
const HILL_GEO = new THREE.ConeGeometry(1.25, 1.05, 7);
const HILL2_GEO = new THREE.ConeGeometry(0.85, 0.72, 6);
const KNOLL_GEO = new THREE.SphereGeometry(0.6, 8, 6);
const BEACH_GEO = new THREE.CylinderGeometry(1.9, 2.05, 0.07, 9);
const WAKE_GEO = new THREE.PlaneGeometry(2.3, 0.4);
const HORIZON_GEO = new THREE.PlaneGeometry(60, 0.08);

// ステップ = 航路に浮かぶ小さな島。未達=静かな砂の小島、達成=緑が芽吹き浜に灯がともる。
// 船はこれらを巡って島へ向かう(ピン=柱+玉 は廃止)。
const ISLET_BEACH_GEO = new THREE.CylinderGeometry(0.56, 0.74, 0.09, 9);
const ISLET_HILL_LIT_GEO = new THREE.ConeGeometry(0.46, 0.72, 6);
const ISLET_HILL_DIM_GEO = new THREE.ConeGeometry(0.46, 0.52, 6);
const ISLET_KNOLL_LIT_GEO = new THREE.ConeGeometry(0.3, 0.4, 6);
const ISLET_KNOLL_DIM_GEO = new THREE.ConeGeometry(0.3, 0.3, 6);
const ISLET_ROCK_GEO = new THREE.SphereGeometry(0.17, 6, 5);
const ISLET_GLOW_GEO = new THREE.SphereGeometry(0.085, 10, 8);
const ISLET_EMBER = "#F3C065"; // 浜の灯

// 制覇の旗(達成した島の頂に立てる)。旗竿+風になびく三角旗。
const FLAG_POLE_H = 0.5;
const FLAG_POLE_GEO = new THREE.CylinderGeometry(0.015, 0.015, FLAG_POLE_H, 6);
const FLAG_CLOTH_GEO = (() => {
  const s = new THREE.Shape();
  s.moveTo(0, 0);
  s.lineTo(0, 0.17);
  s.lineTo(0.3, 0.085);
  s.closePath();
  return new THREE.ShapeGeometry(s);
})();
const RETURN_ORANGE = "#F5822A"; // 帰帆色(旗・達成日)

/// ステップ位置を航路上に等間隔で割り付ける。両端(出発・島)は空ける。
export function stepBuoyX(index: number, total: number): number {
  return X_START + ((index + 1) / (total + 1)) * (X_END - X_START);
}

/// 低ポリの島。半球と円錐を組んだ丘+水面の際のわずかな浜。
export function Island() {
  return (
    <group position={[3.5, 0, -0.9]}>
      <mesh geometry={BEACH_GEO} position={[0, 0.03, 0.1]}>
        <meshStandardMaterial color={BEACH} flatShading roughness={0.95} />
      </mesh>
      <mesh geometry={HILL_GEO} position={[0, 0.5, 0]} rotation={[0, 0.4, 0]}>
        <meshStandardMaterial color={SAND} flatShading roughness={0.9} />
      </mesh>
      <mesh geometry={HILL2_GEO} position={[0.8, 0.34, 0.35]} rotation={[0, 1.1, 0]}>
        <meshStandardMaterial color={SAND} flatShading roughness={0.9} />
      </mesh>
      <mesh geometry={KNOLL_GEO} position={[-0.85, 0.08, 0.25]}>
        <meshStandardMaterial color={SAND} flatShading roughness={0.9} />
      </mesh>
    </group>
  );
}

/// 水平線。霧に沈む海の縁に、sandの淡い一線(2Dカードの.dest-horizon風)。
export function Horizon() {
  return (
    <mesh geometry={HORIZON_GEO} position={[0, 0.04, -20]}>
      <meshBasicMaterial
        color={SAND}
        transparent
        opacity={0.22}
        fog={false}
        depthWrite={false}
      />
    </mesh>
  );
}

/// 航跡。船尾から後ろへ、白い帯が尾に向かってフェードする。
export function Wake({ animate }: { animate: boolean }) {
  const mat = useRef<THREE.MeshBasicMaterial>(null);
  const texture = useMemo(() => {
    const c = document.createElement("canvas");
    c.width = 64;
    c.height = 8;
    const ctx = c.getContext("2d");
    if (ctx) {
      const g = ctx.createLinearGradient(0, 0, 64, 0);
      g.addColorStop(0, "rgba(255,255,255,0)"); // 尾は消える
      g.addColorStop(0.7, "rgba(255,255,255,0.5)");
      g.addColorStop(1, "rgba(255,255,255,0.9)"); // 船尾側が濃い
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, 64, 8);
    }
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }, []);
  useEffect(() => () => texture.dispose(), [texture]);

  useFrame(({ clock }) => {
    if (!animate || !mat.current) return;
    mat.current.opacity = 0.34 + Math.sin(clock.elapsedTime * 1.4) * 0.07;
  });

  return (
    <mesh geometry={WAKE_GEO} rotation={[-Math.PI / 2, 0, 0]} position={[-2.15, 0.025, 0]}>
      <meshBasicMaterial
        ref={mat}
        map={texture}
        transparent
        opacity={0.34}
        depthWrite={false}
      />
    </mesh>
  );
}

// 小島の素材(色に依存しないので一度だけ作る)。浜=砂、丘=達成で緑/未達で砂、岩、灯。
const ISLET_BEACH_MAT = new THREE.MeshStandardMaterial({
  color: BEACH,
  flatShading: true,
  roughness: 0.95,
});
const ISLET_HILL_LIT_MAT = new THREE.MeshStandardMaterial({
  color: "#5DCAA5", // 芽吹いた緑(seaGreen)
  flatShading: true,
  roughness: 0.9,
});
const ISLET_HILL_DIM_MAT = new THREE.MeshStandardMaterial({
  color: SAND,
  flatShading: true,
  roughness: 0.9,
});
const ISLET_ROCK_MAT = new THREE.MeshStandardMaterial({
  color: "#7A6B57",
  flatShading: true,
  roughness: 0.95,
});
const ISLET_GLOW_MAT = new THREE.MeshStandardMaterial({
  color: ISLET_EMBER,
  emissive: ISLET_EMBER,
  emissiveIntensity: 1.4,
  roughness: 0.5,
  fog: false,
});

const FLAG_POLE_MAT = new THREE.MeshStandardMaterial({
  color: "#5A2A15",
  flatShading: true,
  roughness: 0.8,
});
const FLAG_CLOTH_MAT = new THREE.MeshStandardMaterial({
  color: RETURN_ORANGE,
  flatShading: true,
  roughness: 0.9,
  side: THREE.DoubleSide,
});

/// 3D空間に浮かぶ小さな文字板(常にカメラを向く)。達成日の記録に使う。
/// Canvas に描いた文字をテクスチャにする(iOS makeDateLabel と同じ作り)。
function DateLabel({ text, y }: { text: string; y: number }) {
  const texture = useMemo(() => {
    const c = document.createElement("canvas");
    const scale = 2;
    const font = `500 ${22 * scale}px -apple-system, system-ui, sans-serif`;
    const ctx0 = c.getContext("2d");
    if (!ctx0) return null;
    ctx0.font = font;
    const w = ctx0.measureText(text).width;
    c.width = Math.ceil(w + 18 * scale);
    c.height = Math.ceil(34 * scale);
    const ctx = c.getContext("2d");
    if (!ctx) return null;
    ctx.font = font;
    ctx.fillStyle = RETURN_ORANGE;
    ctx.textBaseline = "middle";
    ctx.fillText(text, 9 * scale, c.height / 2);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }, [text]);
  useEffect(() => () => texture?.dispose(), [texture]);
  if (!texture) return null;
  const h = 0.46;
  const w = h * (texture.image.width / texture.image.height);
  return (
    <sprite position={[0, y, 0]} scale={[w, h, 1]}>
      <spriteMaterial map={texture} transparent depthWrite={false} fog={false} />
    </sprite>
  );
}

/// 制覇の旗。丘の頂に立てる旗竿と、風になびく三角旗。
function StepFlag({ hillHeight, phase }: { hillHeight: number; phase: number }) {
  const flag = useRef<THREE.Group>(null);
  useFrame(({ clock }) => {
    if (flag.current) {
      flag.current.rotation.y = Math.sin(clock.elapsedTime * 4.6 + phase) * 0.2;
    }
  });
  return (
    <group ref={flag} position={[-0.05, 0.09 + hillHeight, 0]}>
      <mesh geometry={FLAG_POLE_GEO} material={FLAG_POLE_MAT} position={[0, FLAG_POLE_H / 2, 0]} />
      <mesh
        geometry={FLAG_CLOTH_GEO}
        material={FLAG_CLOTH_MAT}
        position={[0.012, FLAG_POLE_H - 0.2, 0]}
      />
    </group>
  );
}

/// 航路に浮かぶステップの小島。達成した島は緑が芽吹き、旗が立ち、浜に灯がともる。
/// `doneAt` があれば、いつ辿り着いたかを島の上に小さなオレンジ文字で掲げる。
/// onToggleがあれば当たり判定を付けてタップで達成/取消。
export function StepBuoys({
  steps,
  onToggle,
}: {
  steps: VoyageStep[];
  onToggle?: (index: number) => void;
}) {
  const n = steps.length;
  return (
    <>
      {steps.map(({ done, doneAt }, i) => (
        // 前後に散らして群島感を出す(一直線に並べない)。
        <group key={i} position={[stepBuoyX(i, n), 0, 0.7 + (i % 2) * 0.7]}>
          {/* 浜 */}
          <mesh geometry={ISLET_BEACH_GEO} material={ISLET_BEACH_MAT} position={[0, 0.045, 0]} />
          {/* 丘(達成=緑で高く / 未達=砂で低め) */}
          <mesh
            geometry={done ? ISLET_HILL_LIT_GEO : ISLET_HILL_DIM_GEO}
            material={done ? ISLET_HILL_LIT_MAT : ISLET_HILL_DIM_MAT}
            position={[-0.05, 0.09 + (done ? 0.36 : 0.26), 0]}
            rotation={[0, i * 1.7, 0]}
          />
          {/* 副丘(二つ目の起伏でシルエットに厚みを) */}
          <mesh
            geometry={done ? ISLET_KNOLL_LIT_GEO : ISLET_KNOLL_DIM_GEO}
            material={done ? ISLET_HILL_LIT_MAT : ISLET_HILL_DIM_MAT}
            position={[0.34, 0.09 + (done ? 0.2 : 0.15), 0.12]}
            rotation={[0, i * 0.9, 0]}
          />
          {/* 小岩(シルエットの変化) */}
          <mesh
            geometry={ISLET_ROCK_GEO}
            material={ISLET_ROCK_MAT}
            position={[-0.42, 0.07, 0.18]}
            scale={[1, 0.66, 1]}
          />
          {/* 達成した島の浜の灯(たき火/ランタン) */}
          {done && (
            <mesh geometry={ISLET_GLOW_GEO} material={ISLET_GLOW_MAT} position={[0.16, 0.17, 0.5]} />
          )}
          {/* 制覇の証の旗。島ごとに位相をずらして同じ風になびかせる */}
          {done && <StepFlag hillHeight={0.72} phase={i * 0.8} />}
          {/* いつ辿り着いたかを、島の上に小さく残す */}
          {done && doneAt && <DateLabel text={shortDateLabel(doneAt)} y={0.72 + 0.62} />}
          {onToggle && (
            <mesh
              position={[0, 0.3, 0]}
              onClick={(e) => {
                e.stopPropagation();
                onToggle(i);
              }}
            >
              <cylinderGeometry args={[0.8, 0.8, 1.0, 8]} />
              <meshBasicMaterial transparent opacity={0} depthWrite={false} />
            </mesh>
          )}
        </group>
      ))}
    </>
  );
}

/// シーン本体。夜の海と島、ratioに応じた位置へlerpで進む船、微かなカメラの揺れ。
function VoyageSea({
  ratio,
  animate,
  steps,
}: {
  ratio: number;
  animate: boolean;
  steps?: VoyageStep[];
}) {
  const parts = useMemo(() => boatProps(), []);
  const travel = useRef<THREE.Group>(null);
  const targetX = X_START + Math.min(Math.max(ratio, 0), 1) * (X_END - X_START);
  const xRef = useRef(targetX);
  const invalidate = useThree((s) => s.invalidate);
  const camera = useThree((s) => s.camera);

  // 固定の斜め視点。demandフレームループでも初回から正しい向きで描く。
  useLayoutEffect(() => {
    camera.lookAt(CAM_TARGET);
    invalidate();
  }, [camera, invalidate]);

  // reduced-motion時はアニメせず、ratioの位置へ直接置いて一度だけ描く。
  useLayoutEffect(() => {
    if (animate) return;
    xRef.current = targetX;
    if (travel.current) travel.current.position.x = targetX;
    invalidate();
  }, [targetX, animate, invalidate]);

  useFrame((state, delta) => {
    if (!animate) return;
    const time = state.clock.elapsedTime;
    // ratioが増えると滑らかに前進する。
    xRef.current = THREE.MathUtils.damp(xRef.current, targetX, 1.1, delta);
    if (travel.current) travel.current.position.x = xRef.current;
    // カメラのごくわずかな揺れ(酔わない振幅)。
    camera.position.x = CAM_POS[0] + Math.sin(time * 0.22) * 0.07;
    camera.position.y = CAM_POS[1] + Math.sin(time * 0.35 + 1.0) * 0.04;
    camera.lookAt(CAM_TARGET);
  });

  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 12, 30]} />
      {/* 月光: BoatStudioと同じトーン。影は使わない。 */}
      <ambientLight color="#ffe9c8" intensity={0.45} />
      <directionalLight color="#EADEBD" intensity={1.15} position={[-6, 8, -5]} />
      <directionalLight color="#5DCAA5" intensity={0.2} position={[5, 3, 6]} />
      <Stars
        radius={42}
        depth={18}
        count={380}
        factor={2.0}
        saturation={0}
        fade
        speed={animate ? 0.5 : 0}
      />
      <Moon position={[1.8, 1.25, -14]} />
      <Sea moonX={1.8} animate={animate} />
      <Horizon />
      <Gulls flock={CARD_GULLS} animate={animate} center={CARD_GULL_CENTER} />
      <Island />
      {/* ステップ目標なら、航路に目印のブイを浮かべる(達成で点灯)。 */}
      {steps && steps.length > 0 && <StepBuoys steps={steps} />}
      {/* 航路上の船。揺れ(BoatModel内)+波紋+航跡ごと進む。 */}
      <group ref={travel} position={[xRef.current, 0, 0]} rotation={[0, 0.1, 0]} scale={0.55}>
        <Ripples animate={animate} />
        <Wake animate={animate} />
        <BoatModel parts={parts} animate={animate} />
        {/* 甲板の自分の航海士。舳先を見て進む姿にしたいので船首寄りに立たせる。
            原点が足元なので舷縁(y≈0.5〜0.58)の上に置き、マストとメインセイルを
            避けつつ舳先の反りに脚が入らない x=0.88、帆に隠れない手前の舷側 z=+0.22。
            姿は装いで選んだもの。iOS VoyageSceneKit と同値。 */}
        <group position={[0.88, 0.57, 0.22]} scale={0.62}>
          <PhoenixModel animate={animate} pose={navigatorPose()} />
        </group>
      </group>
    </>
  );
}

/// 目的地カードの3D版。島名と残りはCanvas外のHTMLオーバーレイで重ねる。
export default function VoyageScene({
  name,
  ratio,
  label,
  onClick,
  steps,
  footnote,
  children,
}: VoyageSceneProps) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const rootRef = useRef<HTMLDivElement>(null);
  // カードがスクロールで画面外に出たらrAFループを止める(電池・GPU対策)。
  // IntersectionObserverが無い環境では従来どおり常時描画にフォールバック。
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    const el = rootRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(([entry]) => {
      setVisible(entry.isIntersecting);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={rootRef}
      className="voyage-scene"
      role="button"
      tabIndex={0}
      aria-label={label ? `${name} · ${label}` : name}
      onClick={onClick}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick?.();
        }
      }}
    >
      <div className="voyage-head">
        <span className="voyage-name">{name}</span>
        <span className="voyage-remaining">{label}</span>
        {children}
      </div>
      {/* 直近に辿り着いた小島と、その日付(小さなオレンジ文字) */}
      {footnote && <span className="voyage-footnote">{footnote}</span>}
      <Canvas
        dpr={[1, 2]}
        frameloop={animate && visible ? "always" : "demand"}
        camera={{ position: CAM_POS, fov: CAM_FOV }}
      >
        <VoyageSea ratio={ratio} animate={animate} steps={steps} />
      </Canvas>
    </div>
  );
}
