import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import {
  Canvas,
  useFrame,
  useThree,
  type RootState,
  type ThreeEvent,
} from "@react-three/fiber";
import { Html, Stars } from "@react-three/drei";
import BoatModel from "./BoatModel";
import { Moon, NIGHT_BG, Ripples, Sea } from "./SeaParts";
import { Horizon, Island } from "./VoyageScene";
import { boatPartsFromIds } from "../boat";
import {
  ROOM_MAX_MEMBERS,
  fetchMonth,
  type HarborMember,
  type HarborRoom,
} from "../harbor";
import { saveCanvas } from "../share";
import { demoLitMemberIds, isDemo } from "../demo";
import { lang, t } from "../i18n";

// 港の「みんなの海」。参加メンバー全員の船が同じ夜の海に浮かび、
// 同じ島(港の名前を持つ島)へ向かって並走している世界。
// VoyageScene/BoatStudioと同じ品質言語(低ポリ+flatShading、夜の海、星、月、波紋)。
//
// 反ストリークの約束: 船の位置は進捗・量・順位では決めない。
// uidのハッシュだけで決まる固定レーン+有機的な前後オフセット。誰も先頭ではない。

export interface HarborWorldProps {
  room: HarborRoom;
  members: HarborMember[];
  onSelectMember?: (member: HarborMember) => void;
}

const CAM_POS: [number, number, number] = [0.2, 2.6, 8.4];
const CAM_TARGET: [number, number, number] = [0.5, 0.35, 0];
// 島(VoyageSceneのIslandは[3.5,0,-0.9]基準)を右奥へ寄せる分。
const ISLAND_SHIFT: [number, number, number] = [0.9, 0, -1.9];
const ISLAND_TOP: [number, number, number] = [
  3.5 + ISLAND_SHIFT[0],
  1.6,
  -0.9 + ISLAND_SHIFT[2],
];
// 並走のレーン(手前→奥)。中央寄せで使う。前後の基準位置はレーンごとに
// 互い違いにして、ハッシュの揺らぎが重なっても船同士がぶつからないようにする。
const LANES_Z = [2.05, 0.65, -0.75, -2.15];
const LANES_X = [0.15, -2.05, 0.75, -1.35];

// ジオメトリは色に依存しないので、モジュール読み込み時に一度だけ作る。
const LANTERN_GEO = new THREE.SphereGeometry(0.16, 10, 8);
const LANTERN_POLE_GEO = new THREE.CylinderGeometry(0.022, 0.022, 0.55, 6);
const BOAT_HIT_GEO = new THREE.BoxGeometry(3.0, 2.6, 1.6);

/// uid→32bit。船のレーンと揺れの位相を決める(進捗とは無関係)。
function hashUid(uid: string): number {
  let h = 5381;
  for (let i = 0; i < uid.length; i++) h = ((h << 5) + h + uid.charCodeAt(i)) >>> 0;
  return h >>> 0;
}

interface Berth {
  member: HarborMember;
  x: number;
  z: number;
  rot: number;
  phase: number;
}

/// メンバー(最大4人)を固定レーンへ。ハッシュ順に並べ、前後は有機的にばらす。
function makeBerths(members: HarborMember[]): Berth[] {
  const fleet = members
    .slice(0, ROOM_MAX_MEMBERS)
    .map((member) => ({ member, hash: hashUid(member.id) }))
    .sort((a, b) => a.hash - b.hash || (a.member.id < b.member.id ? -1 : 1));
  const start = Math.floor((LANES_Z.length - fleet.length) / 2);
  return fleet.map(({ member, hash }, i) => {
    const lane = Math.min(start + i, LANES_Z.length - 1);
    return {
      member,
      x: LANES_X[lane] + ((((hash >> 3) % 100) / 100) * 0.7 - 0.35),
      z: LANES_Z[lane],
      rot: 0.04 + (((hash >> 9) % 100) / 100) * 0.12,
      phase: ((hash >> 5) % 628) / 100,
    };
  });
}

