import { useState } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, Stars } from "@react-three/drei";
import { Moon, NIGHT_BG } from "./SeaParts";
import PhoenixModel from "./PhoenixModel";

// 航海士フェニックスの360度ビューア。URLハッシュ #phoenix で開く。
// 背景は最小限(夜色+星+月)にして、中央のキャラクターだけを見せる。
// ドラッグで自由に回せるほか、向きのプリセットで正面・横・背面へ一発移動。

const YAWS = [0, 90, 180, 270];

export default function PhoenixViewer() {
  const [yaw, setYaw] = useState(0);
  const [autoRotate, setAutoRotate] = useState(true);

  return (
    <div className="phoenix-viewer">
      <Canvas dpr={[1, 2]} camera={{ position: [1.6, 1.3, 3.4], fov: 38 }}>
        <color attach="background" args={[NIGHT_BG]} />
        {/* 月光: BoatStudioと同じトーン+キャラ見せ用に少しだけ明るく。影は使わない。 */}
        <ambientLight color="#ffe9c8" intensity={0.6} />
        <directionalLight color="#EADEBD" intensity={1.45} position={[-6, 8, -5]} />
        <directionalLight color="#5DCAA5" intensity={0.3} position={[5, 3, 6]} />
        <Stars radius={42} depth={18} count={320} factor={2.0} saturation={0} fade speed={0.4} />
        <Moon position={[-8, 4.2, -14]} />
        <group rotation={[0, (yaw * Math.PI) / 180, 0]}>
          <PhoenixModel animate />
        </group>
        <OrbitControls
          target={[0, 0.62, 0]}
          enablePan={false}
          enableDamping
          minDistance={1.6}
          maxDistance={7}
          minPolarAngle={Math.PI * 0.12}
          maxPolarAngle={Math.PI * 0.58}
          autoRotate={autoRotate}
          autoRotateSpeed={0.8}
          onStart={() => setAutoRotate(false)}
        />
      </Canvas>

      <div className="phoenix-viewer-ui">
        <div className="chip-row">
          {YAWS.map((deg) => (
            <button
              key={deg}
              className={`chip${yaw === deg ? " selected" : ""}`}
              onClick={() => setYaw(deg)}
            >
              {deg}°
            </button>
          ))}
          <button
            className="chip"
            onClick={() => {
              location.hash = "";
              location.reload();
            }}
          >
            閉じる
          </button>
        </div>
      </div>
    </div>
  );
}
