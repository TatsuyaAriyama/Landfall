import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import * as THREE from "three";
import { Canvas, useFrame, useThree, type ThreeEvent } from "@react-three/fiber";
import { Html, OrbitControls, Stars } from "@react-three/drei";
import BoatModel from "./BoatModel";
import { NIGHT_BG, Ripples, Sea } from "./SeaParts";
import { Horizon, Island, Wake, X_END, X_START } from "./VoyageScene";
import { boatProps } from "../boat";
import { playPlink } from "../audio";
import type { UserData } from "../data";
import {
  deleteDestination,
  destinationProgress,
  saveDestination,
  type Destination,
} from "../destinations";
import { askConfirm, showToast } from "../overlays";
import { t } from "../i18n";

// 目的地の没入エディタ。3D航海カードをタップすると、この「世界」へズームインして
// 入り、夜の海の中で島の名前・対象項目・目標を設定・変更できる。
// 保存/削除/検証はDestinationDialogと同等。世界観はVoyageScene/BoatStudioと同じ。

export interface VoyageWorldProps {
  dest: Destination | null; // null = 新規作成(世界の中でそのまま設定する)
  data: UserData;
  uid: string;
  onClose: () => void;
}

type Phase = "enter" | "idle" | "exit";

// カードと同じ遠景から、船と島を望む近景へドリーインする。
const FAR_POS = new THREE.Vector3(0.4, 2.5, 8.2);
const FAR_TARGET = new THREE.Vector3(0, 0.35, 0);
const DOLLY_SECONDS = 1.2;
const ISLAND_POS: [number, number, number] = [3.5, 0, -0.9];

// ジオメトリは色に依存しないので、モジュール読み込み時に一度だけ作る。
const MOON_GEO = new THREE.SphereGeometry(1.1, 20, 14);
const BOAT_HIT_GEO = new THREE.BoxGeometry(3.0, 2.6, 1.6);
const TAP_RING_GEO = new THREE.RingGeometry(0.9, 1.0, 48);
const SHOOTING_GEO = new THREE.PlaneGeometry(1.8, 0.035);

function easeInOutCubic(v: number): number {
  return v < 0.5 ? 4 * v * v * v : 1 - Math.pow(-2 * v + 2, 3) / 2;
}

/// 入場・退場のカメラ演出。idle中はOrbitControlsに任せる(pan無効なので
/// 注視点はnear.targetのまま動かない=退場はそこから遠景へ戻せばよい)。
function CameraRig({
  phase,
  animate,
  near,
  onEntered,
  onExited,
}: {
  phase: Phase;
  animate: boolean;
  near: { pos: THREE.Vector3; target: THREE.Vector3 };
  onEntered: () => void;
  onExited: () => void;
}) {
  const camera = useThree((s) => s.camera);
  const invalidate = useThree((s) => s.invalidate);
  const startAt = useRef<number | null>(null);
  const fromPos = useRef(new THREE.Vector3());
  const look = useRef(new THREE.Vector3());
  const done = useRef(false);

  // 初期配置。reduced-motionなら最初から近景(ジャンプカット)。
  const initialised = useRef(false);
  useLayoutEffect(() => {
    if (initialised.current) return;
    initialised.current = true;
    if (animate) {
      camera.position.copy(FAR_POS);
      camera.lookAt(FAR_TARGET);
    } else {
      camera.position.copy(near.pos);
      camera.lookAt(near.target);
    }
    invalidate();
  }, [animate, camera, near, invalidate]);

  // フェーズが変わったらタイムラインを巻き直す。
  useEffect(() => {
    startAt.current = null;
    done.current = false;
  }, [phase]);

  useFrame(({ clock }) => {
    if (!animate || phase === "idle" || done.current) return;
    const now = clock.elapsedTime;
    if (startAt.current === null) {
      startAt.current = now;
      // 退場は「いまの視点」から遠景へ逆再生する(回して眺めた後でも滑らか)。
      fromPos.current.copy(phase === "enter" ? FAR_POS : camera.position);
    }
    const raw = Math.min((now - startAt.current) / DOLLY_SECONDS, 1);
    const k = easeInOutCubic(raw);
    const toPos = phase === "enter" ? near.pos : FAR_POS;
    const fromT = phase === "enter" ? FAR_TARGET : near.target;
    const toT = phase === "enter" ? near.target : FAR_TARGET;
    camera.position.lerpVectors(fromPos.current, toPos, k);
    look.current.lerpVectors(fromT, toT, k);
    camera.lookAt(look.current);
    if (raw >= 1) {
      done.current = true;
      if (phase === "enter") onEntered();
      else onExited();
    }
  });
  return null;
}

