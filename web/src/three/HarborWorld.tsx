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
  type HarborVoyage,
} from "../harbor";
import {
  activeEncounter,
  encounterPhase,
  type EncounterKind,
  type SeaRoute,
} from "../voyageMap";
import { saveCanvas } from "../share";
import { demoLitMemberIds, isDemo } from "../demo";
import { playStrike } from "../audio";
import { lang, t, voyageRemainingLabel } from "../i18n";

// 港の「みんなの海」。参加メンバー全員の船が同じ夜の海に浮かび、
// 同じ島(港の名前を持つ島)へ向かって並走している世界。
// VoyageScene/BoatStudioと同じ品質言語(低ポリ+flatShading、夜の海、星、月、波紋)。
//
// 反ストリークの約束: 船の位置は進捗・量・順位では決めない。
// uidのハッシュだけで決まる固定レーン+有機的な前後オフセット。誰も先頭ではない。

/// マウント後に届いた着岸/帰還を、船からの一撃として世界に流すイベント。
export interface StrikeEvent {
  uid: string;
  seq: number;
}

export interface HarborWorldProps {
  room: HarborRoom;
  members: HarborMember[];
  onSelectMember?: (member: HarborMember) => void;
  /// 共同航海。undefined=読込中(何も出さない)、null=航海なし。
  voyage?: HarborVoyage | null;
  /// 選択中の航路(generateRoutes(voyage.seed)[voyage.routeIndex])。導出は呼び出し側。
  route?: SeaRoute | null;
  /// 航海の進捗(全員の合算・分)。導出は呼び出し側(RoomDetail)。
  progressMinutes?: number;
  strike?: StrikeEvent | null;
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

// ---- 航路の海域(嵐/海獣) ----
// 進捗が海域の区間に入ると船団と島の間に現れる。海域内の潮目3段階で縮み・薄れ、
// 抜けると海へ帰る/晴れる。品質言語は世界と同じ(低ポリ+flatShading・フラット)。

const ENCOUNTER_POS: [number, number, number] = [2.45, 0, -1.35];
const BEAST_BODY_COLOR = "#342A5C"; // midnight系(夜の海に沈まない程度に持ち上げ)
const BEAST_DARK_COLOR = "#241A44"; // midnight寄りの陰
const EYE_ORANGE = "#F5822A"; // returnOrange

// 潮目3段階の見た目(0=満力、2=あと少し)。しきい値通過はdampで滑らかに。
const BEAST_PHASE_SCALE = [1.15, 0.92, 0.7];
const BEAST_PHASE_Y = [0, -0.26, -0.55];
// ハリケーンは「巨大」が身上。満力ではっきり大きく、弱まるほど痩せて低くなる。
const HUR_PHASE_SCALE = [1.24, 1.0, 0.78];

const BEAST_BODY_GEO = new THREE.SphereGeometry(0.6, 9, 7);
const BEAST_HEAD_GEO = new THREE.ConeGeometry(0.3, 0.5, 7);
const BEAST_EYE_GEO = new THREE.SphereGeometry(0.06, 8, 6);
const TENT_SEG1_GEO = new THREE.CylinderGeometry(0.08, 0.14, 0.75, 6);
const TENT_SEG2_GEO = new THREE.CylinderGeometry(0.035, 0.08, 0.6, 6);
const TENT_TIP_GEO = new THREE.ConeGeometry(0.035, 0.3, 6);
const CLOUD_GEO = new THREE.SphereGeometry(0.5, 8, 6);
const BOLT_GEO = new THREE.PlaneGeometry(1.0, 0.045);
// ハリケーンの漏斗(海面へ降りる細い首)・目(淡い円盤)・海面のしぶきの環。
const HUR_FUNNEL_GEO = new THREE.CylinderGeometry(0.58, 0.24, 0.9, 9, 1, true);
const HUR_EYE_GEO = new THREE.CircleGeometry(0.3, 10);
const HUR_SKIRT_GEO = new THREE.TorusGeometry(1.05, 0.13, 8, 28);

// 材質は色に依存しないので、ジオメトリと同じくモジュールで一度だけ作る
// (海域は同時に1体なので、目や雲のアニメも共有インスタンスで問題ない)。
const KRAKEN_BODY_MAT = new THREE.MeshStandardMaterial({
  color: BEAST_BODY_COLOR,
  flatShading: true,
  roughness: 0.85,
});
const KRAKEN_DARK_MAT = new THREE.MeshStandardMaterial({
  color: BEAST_DARK_COLOR,
  flatShading: true,
  roughness: 0.85,
});
const KRAKEN_EYE_MAT = new THREE.MeshStandardMaterial({
  color: EYE_ORANGE,
  emissive: new THREE.Color(EYE_ORANGE),
  emissiveIntensity: 1.5,
  fog: false,
});
// ハリケーン: 夜の海に沈まない程度に持ち上げた嵐雲の青3段。稲光は薄紫のemissive。
const HUR_TIER_MATS = ["#3A4C6B", "#2B3A55", "#1E2A3E"].map(
  (color) =>
    new THREE.MeshStandardMaterial({
      color,
      flatShading: true,
      roughness: 0.95,
      transparent: true,
      emissive: new THREE.Color("#CECBF6"),
      emissiveIntensity: 0,
    }),
);
const HUR_FUNNEL_MAT = new THREE.MeshStandardMaterial({
  color: "#131B29",
  flatShading: true,
  roughness: 0.9,
  transparent: true,
  side: THREE.DoubleSide,
});
const HUR_EYE_MAT = new THREE.MeshBasicMaterial({
  color: "#EADEBD",
  transparent: true,
  opacity: 0.75,
  fog: false,
});
const HUR_SKIRT_MAT = new THREE.MeshBasicMaterial({
  color: "#7FA8B8",
  transparent: true,
  opacity: 0.22,
  depthWrite: false,
});

/// ハリケーンの積層。横からのカメラでも「回る嵐」と読めるよう、渦は上空の
/// 円盤ではなく、下ほどすぼまる3段の雲リングの塔として組む(上段が明るく大きい)。
/// 各段はゴツゴツした雲塊のリングで、段ごとに違う速さで回って渦を見せる。
const HUR_TIERS: {
  y: number;
  r: number;
  n: number;
  size: number;
  /// その段の回転速度の倍率(内側=下段ほど速い)。
  speed: number;
}[] = [
  { y: 1.78, r: 1.18, n: 8, size: 1.0, speed: 0.55 },
  { y: 1.28, r: 0.84, n: 7, size: 0.78, speed: 0.8 },
  { y: 0.86, r: 0.55, n: 6, size: 0.58, speed: 1.15 },
];

/// 段内の雲塊の配置(決定的な揺らぎつき)。モジュールで一度だけ計算する。
const HUR_TIER_PUFFS: { p: [number, number, number]; s: [number, number, number] }[][] =
  HUR_TIERS.map((tier, ti) =>
    Array.from({ length: tier.n }, (_, i) => {
      const ang = (i / tier.n) * Math.PI * 2 + ti * 0.7;
      const wob = ((ti * 11 + i * 17) % 10) / 10; // 0..0.9 の決定的な揺らぎ
      const r = tier.r * (0.92 + wob * 0.16);
      const size = tier.size * (0.85 + ((i * 7 + ti * 3) % 10) / 33);
      return {
        p: [Math.cos(ang) * r, tier.y + (wob - 0.45) * 0.14, Math.sin(ang) * r] as [
          number,
          number,
          number,
        ],
        s: [size * 1.05, size * 0.55, size * 0.85] as [number, number, number],
      };
    }),
  );

// 触腕4本の配置角(XZ平面)。yawグループで局所+Xを放射方向へ向ける。
const TENTACLES = [0, 1, 2, 3].map((i) => (i / 4) * Math.PI * 2 + 0.6);

/// いま海に描くべき海域(嵐/海獣)。phase は潮目(0=満力→2=あと少し)、
/// defeating は「抜けた瞬間の沈む/晴れる」演出中。
interface EncounterView {
  kind: EncounterKind;
  phase: number;
  defeating: boolean;
}

/// 海獣。海面から出る胴体+頭+触腕4本。ゆっくり上下に蠢き、
/// 潮目で縮んで沈み、討伐で深みへ帰る。命中でscaleパルスの身じろぎ。
function Kraken({
  phase,
  defeating,
  animate,
  hitClock,
}: {
  phase: number;
  defeating: boolean;
  animate: boolean;
  hitClock: { current: number };
}) {
  const root = useRef<THREE.Group>(null);
  const tents = useRef<(THREE.Group | null)[]>([]);
  const baseY = useRef(BEAST_PHASE_Y[phase]);
  const baseScale = useRef(BEAST_PHASE_SCALE[phase]);
  const invalidate = useThree((s) => s.invalidate);

  // reduced-motion(demandフレーム)時: 潮目の段階へ直接置いて一度だけ描く。
  useLayoutEffect(() => {
    if (animate) return;
    baseY.current = BEAST_PHASE_Y[phase];
    baseScale.current = BEAST_PHASE_SCALE[phase];
    const g = root.current;
    if (g) {
      g.position.y = baseY.current;
      g.scale.setScalar(baseScale.current);
    }
    invalidate();
  }, [phase, animate, invalidate]);

  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const g = root.current;
    if (!g) return;
    const lambda = defeating ? 2.0 : 1.3;
    baseY.current = THREE.MathUtils.damp(
      baseY.current,
      defeating ? -2.6 : BEAST_PHASE_Y[phase],
      lambda,
      delta,
    );
    baseScale.current = THREE.MathUtils.damp(
      baseScale.current,
      defeating ? 0.5 : BEAST_PHASE_SCALE[phase],
      lambda,
      delta,
    );
    // 一撃の命中で身じろぎ(scaleパルス)。
    const since = time - hitClock.current;
    const pulse = since >= 0 && since < 0.5 ? Math.sin((since / 0.5) * Math.PI) * 0.09 : 0;
    g.position.y = baseY.current + (defeating ? 0 : Math.sin(time * 0.5) * 0.06);
    g.scale.setScalar(baseScale.current * (1 + pulse));
    KRAKEN_EYE_MAT.emissiveIntensity = 1.5 + Math.sin(time * 2.4) * 0.3;
    for (let i = 0; i < tents.current.length; i++) {
      const tg = tents.current[i];
      if (tg) tg.rotation.z = -0.45 + Math.sin(time * 0.55 + i * 1.7) * 0.1;
    }
  });

  return (
    <group position={ENCOUNTER_POS}>
      <group ref={root}>
        {/* 胴体(押し潰した球)+頭(円錐) */}
        <mesh
          geometry={BEAST_BODY_GEO}
          material={KRAKEN_BODY_MAT}
          position={[0, 0.28, 0]}
          scale={[1, 0.92, 0.86]}
        />
        <mesh
          geometry={BEAST_HEAD_GEO}
          material={KRAKEN_DARK_MAT}
          position={[0, 0.95, 0]}
          rotation={[0.1, 0, -0.08]}
        />
        {/* 目: returnOrangeの小球(カメラ側) */}
        {[-0.2, 0.2].map((x) => (
          <mesh
            key={x}
            geometry={BEAST_EYE_GEO}
            material={KRAKEN_EYE_MAT}
            position={[x, 0.42, 0.48]}
          />
        ))}
        {/* 触腕: 曲げたコーンの3節。外へ倒し、節ごとに曲げて反りを作る */}
        {TENTACLES.map((a, i) => (
          <group key={a} rotation={[0, -a, 0]}>
            <group
              ref={(g) => {
                tents.current[i] = g;
              }}
              position={[0.58, -0.05, 0]}
              rotation={[0, 0, -0.45]}
            >
              <mesh geometry={TENT_SEG1_GEO} material={KRAKEN_BODY_MAT} position={[0, 0.34, 0]} />
              <group position={[0, 0.66, 0]} rotation={[0, 0, -0.5]}>
                <mesh
                  geometry={TENT_SEG2_GEO}
                  material={KRAKEN_DARK_MAT}
                  position={[0, 0.26, 0]}
                />
                <group position={[0, 0.52, 0]} rotation={[0, 0, -0.55]}>
                  <mesh
                    geometry={TENT_TIP_GEO}
                    material={KRAKEN_DARK_MAT}
                    position={[0, 0.12, 0]}
                  />
                </group>
              </group>
            </group>
          </group>
        ))}
      </group>
    </group>
  );
}