/// 一隻の船。位相の違う揺れ+名前ラベル+今日の灯+タップで軌跡へ。
function MemberBoat({
  berth,
  lit,
  animate,
  onSelect,
}: {
  berth: Berth;
  lit: boolean;
  animate: boolean;
  onSelect?: (member: HarborMember) => void;
}) {
  const { member, phase } = berth;
  const parts = useMemo(
    () =>
      boatPartsFromIds({
        boatSail: member.boatSail,
        boatJib: member.boatJib,
        boatHull: member.boatHull,
        boatStripe: member.boatStripe,
        boatFlag: member.boatFlag,
      }),
    [member],
  );
  const bob = useRef<THREE.Group>(null);
  const lanternMat = useRef<THREE.MeshStandardMaterial>(null);

  // BoatModel自体の揺れは全船同位相なので、外側でuidごとの位相を重ねる。
  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const g = bob.current;
    if (g) {
      g.position.y = Math.sin(time * 0.7 + phase) * 0.05;
      g.rotation.z = Math.sin(time * 0.55 + phase * 1.7) * 0.02;
    }
    if (lanternMat.current) {
      // ランタンのゆらぎ(emissiveのみ。lightは増やさない)。
      lanternMat.current.emissiveIntensity = 1.8 + Math.sin(time * 2.1 + phase) * 0.35;
    }
  });

  return (
    <group position={[berth.x, 0, berth.z]} rotation={[0, berth.rot, 0]} scale={0.45}>
      <Ripples animate={animate} />
      <group ref={bob}>
        <BoatModel parts={parts} animate={animate} />
        {/* 今日の灯: 船尾の短い掲灯柱+暖色のランタン(emissiveな小球のみ) */}
        {lit && (
          <group position={[-0.88, 0.42, 0]}>
            <mesh geometry={LANTERN_POLE_GEO} position={[0, 0.27, 0]}>
              <meshStandardMaterial color="#5A2A15" flatShading roughness={0.8} />
            </mesh>
            <mesh geometry={LANTERN_GEO} position={[0, 0.62, 0]}>
              <meshStandardMaterial
                ref={lanternMat}
                color="#F3C065"
                emissive="#F3C065"
                emissiveIntensity={1.8}
                fog={false}
              />
            </mesh>
          </group>
        )}
      </group>
      <Html
        position={[0.1, 2.7, 0]}
        center
        distanceFactor={7}
        zIndexRange={[1, 0]}
        style={{ pointerEvents: "none" }}
      >
        <div className="harbor-world-name">{member.displayName}</div>
      </Html>
      {/* 透明な当たり判定(船体+帆を覆う)。タップでこの人の軌跡へ。 */}
      <mesh
        geometry={BOAT_HIT_GEO}
        position={[0.1, 1.0, 0]}
        onClick={(e: ThreeEvent<MouseEvent>) => {
          e.stopPropagation();
          onSelect?.(member);
        }}
      >
        <meshBasicMaterial transparent opacity={0} depthWrite={false} />
      </mesh>
    </group>
  );
}

/// シーン本体。夜の海+右奥の島(港名)+並走する船団。
function HarborSea({
  roomName,
  berths,
  litIds,
  animate,
  onSelect,
}: {
  roomName: string;
  berths: Berth[];
  litIds: ReadonlySet<string>;
  animate: boolean;
  onSelect?: (member: HarborMember) => void;
}) {
  const camera = useThree((s) => s.camera);
  const invalidate = useThree((s) => s.invalidate);

  // 固定の斜め視点(VoyageSceneと同じ作法)。スクロール中の帯なので
  // OrbitControlsは使わない — タッチ回転が縦スクロールを塞ぐため。
  useLayoutEffect(() => {
    camera.lookAt(CAM_TARGET[0], CAM_TARGET[1], CAM_TARGET[2]);
    invalidate();
  }, [camera, invalidate]);

  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 12, 30]} />
      {/* 月光: VoyageSceneと同じトーン。影は使わない。 */}
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
      <Moon position={[-8, 2.8, -16]} />
      <Sea />
      <Horizon />
      {/* 右奥の島。上に港の名前が小さく浮かぶ。 */}
      <group position={ISLAND_SHIFT}>
        <Island />
      </group>
      <Html
        position={ISLAND_TOP}
        center
        distanceFactor={8}
        zIndexRange={[1, 0]}
        style={{ pointerEvents: "none" }}
      >
        <div className="harbor-world-island">{roomName}</div>
      </Html>
      {berths.map((berth) => (
        <MemberBoat
          key={berth.member.id}
          berth={berth}
          lit={litIds.has(berth.member.id)}
          animate={animate}
          onSelect={onSelect}
        />
      ))}
    </>
  );
}