/// 月。タップするとふわっと一瞬明るくなる(emissiveをease)。
function TappableMoon({ animate }: { animate: boolean }) {
  const mat = useRef<THREE.MeshStandardMaterial>(null);
  const glowAt = useRef(-Infinity);
  const clock = useThree((s) => s.clock);

  useFrame(({ clock: c }) => {
    if (!animate || !mat.current) return;
    const p = (c.elapsedTime - glowAt.current) / 1.3;
    mat.current.emissiveIntensity =
      p >= 0 && p < 1 ? 0.95 + Math.sin(Math.PI * p) * 0.8 : 0.95;
  });

  return (
    <mesh
      geometry={MOON_GEO}
      position={[-8, 3.2, -16]}
      onClick={(e: ThreeEvent<MouseEvent>) => {
        e.stopPropagation();
        if (animate) glowAt.current = clock.elapsedTime;
      }}
    >
      <meshStandardMaterial
        ref={mat}
        color={NIGHT_BG}
        emissive="#EADEBD"
        emissiveIntensity={0.95}
        fog={false}
      />
    </mesh>
  );
}

/// 流れ星。8〜20秒間隔で、細長い淡いメッシュが約1.5秒かけて夜空を横切る。
function ShootingStar({ animate }: { animate: boolean }) {
  const mesh = useRef<THREE.Mesh>(null);
  const mat = useRef<THREE.MeshBasicMaterial>(null);
  const nextAt = useRef(5 + Math.random() * 9); // 初回は少し早めに
  const startAt = useRef<number | null>(null);
  const from = useRef(new THREE.Vector3());
  const vel = useRef(new THREE.Vector3());

  useFrame(({ clock }) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    if (startAt.current === null) {
      if (time < nextAt.current) return;
      startAt.current = time;
      const sign = Math.random() < 0.5 ? 1 : -1;
      from.current.set(
        -sign * (3 + Math.random() * 6),
        6 + Math.random() * 3.5,
        -21 - Math.random() * 4,
      );
      vel.current.set(sign * (8 + Math.random() * 4), -(2 + Math.random() * 2), 0);
      return;
    }
    const p = (time - startAt.current) / 1.5;
    const m = mesh.current;
    const mm = mat.current;
    if (p >= 1) {
      startAt.current = null;
      nextAt.current = time + 8 + Math.random() * 12;
      if (m) m.visible = false;
      return;
    }
    if (m && mm) {
      m.visible = true;
      m.position.copy(from.current).addScaledVector(vel.current, p);
      m.rotation.z = Math.atan2(vel.current.y, vel.current.x);
      mm.opacity = Math.sin(Math.PI * p) * 0.5;
    }
  });

  return (
    <mesh ref={mesh} geometry={SHOOTING_GEO} visible={false}>
      <meshBasicMaterial
        ref={mat}
        color="#EADEBD"
        transparent
        opacity={0}
        fog={false}
        depthWrite={false}
        side={THREE.DoubleSide}
      />
    </mesh>
  );
}