/// 嵐の航海 — 巨大なハリケーン。下ほどすぼまる3段の雲リングが段ごとに違う
/// 速さで回り、細い漏斗が海面へ降りて、しぶきの環を巻き上げる。右手前の
/// 水平線から滑り込んで来て(接近)、潮目で痩せ、抜けると空へほどけながら
/// 過ぎ去っていく。命中で稲光。
function Hurricane({
  phase,
  defeating,
  animate,
  hitClock,
}: {
  phase: number;
  defeating: boolean;
  animate: boolean;
  hitClock: { current: number };
}) {
  const root = useRef<THREE.Group>(null);
  const tiers = useRef<(THREE.Group | null)[]>([]);
  const skirt = useRef<THREE.Mesh>(null);
  const appear = useRef(0); // 0=水平線の彼方 → 1=定位置(接近の滑り込み)
  const baseScale = useRef(HUR_PHASE_SCALE[phase]);
  const fade = useRef(1);
  const drift = useRef(0); // 過ぎ去り(defeat)の横滑り
  const invalidate = useThree((s) => s.invalidate);

  const applyFade = (v: number) => {
    for (const m of HUR_TIER_MATS) m.opacity = v;
    HUR_FUNNEL_MAT.opacity = v;
    HUR_EYE_MAT.opacity = 0.75 * v;
    HUR_SKIRT_MAT.opacity = 0.22 * v;
  };

  // reduced-motion(demandフレーム)時: 接近は省略して定位置に置き、一度だけ描く。
  useLayoutEffect(() => {
    if (animate) return;
    appear.current = 1;
    baseScale.current = HUR_PHASE_SCALE[phase];
    fade.current = defeating ? 0 : 1;
    const g = root.current;
    if (g) {
      g.position.set(ENCOUNTER_POS[0], 0, ENCOUNTER_POS[2]);
      g.scale.setScalar(baseScale.current);
    }
    applyFade(fade.current);
    for (const m of HUR_TIER_MATS) m.emissiveIntensity = 0;
    invalidate();
  }, [phase, animate, defeating, invalidate]);

  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const g = root.current;
    if (!g) return;
    appear.current = THREE.MathUtils.damp(appear.current, 1, 1.1, delta);
    baseScale.current = THREE.MathUtils.damp(
      baseScale.current,
      defeating ? 0.35 : HUR_PHASE_SCALE[phase],
      defeating ? 1.6 : 1.2,
      delta,
    );
    fade.current = THREE.MathUtils.damp(fade.current, defeating ? 0 : 1, 1.8, delta);
    drift.current = THREE.MathUtils.damp(drift.current, defeating ? 2.4 : 0, 1.1, delta);
    // 接近: 右手前の水平線から定位置へ(島の背後は通らない)。
    // 過ぎ去り: ほどけながら空へ昇り、右へ流れていく。
    const t = appear.current;
    g.position.set(
      ENCOUNTER_POS[0] + (1 - t) * 3.0 + drift.current,
      (1 - t) * 0.3 + (1 - fade.current) * 1.5,
      ENCOUNTER_POS[2] + (1 - t) * 0.6,
    );
    // 命中で身震い(scaleパルス)。塔全体がわずかに傾いで揺れる。
    const since = time - hitClock.current;
    const pulse = since >= 0 && since < 0.5 ? Math.sin((since / 0.5) * Math.PI) * 0.07 : 0;
    g.scale.setScalar(baseScale.current * (0.55 + 0.45 * t) * (1 + pulse));
    g.rotation.z = 0.05 + Math.sin(time * 0.4) * 0.02;
    // 段ごとに違う速さで回る(下段=内側ほど速い)。弱まるほど回転もゆるむ。
    const spin = (0.6 - phase * 0.1) * (0.4 + 0.6 * fade.current);
    for (let i = 0; i < HUR_TIERS.length; i++) {
      const tg = tiers.current[i];
      if (tg) tg.rotation.y = -time * spin * HUR_TIERS[i].speed;
    }
    if (skirt.current) skirt.current.rotation.z = time * spin * 0.6;
    // 稲光: 決定的な疑似ランダムのまたたき+命中の強い閃き。
    const flick = Math.sin(time * 1.7) * Math.sin(time * 2.9 + 1.3) * Math.sin(time * 0.83 + 4.1);
    const strikeFlash = since >= 0 && since < 0.4 ? 1 - since / 0.4 : 0;
    const glow = (flick > 0.82 ? (flick - 0.82) * 3.2 : 0) + strikeFlash * 0.9;
    HUR_TIER_MATS.forEach((m, i) => {
      m.emissiveIntensity = glow * (1 - i * 0.25);
    });
    applyFade(fade.current);
  });

  return (
    <group ref={root} position={ENCOUNTER_POS}>
      {/* 3段の雲リング。段ごとに別グループで回す */}
      {HUR_TIER_PUFFS.map((puffs, ti) => (
        <group
          key={ti}
          ref={(el) => {
            tiers.current[ti] = el;
          }}
        >
          {puffs.map((puff, i) => (
            <mesh
              key={i}
              geometry={CLOUD_GEO}
              material={HUR_TIER_MATS[ti]}
              position={puff.p}
              scale={puff.s}
            />
          ))}
        </group>
      ))}
      {/* 漏斗: 塔の芯が海面へ降りる細い首 */}
      <mesh geometry={HUR_FUNNEL_GEO} material={HUR_FUNNEL_MAT} position={[0, 0.5, 0]} />
      {/* 目: 塔の頂の淡い円盤。カメラへ少し傾け、静けさを覗かせる */}
      <mesh
        geometry={HUR_EYE_GEO}
        material={HUR_EYE_MAT}
        position={[0, 2.0, 0.05]}
        rotation={[-Math.PI / 2 + 0.32, 0, 0]}
      />
      {/* 海面のしぶきの環。漏斗の足元で巻き上がる */}
      <mesh
        ref={skirt}
        geometry={HUR_SKIRT_GEO}
        material={HUR_SKIRT_MAT}
        position={[0, 0.08, 0]}
        rotation={[-Math.PI / 2, 0, 0]}
      />
    </group>
  );
}

