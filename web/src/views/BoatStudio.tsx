import { useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, Stars } from "@react-three/drei";
import type { UserData } from "../data";
import type { BoatParts } from "../symbols";
import BoatModel from "../three/BoatModel";
import PhoenixModel, { type PhoenixPose } from "../three/PhoenixModel";
import { Moon, NIGHT_BG, Ripples, Sea } from "../three/SeaParts";
import {
  BOAT_OPTIONS,
  boatPartId,
  boatProps,
  isBoatOptionUnlocked,
  setBoatPart,
  totalMinutes,
  type BoatPart,
} from "../boat";
import { pushProfileEverywhere } from "../harbor";
import { lang, t, unlockAtLabel, type I18nKey } from "../i18n";

// 船スタジオ。夜の海に浮かぶ自分の船を、three.jsで360度眺めながら着せ替える。
// 船体・海・月・波紋の3D部品は src/three/ に共有化してある(VoyageSceneと同じ世界)。

/// 夜の海のシーン一式。背景・霧・星・月・海・波紋・船・カメラ操作。
function NightSea({ parts, animate }: { parts: BoatParts; animate: boolean }) {
  const [autoRotate, setAutoRotate] = useState(true);
  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 11, 30]} />
      {/* 月光: sand色のdirectional+暖色の弱いambient+海色の弱いfill。影は使わない。 */}
      <ambientLight color="#ffe9c8" intensity={0.45} />
      <directionalLight color="#EADEBD" intensity={1.15} position={[-6, 8, -5]} />
      <directionalLight color="#5DCAA5" intensity={0.2} position={[5, 3, 6]} />
      <Stars
        radius={42}
        depth={18}
        count={900}
        factor={2.2}
        saturation={0}
        fade
        speed={animate ? 0.6 : 0}
      />
      <Moon position={[-8.5, 5.6, -14]} />
      <Sea />
      <Ripples animate={animate} />
      <BoatModel parts={parts} animate={animate} />
      <OrbitControls
        target={[0, 0.7, 0]}
        enablePan={false}
        enableDamping
        minDistance={3.4}
        maxDistance={9}
        minPolarAngle={Math.PI * 0.18}
        maxPolarAngle={Math.PI * 0.52}
        autoRotate={autoRotate && animate}
        autoRotateSpeed={0.6}
        onStart={() => setAutoRotate(false)}
      />
    </>
  );
}

/// 航海士ステージ。同じ夜の海に、プレイヤー(不死鳥の航海士)を大きく立たせて見せる。
/// 船より一回り寄って、ポーズ切り替えで歩行や仕草を確認できる。
function SailorStage({ pose, animate }: { pose: PhoenixPose; animate: boolean }) {
  const [autoRotate, setAutoRotate] = useState(true);
  return (
    <>
      <color attach="background" args={[NIGHT_BG]} />
      <fog attach="fog" args={[NIGHT_BG, 11, 30]} />
      <ambientLight color="#ffe9c8" intensity={0.6} />
      <directionalLight color="#EADEBD" intensity={1.4} position={[-6, 8, -5]} />
      <directionalLight color="#5DCAA5" intensity={0.28} position={[5, 3, 6]} />
      <Stars
        radius={42}
        depth={18}
        count={900}
        factor={2.2}
        saturation={0}
        fade
        speed={animate ? 0.6 : 0}
      />
      <Moon position={[-8.5, 5.6, -14]} />
      <Sea />
      <Ripples animate={animate} />
      <group scale={0.95}>
        <PhoenixModel animate={animate} pose={pose} />
      </group>
      <OrbitControls
        target={[0, 0.62, 0]}
        enablePan={false}
        enableDamping
        minDistance={1.8}
        maxDistance={7}
        minPolarAngle={Math.PI * 0.14}
        maxPolarAngle={Math.PI * 0.56}
        autoRotate={autoRotate && animate}
        autoRotateSpeed={0.6}
        onStart={() => setAutoRotate(false)}
      />
    </>
  );
}

const POSES: [PhoenixPose, I18nKey][] = [
  ["idle", "poseIdle"],
  ["walk", "poseWalk"],
  ["raise", "poseRaise"],
  ["hail", "poseHail"],
];