/// 進捗位置の船。タップで小さくホップ+波紋が一周広がり、短い音が鳴る。
/// 連打はタイムラインを巻き直すだけなので壊れない。
function PlayfulBoat({ boatX, animate }: { boatX: number; animate: boolean }) {
  const parts = useMemo(() => boatProps(), []);
  const hop = useRef<THREE.Group>(null);
  const ringMesh = useRef<THREE.Mesh>(null);
  const ringMat = useRef<THREE.MeshBasicMaterial>(null);
  const tapAt = useRef(-Infinity);
  const lastSound = useRef(0);
  const clock = useThree((s) => s.clock);

  const onTap = (e: ThreeEvent<MouseEvent>) => {
    e.stopPropagation();
    const now = performance.now();
    if (now - lastSound.current > 180) {
      lastSound.current = now;
      playPlink();
    }
    if (animate) tapAt.current = clock.elapsedTime;
  };

  useFrame(({ clock: c }) => {
    if (!animate) return;
    const p = (c.elapsedTime - tapAt.current) / 1.1;
    const g = hop.current;
    const rm = ringMesh.current;
    const rmat = ringMat.current;
    if (p >= 0 && p < 1) {
      const hopP = Math.min(p / 0.32, 1); // 前半でホップ、波紋は最後まで広がる
      if (g) g.position.y = Math.sin(Math.PI * hopP) * 0.22;
      if (rm && rmat) {
        rm.visible = true;
        const s = 1 + p * 3.6;
        rm.scale.set(s, s, 1);
        rmat.opacity = (1 - p) * 0.42;
      }
    } else {
      if (g) g.position.y = 0;
      if (rm) rm.visible = false;
    }
  });

  return (
    <group position={[boatX, 0, 0]} rotation={[0, 0.1, 0]} scale={0.55}>
      <Ripples animate={animate} />
      <Wake animate={animate} />
      <mesh
        ref={ringMesh}
        geometry={TAP_RING_GEO}
        rotation={[-Math.PI / 2, 0, 0]}
        position={[0, 0.03, 0]}
        visible={false}
      >
        <meshBasicMaterial
          ref={ringMat}
          color="#7FB8A6"
          transparent
          opacity={0}
          depthWrite={false}
        />
      </mesh>
      <group ref={hop}>
        <BoatModel parts={parts} animate={animate} />
      </group>
      {/* 透明な当たり判定(船体+帆を覆う) */}
      <mesh geometry={BOAT_HIT_GEO} position={[0.1, 1.0, 0]} onClick={onTap}>
        <meshBasicMaterial transparent opacity={0} depthWrite={false} />
      </mesh>
    </group>
  );
}

/// 世界そのもの。VoyageScene/BoatStudioと同じ夜の海+星・月・霧・島・船。
function WorldScene({
  phase,
  animate,
  boatX,
  islandLabel,
  onEntered,
  onExited,
}: {
  phase: Phase;
  animate: boolean;
  boatX: number;
  islandLabel: string;
  onEntered: () => void;
  onExited: () => void;
}) {
  // 近景の構図は画面の縦横比で決める。横長なら船と島の中間を見る。縦長は
  // 視野が狭いので船寄り+少し引き、下部パネルに隠れないよう視線をやや
  // 沈めて船を画面上寄りに置く(島は回して見つける楽しみに残す)。
  const size = useThree((s) => s.size);
  const near = useMemo(() => {
    const aspect = size.width / Math.max(size.height, 1);
    const wide = aspect >= 1.05;
    const tx = boatX + (ISLAND_POS[0] - boatX) * (wide ? 0.5 : 0.08);
    return wide
      ? {
          pos: new THREE.Vector3(tx - 1.2, 1.9, 5.4),
          target: new THREE.Vector3(tx, 0.5, -0.5),
          maxPolar: Math.PI * 0.52,
        }
      : {
          pos: new THREE.Vector3(tx - 1.0, 1.9, 7.2),
          target: new THREE.Vector3(tx, -0.25, -0.5),
          maxPolar: Math.PI * 0.46,
        };
  }, [boatX, size.width, size.height]);

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
        count={620}
        factor={2.1}
        saturation={0}
        fade
        speed={animate ? 0.5 : 0}
      />
      <TappableMoon animate={animate} />
      <ShootingStar animate={animate} />
      <Sea />
      <Horizon />
      <Island />
      {/* 入力中の島の名前が、島の上にライブで浮かぶ */}
      {islandLabel && (
        <Html
          position={[ISLAND_POS[0], 1.9, ISLAND_POS[2]]}
          center
          distanceFactor={9}
          zIndexRange={[3, 0]}
          style={{ pointerEvents: "none" }}
        >
          <div className="voyage-world-label">{islandLabel}</div>
        </Html>
      )}
      <PlayfulBoat boatX={boatX} animate={animate} />
      <CameraRig
        phase={phase}
        animate={animate}
        near={near}
        onEntered={onEntered}
        onExited={onExited}
      />
      {phase === "idle" && (
        <OrbitControls
          target={[near.target.x, near.target.y, near.target.z]}
          enablePan={false}
          enableDamping
          minDistance={3.2}
          maxDistance={11}
          minPolarAngle={Math.PI * 0.16}
          maxPolarAngle={near.maxPolar}
        />
      )}
    </>
  );
}