interface Bolt {
  id: number;
  from: [number, number, number];
}

/// 一撃の光。船から海獣/嵐へ、emissiveな薄いプレーンが一閃して飛ぶ。
/// 到達時に hitClock を更新し(身じろぎ/明滅の起点)、自身を消す。
function StrikeBolt({
  from,
  hitClock,
  onDone,
}: {
  from: [number, number, number];
  hitClock: { current: number };
  onDone: () => void;
}) {
  const mesh = useRef<THREE.Mesh>(null);
  const mat = useRef<THREE.MeshBasicMaterial>(null);
  const start = useRef<number | null>(null);
  const finished = useRef(false);
  const path = useMemo(() => {
    const origin = new THREE.Vector3(from[0], 0.55, from[2]);
    const target = new THREE.Vector3(ENCOUNTER_POS[0], 0.75, ENCOUNTER_POS[2]);
    const dir = target.clone().sub(origin).normalize();
    const quat = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(1, 0, 0), dir);
    return { origin, target, quat };
  }, [from]);

  useFrame(({ clock }) => {
    if (finished.current) return;
    const time = clock.elapsedTime;
    if (start.current === null) start.current = time;
    const s = (time - start.current) / 0.4;
    if (s >= 1) {
      finished.current = true;
      hitClock.current = time; // 命中 → 海獣の身じろぎ/嵐の明滅
      onDone();
      return;
    }
    const m = mesh.current;
    if (m) {
      m.position.lerpVectors(path.origin, path.target, s);
      m.position.y += Math.sin(Math.PI * s) * 0.35;
      m.quaternion.copy(path.quat);
    }
    if (mat.current) mat.current.opacity = Math.sin(Math.PI * Math.min(s * 1.25, 1)) * 0.95;
  });

  return (
    <mesh ref={mesh} geometry={BOLT_GEO} position={[from[0], 0.55, from[2]]}>
      <meshBasicMaterial
        ref={mat}
        color="#F3C065"
        transparent
        opacity={0}
        blending={THREE.AdditiveBlending}
        depthWrite={false}
        side={THREE.DoubleSide}
        fog={false}
      />
    </mesh>
  );
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