/// 装いタブ。上が3Dステージ、下がカスタマイズ。
/// 「船」と「航海士」を切り替えて、それぞれを360度眺められる。
export default function BoatStudio({ data }: { data: UserData }) {
  const [, setTick] = useState(0);
  const [mode, setMode] = useState<"boat" | "sailor">("boat");
  const [pose, setPose] = useState<PhoenixPose>("idle");
  const [animate] = useState(
    () => !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const total = totalMinutes(data.sessions);
  const totalLabel =
    lang === "ja" ? `${Math.floor(total / 60)}時間` : `${Math.floor(total / 60)}h`;
  const parts = boatProps();

  // 部位を選んだら、参加中の港の「みんなの海」へも即反映する
  // (fire-and-forget。オフラインや未サインインの失敗は握りつぶす)。
  const choose = (part: BoatPart, id: string) => {
    setBoatPart(part, id);
    setTick((n) => n + 1);
    void pushProfileEverywhere().catch(() => {});
  };

  return (
    <div>
      <h1 className="page-title">
        {mode === "boat" ? t("boatStudioTitle") : t("sailorTitle")}
      </h1>
      {/* 「船」と「航海士」の切り替え。装いタブの入口。 */}
      <div className="chip-row" style={{ marginBottom: 12 }}>
        <button
          className={`chip${mode === "boat" ? " selected" : ""}`}
          onClick={() => setMode("boat")}
        >
          {t("dressBoat")}
        </button>
        <button
          className={`chip${mode === "sailor" ? " selected" : ""}`}
          onClick={() => setMode("sailor")}
        >
          {t("dressSailor")}
        </button>
      </div>
      <div className="boat-studio-stage">
        <Canvas
          dpr={[1, 2]}
          frameloop={animate ? "always" : "demand"}
          camera={
            mode === "boat"
              ? { position: [3.1, 1.7, 4.3], fov: 40 }
              : { position: [1.7, 1.35, 3.4], fov: 40 }
          }
        >
          {mode === "boat" ? (
            <NightSea parts={parts} animate={animate} />
          ) : (
            <SailorStage pose={pose} animate={animate} />
          )}
        </Canvas>
      </div>
      <p className="boat-studio-hint">{t("boatHint")}</p>
      {mode === "sailor" ? (
        <div className="chip-row" style={{ marginTop: 4 }}>
          {POSES.map(([key, labelKey]) => (
            <button
              key={key}
              className={`chip${pose === key ? " selected" : ""}`}
              onClick={() => setPose(key)}
            >
              {t(labelKey)}
            </button>
          ))}
        </div>
      ) : null}
      {mode === "sailor" ? null : (
        <>
          <p className="boat-studio-total">
            {t("totalVoyage")}: {totalLabel}
          </p>
          {(
        [
          ["sail", "sailColor"],
          ["jib", "jibLabel"],
          ["hull", "hullLabel"],
          ["stripe", "stripeLabel"],
          ["flag", "flagLabel"],
        ] as [BoatPart, I18nKey][]
      ).map(([part, labelKey]) => (
        <div key={part}>
          <p className="row-sub" style={{ margin: "14px 0 6px" }}>
            {t(labelKey)}
          </p>
          <div className="chip-row">
            {BOAT_OPTIONS[part].map((o) => {
              // 戦利品は累計時間ではなく「共同航海の到着」で解放される。
              const locked = !isBoatOptionUnlocked(o, total);
              const lockLabel = o.lootKey
                ? t("lootLock")
                : unlockAtLabel(o.unlockMinutes / 60);
              const selected = boatPartId(part) === o.id;
              if (o.color) {
                return (
                  <button
                    key={o.id}
                    className={`swatch${selected ? " selected" : ""}`}
                    style={{ background: o.color, opacity: locked ? 0.3 : 1 }}
                    disabled={locked}
                    title={locked ? lockLabel : o.id}
                    onClick={() => choose(part, o.id)}
                    aria-label={locked ? `${o.id} · ${lockLabel}` : o.id}
                  />
                );
              }
              const label = t(
                (o.id === "none"
                  ? "flagNone"
                  : o.id === "pennant"
                    ? "flagPennant"
                    : o.id === "swallow"
                      ? "flagSwallow"
                      : "flagKraken") as I18nKey,
              );
              return (
                <button
                  key={o.id}
                  className={`chip${selected ? " selected" : ""}`}
                  disabled={locked}
                  style={locked ? { opacity: 0.4 } : undefined}
                  onClick={() => choose(part, o.id)}
                >
                  {label}
                  {locked ? ` · ${lockLabel}` : ""}
                </button>
              );
            })}
          </div>
        </div>
          ))}
        </>
      )}
    </div>
  );
}