/// 没入エディタ本体。全画面の夜の海+世界に馴染む半透明の編集UI。
export default function VoyageWorld({ dest, data, uid, onClose }: VoyageWorldProps) {
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const [phase, setPhase] = useState<Phase>(animate ? "enter" : "idle");

  // ---- 編集状態(DestinationDialogと同等) ----
  const [name, setName] = useState(dest?.name ?? "");
  const [itemUUID, setItemUUID] = useState<string | undefined>(dest?.itemUUID);
  // 新規の目的地は期日が既定(一番使われる目標のため)。編集時は保存済みの種類に従う。
  const [kind, setKind] = useState<"hours" | "date" | "done">(
    dest
      ? dest.manual
        ? "done"
        : dest.targetDate && !dest.targetMinutes
          ? "date"
          : "hours"
      : "date",
  );
  const [hours, setHours] = useState(
    dest?.targetMinutes ? String(Math.round(dest.targetMinutes / 60)) : "20",
  );
  const [dateStr, setDateStr] = useState(
    dest?.targetDate ? dest.targetDate.toISOString().slice(0, 10) : "",
  );
  const [working, setWorking] = useState(false);
  const confirmingRef = useRef(false);
  // 期日/累計時間を「触った」印。既存の値がすでに有効でも、開いた直後には
  // 自動保存しない(ただ見ただけで閉じてしまうのを防ぐ)ためのガード。
  const dateTouched = useRef(false);
  const hoursTouched = useRef(false);
  const autoSavedRef = useRef(false);

  const trimmed = name.replace(/^[\s　]+|[\s　]+$/g, "");
  const hoursNum = Number(hours);
  const valid =
    trimmed.length > 0 &&
    (kind === "hours"
      ? hoursNum > 0 && hoursNum <= 10000
      : kind === "date"
        ? dateStr.length === 10
        : dateStr.length === 0 || dateStr.length === 10); // 完了: 締切は任意

  // ---- 世界の配置(カードと同じ航路・島) ----
  const ratio = dest ? destinationProgress(dest, data.sessions).ratio : 0;
  const boatX = X_START + Math.min(Math.max(ratio, 0), 1) * (X_END - X_START);

  // ---- 閉じる(退場演出→onClose。reduced-motionはジャンプカット) ----
  const phaseRef = useRef(phase);
  phaseRef.current = phase;
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;
  const requestClose = useCallback(() => {
    if (confirmingRef.current || phaseRef.current === "exit") return;
    if (!animate) {
      onCloseRef.current();
      return;
    }
    setPhase("exit");
  }, [animate]);
  const handleEntered = useCallback(() => {
    setPhase((p) => (p === "enter" ? "idle" : p));
  }, []);
  const handleExited = useCallback(() => {
    onCloseRef.current();
  }, []);

  // Escで閉じる+表示中は背景スクロールを固定(Modalと同じ作法)。
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") requestClose();
    };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [requestClose]);

  // ---- 保存/削除(DestinationDialogと同等) ----
  const save = async () => {
    if (!valid || working) return;
    setWorking(true);
    await saveDestination(uid, {
      id: dest?.id,
      name: trimmed,
      itemUUID,
      targetMinutes: kind === "hours" ? Math.round(hoursNum * 60) : undefined,
      targetDate: kind !== "hours" && dateStr ? new Date(`${dateStr}T00:00:00`) : undefined,
      manual: kind === "done" ? true : undefined,
      manualDone: kind === "done" ? dest?.manualDone : undefined,
      createdAt: dest?.createdAt,
    });
    showToast(t("savedToast"));
    requestClose();
  };

  // 期日/累計時間を設定し終えたら、そのまま保存してズームアウト(ホームへ戻る)。
  // 「保存する」を別途押す一手間をなくす — 名前・項目だけの変更は従来通り
  // 保存ボタンで確定する(値を触っていなければここでは動かない)。
  useEffect(() => {
    // 目標の種類を切り替えたら、前の種類での「触った/自動保存済み」の印は捨てる。
    dateTouched.current = false;
    hoursTouched.current = false;
    autoSavedRef.current = false;
  }, [kind]);

  useEffect(() => {
    if (kind !== "date" || !dateTouched.current || autoSavedRef.current) return;
    if (dateStr.length !== 10 || !trimmed || working) return;
    autoSavedRef.current = true;
    void save();
  }, [dateStr, kind, trimmed, working]);

  const remove = async () => {
    if (!dest || working) return;
    confirmingRef.current = true;
    const ok = await askConfirm({
      title: t("deleteDestination"),
      message: t("deleteDestinationConfirm"),
      confirmLabel: t("delete"),
      danger: true,
    });
    confirmingRef.current = false;
    if (!ok) return;
    setWorking(true);
    await deleteDestination(uid, dest.id);
    requestClose();
  };

  // iOS Safari はキーボードでレイアウトビューポートが縮まないため、
  // visualViewport の縮み量ぶんだけ下部パネルを持ち上げる(--vv-lift)。
  const rootRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;
    const apply = () => {
      const lift = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
      rootRef.current?.style.setProperty("--vv-lift", `${lift}px`);
    };
    vv.addEventListener("resize", apply);
    vv.addEventListener("scroll", apply);
    apply();
    return () => {
      vv.removeEventListener("resize", apply);
      vv.removeEventListener("scroll", apply);
    };
  }, []);

  return (
    <div
      ref={rootRef}
      className="voyage-world"
      role="dialog"
      aria-modal="true"
      aria-label={t("destinationTitle")}
    >
      <Canvas
        dpr={[1, 2]}
        frameloop={animate ? "always" : "demand"}
        camera={{ position: [FAR_POS.x, FAR_POS.y, FAR_POS.z], fov: 36 }}
      >
        <WorldScene
          phase={phase}
          animate={animate}
          boatX={boatX}
          islandLabel={trimmed}
          onEntered={handleEntered}
          onExited={handleExited}
        />
      </Canvas>

      <div className={`voyage-world-ui${phase === "idle" ? "" : " hidden"}`}>
        <div className="voyage-world-top">
          <input
            className="field voyage-world-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={t("islandNamePlaceholder")}
            maxLength={60}
            aria-label={t("islandName")}
          />
          <button className="voyage-world-close" onClick={requestClose}>
            {t("close")}
          </button>
        </div>

        <div className="voyage-world-panel">
          <p className="section-label">{t("countsToward")}</p>
          <div className="chip-row">
            <button
              className={`chip${itemUUID === undefined ? " selected" : ""}`}
              onClick={() => setItemUUID(undefined)}
            >
              {t("allItems")}
            </button>
            {data.items.map((item) => (
              <button
                key={item.id}
                className={`chip${itemUUID === item.id ? " selected" : ""}`}
                onClick={() => setItemUUID(item.id)}
              >
                {item.name}
              </button>
            ))}
          </div>

          <p className="section-label">{t("goalKind")}</p>
          <div className="chip-row">
            <button
              className={`chip${kind === "date" ? " selected" : ""}`}
              onClick={() => setKind("date")}
            >
              {t("goalDate")}
            </button>
            <button
              className={`chip${kind === "hours" ? " selected" : ""}`}
              onClick={() => setKind("hours")}
            >
              {t("goalHours")}
            </button>
            <button
              className={`chip${kind === "done" ? " selected" : ""}`}
              onClick={() => setKind("done")}
            >
              {t("goalDone")}
            </button>
          </div>

          <div style={{ marginTop: 14 }}>
            {kind === "hours" ? (
              <div className="stepper-row" style={{ justifyContent: "flex-start" }}>
                <span className="stepper-value">
                  <input
                    className="stepper-input"
                    type="text"
                    inputMode="numeric"
                    value={hours}
                    onChange={(e) => {
                      hoursTouched.current = true;
                      setHours(e.target.value.replace(/[^0-9]/g, ""));
                    }}
                    onBlur={() => {
                      if (kind === "hours" && hoursTouched.current && valid && !working) {
                        void save();
                      }
                    }}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") e.currentTarget.blur();
                    }}
                    aria-label={t("goalHours")}
                  />
                  <span className="stepper-unit">{t("hoursUnit")}</span>
                </span>
              </div>
            ) : kind === "date" ? (
              <input
                className="field"
                type="date"
                value={dateStr}
                min={new Date().toISOString().slice(0, 10)}
                onChange={(e) => {
                  dateTouched.current = true;
                  setDateStr(e.target.value);
                }}
              />
            ) : (
              <>
                <p className="quest-intro">{t("goalDoneDesc")}</p>
                <input
                  className="field"
                  type="date"
                  value={dateStr}
                  min={new Date().toISOString().slice(0, 10)}
                  onChange={(e) => setDateStr(e.target.value)}
                  aria-label={t("optionalDateLabel")}
                />
                <p className="row-sub" style={{ marginTop: 4 }}>
                  {t("optionalDateLabel")}
                </p>
              </>
            )}
          </div>

          <div style={{ height: 18 }} />
          <button
            className="primary-button"
            onClick={save}
            disabled={!valid || working}
          >
            {t("save")}
          </button>
          {dest && (
            <button className="danger-button" onClick={remove} disabled={working}>
              {t("deleteDestination")}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