/// シーン本体。夜の海+右奥の島(港名)+並走する船団+航路の海域(海獣/嵐)。
function HarborSea({
  roomName,
  berths,
  litIds,
  animate,
  onSelect,
  encounter,
  advanceOn,
  arriveFx,
  hitClock,
  bolts,
  onBoltDone,
}: {
  roomName: string;
  berths: Berth[];
  litIds: ReadonlySet<string>;
  animate: boolean;
  onSelect?: (member: HarborMember) => void;
  encounter: EncounterView | null;
  /// 到着済み(船団を島へ寄せる)。マウント時に真なら最初から寄せた位置で描く。
  advanceOn: boolean;
  /// 到着の演出中(光がふわっと明るくなる)。
  arriveFx: boolean;
  hitClock: { current: number };
  bolts: Bolt[];
  onBoltDone: (id: number) => void;
}) {
  const camera = useThree((s) => s.camera);
  const invalidate = useThree((s) => s.invalidate);
  const fleet = useRef<THREE.Group>(null);
  const keyLight = useRef<THREE.DirectionalLight>(null);
  const fillLight = useRef<THREE.DirectionalLight>(null);
  const ambient = useRef<THREE.AmbientLight>(null);
  const advance = useRef(advanceOn ? 1 : 0);
  const dim = useRef(1);
  const arriveClock = useRef<number | null>(null);

  // 海域の中では海がわずかに暗く、潮目が進むごとに明るさが戻る。
  const dimTarget =
    encounter && !encounter.defeating ? 0.62 + encounter.phase * 0.13 : 1;
  const advanceTarget = advanceOn ? 1 : 0;

  const applyVoyageLook = () => {
    if (keyLight.current) keyLight.current.intensity = 1.15 * dim.current;
    if (fillLight.current) fillLight.current.intensity = 0.2 * dim.current;
    if (ambient.current) ambient.current.intensity = 0.45 * (0.6 + 0.4 * dim.current);
    // 到着後、船団は島へ向けて滑走する(島の方向へ平行移動)。
    fleet.current?.position.set(advance.current * 1.5, 0, advance.current * -0.7);
  };

  // 固定の斜め視点(VoyageSceneと同じ作法)。スクロール中の帯なので
  // OrbitControlsは使わない — タッチ回転が縦スクロールを塞ぐため。
  useLayoutEffect(() => {
    camera.lookAt(CAM_TARGET[0], CAM_TARGET[1], CAM_TARGET[2]);
    invalidate();
  }, [camera, invalidate]);

  // reduced-motion時はジャンプカット: 目標値へ直接置いて一度だけ描く。
  useLayoutEffect(() => {
    if (animate) return;
    dim.current = dimTarget;
    advance.current = advanceTarget;
    applyVoyageLook();
    invalidate();
  });

  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    // 到着の瞬間を覚えて、光をふわっと明るくする。
    if (arriveFx && arriveClock.current === null) arriveClock.current = time;
    if (!arriveFx) arriveClock.current = null;
    let target = dimTarget;
    if (arriveClock.current !== null) {
      const dt = time - arriveClock.current;
      if (dt > 1.2 && dt < 3.4) target = 1.22;
    }
    dim.current = THREE.MathUtils.damp(dim.current, target, 1.6, delta);
    advance.current = THREE.MathUtils.damp(advance.current, advanceTarget, 0.9, delta);
    applyVoyageLook();
  });

  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 12, 30]} />
      {/* 月光: VoyageSceneと同じトーン。影は使わない。 */}
      <ambientLight ref={ambient} color="#ffe9c8" intensity={0.45} />
      <directionalLight ref={keyLight} color="#EADEBD" intensity={1.15} position={[-6, 8, -5]} />
      <directionalLight ref={fillLight} color="#5DCAA5" intensity={0.2} position={[5, 3, 6]} />
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
      {/* 海域: 船団と島の間のハリケーン/海獣。抜けるアニメの間は残して見送る/沈める。 */}
      {encounter &&
        (encounter.kind === "storm" ? (
          <Hurricane
            phase={encounter.phase}
            defeating={encounter.defeating}
            animate={animate}
            hitClock={hitClock}
          />
        ) : (
          <Kraken
            phase={encounter.phase}
            defeating={encounter.defeating}
            animate={animate}
            hitClock={hitClock}
          />
        ))}
      {bolts.map((bolt) => (
        <StrikeBolt
          key={bolt.id}
          from={bolt.from}
          hitClock={hitClock}
          onDone={() => onBoltDone(bolt.id)}
        />
      ))}
      {/* 船団。到着後はグループごと島へ滑走する。 */}
      <group ref={fleet}>
        {berths.map((berth) => (
          <MemberBoat
            key={berth.member.id}
            berth={berth}
            lit={litIds.has(berth.member.id)}
            animate={animate}
            onSelect={onSelect}
          />
        ))}
      </group>
    </>
  );
}