/// みんなの海。260pxの横長Canvas+写真ボタン+灯の一行。
export default function HarborWorld({ room, members, onSelectMember }: HarborWorldProps) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const rootRef = useRef<HTMLDivElement>(null);
  const glRef = useRef<RootState | null>(null);
  const [flash, setFlash] = useState(false);
  const flashTimer = useRef<number | undefined>(undefined);

  // スクロールで画面外に出たらrAFループを止める(VoyageSceneと同じ作法)。
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
  useEffect(() => () => window.clearTimeout(flashTimer.current), []);

  const berths = useMemo(() => makeBerths(members), [members]);

  // 今日の灯: 各メンバーの当月ペイロードを読み、今日が含まれる船に灯をともす。
  const [litIds, setLitIds] = useState<ReadonlySet<string>>(new Set());
  useEffect(() => {
    if (isDemo) {
      setLitIds(demoLitMemberIds);
      return;
    }
    let alive = true;
    const now = new Date();
    const ym = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    const today = now.getDate();
    void Promise.all(
      members.slice(0, ROOM_MAX_MEMBERS).map(async (m) => {
        const month = await fetchMonth("rooms", room.id, m.id, ym);
        return month?.days.includes(today) ? m.id : null;
      }),
    ).then((ids) => {
      if (alive) setLitIds(new Set(ids.filter((id): id is string => id !== null)));
    });
    return () => {
      alive = false;
    };
  }, [room.id, members]);

  // 写真撮影。フラッシュ→WebGLの絵を2Dキャンバスへ合成(下部に港名・日付・
  // ワードマークをフラットに描く)→保存/共有シート。
  const takePhoto = () => {
    const state = glRef.current;
    if (!state) return;
    const src = state.gl.domElement;
    setFlash(false);
    // 次フレームで付け直すと連写でもアニメが再生される。
    requestAnimationFrame(() => setFlash(true));
    window.clearTimeout(flashTimer.current);
    flashTimer.current = window.setTimeout(() => setFlash(false), 340);

    const w = src.width;
    const h = src.height;
    const k = w / Math.max(src.clientWidth, 1); // 実効dpr
    const footer = Math.round(56 * k);
    const pad = Math.round(16 * k);
    const out = document.createElement("canvas");
    out.width = w;
    out.height = h + footer;
    const ctx = out.getContext("2d");
    if (!ctx) return;
    ctx.fillStyle = NIGHT_BG;
    ctx.fillRect(0, 0, out.width, out.height);
    // preserveDrawingBufferなしで確実に写すため、直前に同期レンダリングする。
    state.gl.render(state.scene, state.camera);
    ctx.drawImage(src, 0, 0);
    const font = "-apple-system, 'Hiragino Sans', 'Noto Sans JP', sans-serif";
    const midY = h + footer / 2;
    const dateLabel = new Intl.DateTimeFormat(lang, { dateStyle: "medium" }).format(
      new Date(),
    );
    ctx.textBaseline = "middle";
    ctx.textAlign = "left";
    ctx.fillStyle = "#EADEBD";
    ctx.font = `500 ${Math.round(14 * k)}px ${font}`;
    ctx.fillText(`${room.name} · ${dateLabel}`, pad, midY);
    ctx.textAlign = "right";
    ctx.fillStyle = "rgba(234,222,189,0.55)";
    ctx.font = `400 ${Math.round(11 * k)}px ${font}`;
    ctx.fillText(t("wordmark"), w - pad, midY);
    const stamp = new Date().toISOString().slice(0, 10);
    // クリック直後に呼ぶ。待つとtransient activationが切れ、iOS Safariで
    // navigator.share が無言で拒否される。
    void saveCanvas(out, `landfall-harbor-${stamp}.png`);
  };

  return (
    <>
      <div ref={rootRef} className="harbor-world">
        <Canvas
          dpr={[1, 2]}
          frameloop={animate && visible ? "always" : "demand"}
          camera={{ position: CAM_POS, fov: 36 }}
          onCreated={(state) => {
            glRef.current = state;
          }}
        >
          <HarborSea
            roomName={room.name}
            berths={berths}
            litIds={litIds}
            animate={animate}
            onSelect={onSelectMember}
          />
        </Canvas>
        <button
          className="harbor-world-camera"
          onClick={takePhoto}
          aria-label={t("takePhoto")}
          title={t("takePhoto")}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path
              d="M4 8.5C4 7.7 4.7 7 5.5 7H8l1.4-2h5.2L16 7h2.5c.8 0 1.5.7 1.5 1.5v9c0 .8-.7 1.5-1.5 1.5h-13C4.7 19 4 18.3 4 17.5v-9Z"
              fill="currentColor"
            />
            <circle cx="12" cy="13" r="3.2" fill="#123830" />
          </svg>
        </button>
        {flash && <div className="harbor-world-flash" />}
      </div>
      <p className="harbor-world-hint">{t("lanternHint")}</p>
    </>
  );
}