/// みんなの海。260pxの横長Canvas+写真ボタン+灯の一行+共同航海の海域。
export default function HarborWorld({
  room,
  members,
  onSelectMember,
  voyage,
  route,
  progressMinutes = 0,
  strike,
}: HarborWorldProps) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const rootRef = useRef<HTMLDivElement>(null);
  const glRef = useRef<RootState | null>(null);
  const [flash, setFlash] = useState(false);
  const flashTimer = useRef<number | undefined>(undefined);

  // ---- 共同航海: 進捗・海域・到着・一撃 ----
  const target = voyage?.targetMinutes ?? 0;
  const frac = voyage && target > 0 ? Math.min(progressMinutes / target, 1) : 0;
  const arrived = Boolean(voyage?.arrivedAt);
  const voyageActive = Boolean(voyage) && !arrived;
  const identity = voyage ? voyage.createdAt.getTime() : null;
  const activeRoute = voyage && route ? route : null;
  const passedCount = activeRoute
    ? activeRoute.encounters.filter((e) => frac >= e.end).length
    : 0;

  // 海域を抜けた瞬間の演出(沈む/晴れる→帯)と、到着の演出。
  const [clearFx, setClearFx] = useState<{
    kind: EncounterKind;
    stage: "running" | "banner";
  } | null>(null);
  const [arriveStage, setArriveStage] = useState<"none" | "fx" | "quiet">("none");
  const identityRef = useRef<number | null | undefined>(undefined);
  const prevPassed = useRef<number | null>(null);
  const prevArrived = useRef<boolean | null>(null);
  const clearFxTimers = useRef<number[]>([]);
  const arriveTimers = useRef<number[]>([]);

  // 航海が入れ替わったら(次の航海など)演出を全部リセットする。
  // 旧航海のタイマーが残ると、新しい航海の最中に帯や滑走が誤発火する。
  // ※ このeffectは他の演出effectより先に宣言する(実行順が宣言順のため)。
  useEffect(() => {
    if (identityRef.current === identity) return;
    identityRef.current = identity;
    clearFxTimers.current.forEach((id) => window.clearTimeout(id));
    clearFxTimers.current.length = 0;
    arriveTimers.current.forEach((id) => window.clearTimeout(id));
    arriveTimers.current.length = 0;
    setClearFx(null);
    setArriveStage("none");
    prevPassed.current = null;
    prevArrived.current = null;
  }, [identity]);

  // 海域の通過。マウント中に区間の終端を越えた瞬間だけ流す
  // (開いた時に既に過ぎていた海域は静かに素通り)。
  useEffect(() => {
    if (!activeRoute) return;
    if (prevPassed.current === null) {
      prevPassed.current = passedCount;
      return;
    }
    if (passedCount <= prevPassed.current) {
      prevPassed.current = passedCount;
      return;
    }
    const cleared = activeRoute.encounters[passedCount - 1];
    prevPassed.current = passedCount;
    clearFxTimers.current.forEach((id) => window.clearTimeout(id));
    clearFxTimers.current.length = 0;
    if (arrived) return; // 到着と同時なら到着の演出に譲る
    if (!animate) {
      // reduced-motion: 沈む/晴れるはジャンプカットし、帯だけ見せる。
      setClearFx({ kind: cleared.kind, stage: "banner" });
      clearFxTimers.current.push(window.setTimeout(() => setClearFx(null), 4200));
      return;
    }
    setClearFx({ kind: cleared.kind, stage: "running" }); // 沈む/晴れる(約2.2秒)
    clearFxTimers.current.push(
      window.setTimeout(() => setClearFx({ kind: cleared.kind, stage: "banner" }), 2200),
      window.setTimeout(() => setClearFx(null), 6600),
    );
  }, [passedCount, activeRoute, arrived, animate]);

  // 到着。マウント中に arrivedAt が付いた瞬間だけ演出を流す
  // (最初から到着済みの港では静かに"quiet")。
  useEffect(() => {
    if (voyage === undefined || voyage === null) return;
    if (prevArrived.current === null) {
      prevArrived.current = arrived;
      if (arrived) setArriveStage("quiet");
      return;
    }
    if (arrived === prevArrived.current) return;
    prevArrived.current = arrived;
    if (!arrived) {
      setArriveStage("none");
      return;
    }
    // 海域の帯は打ち切り、到着を優先する。
    clearFxTimers.current.forEach((id) => window.clearTimeout(id));
    clearFxTimers.current.length = 0;
    setClearFx(null);
    setArriveStage("fx");
    arriveTimers.current.push(window.setTimeout(() => setArriveStage("quiet"), 8000));
  }, [voyage, arrived]);

  useEffect(() => {
    const a = clearFxTimers.current;
    const b = arriveTimers.current;
    return () => {
      a.forEach((id) => window.clearTimeout(id));
      b.forEach((id) => window.clearTimeout(id));
    };
  }, []);

  // いま描く海域。進捗が区間を越えた直後は、state(clearFx)が立つ前の
  // 1フレームでも海域を消さない(消えて→また現れるちらつきを防ぐ)。
  const enc = activeRoute && voyageActive ? activeEncounter(activeRoute, frac) : null;
  const pendingClear =
    identityRef.current === identity &&
    prevPassed.current !== null &&
    passedCount > prevPassed.current &&
    !arrived;
  const clearingKind: EncounterKind | null =
    clearFx?.stage === "running"
      ? clearFx.kind
      : pendingClear && activeRoute
        ? activeRoute.encounters[passedCount - 1].kind
        : null;
  const encounterView: EncounterView | null = enc
    ? { kind: enc.kind, phase: encounterPhase(enc, frac), defeating: false }
    : clearingKind
      ? { kind: clearingKind, phase: 2, defeating: true }
      : null;

  // 一撃: 新しい着岸/帰還(strike)ごとに、その船から一閃を飛ばす。
  const [bolts, setBolts] = useState<Bolt[]>([]);
  const hitClock = useRef(-10);
  const lastStrikeSeq = useRef(0);

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

  // 嵐の航海 — ハリケーンの海域に入った瞬間、イベントの題字を一度だけ掲げる
  // (同じ航海では再表示しない)。表示のトリガーと消灯タイマーは別のeffectに
  // 分ける — 一緒にすると、StrictMode等でeffectが再実行された際に「表示済み」の
  // 早期returnがタイマーだけを取り消し、題字が出っぱなしになる。
  const [stormIntro, setStormIntro] = useState(false);
  const stormIntroShown = useRef<number | null>(null);
  const stormActive = encounterView?.kind === "storm" && !encounterView.defeating;
  useEffect(() => {
    if (!stormActive || identity === null) return;
    if (stormIntroShown.current === identity) return;
    stormIntroShown.current = identity;
    setStormIntro(true);
  }, [stormActive, identity]);
  useEffect(() => {
    if (!stormIntro) return;
    const id = window.setTimeout(() => setStormIntro(false), 4600);
    return () => window.clearTimeout(id);
  }, [stormIntro]);

  // 一撃の発火。航海中だけ音を添え、海域が出ている間だけ一閃を飛ばす
  // (何もない海に光が飛ぶと行き先が謎になる)。
  useEffect(() => {
    if (!strike || strike.seq === lastStrikeSeq.current) return;
    lastStrikeSeq.current = strike.seq;
    if (!voyageActive) return;
    playStrike();
    if (!animate) return; // reduced-motion: 一閃は省略(ジャンプカット)
    if (!encounterView || encounterView.defeating) return;
    const berth = berths.find((b) => b.member.id === strike.uid);
    if (!berth) return;
    setBolts((list) => [...list.slice(-3), { id: strike.seq, from: [berth.x, 0, berth.z] }]);
  }, [strike, voyageActive, animate, berths, encounterView]);

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
            encounter={encounterView}
            advanceOn={arrived}
            arriveFx={arriveStage === "fx"}
            hitClock={hitClock}
            bolts={bolts}
            onBoltDone={(id) => setBolts((list) => list.filter((b) => b.id !== id))}
          />
        </Canvas>
        {/* 航海の進捗(連続バー+海域の印+残り)。個人の内訳や順位は出さない。 */}
        {voyageActive && voyage && activeRoute && (
          <div className="trial-bar">
            <div
              className="voyage-track"
              role="progressbar"
              aria-valuemin={0}
              aria-valuemax={voyage.targetMinutes}
              aria-valuenow={Math.min(progressMinutes, voyage.targetMinutes)}
            >
              <span
                className="voyage-fill"
                style={{ width: `${Math.round(frac * 100)}%` }}
              />
              {activeRoute.encounters.map((e, i) => (
                <span
                  key={i}
                  className={`voyage-mark ${e.kind}${frac >= e.end ? " passed" : ""}`}
                  style={{ left: `${Math.round(((e.start + e.end) / 2) * 100)}%` }}
                  title={t(e.kind === "storm" ? "encounterStorm" : "encounterKraken")}
                />
              ))}
            </div>
            <span className="trial-remaining">
              {voyageRemainingLabel(voyage.targetMinutes - progressMinutes)}
            </span>
          </div>
        )}
        {/* 嵐の航海の題字。ハリケーンの海域に入った瞬間、一度だけ掲げる。 */}
        {stormIntro && !clearFx && arriveStage !== "fx" && (
          <div className="trial-defeat" role="status">
            <div className="trial-defeat-title">{t("stormEventTitle")}</div>
            <div className="trial-defeat-sub">{t("stormEventSub")}</div>
          </div>
        )}
        {/* 海域を抜けた帯。世界の上にふわっと現れる一枚。 */}
        {clearFx?.stage === "banner" && (
          <div className="trial-defeat" role="status">
            <div className="trial-defeat-title">
              {t(clearFx.kind === "storm" ? "stormCleared" : "krakenCleared")}
            </div>
          </div>
        )}
        {/* 到着の帯+戦利品の告知(その航路に戦利品があるときだけ)。 */}
        {arriveStage === "fx" && (
          <div className="trial-defeat" role="status">
            <div className="trial-defeat-title">{t("voyageArrivedTitle")}</div>
            {activeRoute?.lootKey && (
              <div className="trial-defeat-sub">
                {t(
                  activeRoute.lootKey === "loot.moonlightSail"
                    ? "lootMoonlightNotice"
                    : "lootKrakenNotice",
                )}
              </div>
            )}
          </div>
        )}
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
