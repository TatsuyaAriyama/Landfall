import { useLayoutEffect, useState } from "react";
import { Canvas, useThree } from "@react-three/fiber";
import { ContactShadows, OrbitControls } from "@react-three/drei";
import WindsweptTree from "./WindsweptTree";

function TreeFraming() {
  const { camera, size } = useThree();

  useLayoutEffect(() => {
    // 縦長画面は水平画角が極端に狭い。固定距離のままだと、横へ流れる樹冠が
    // 左右で切れるため、縦横比を見てカメラだけ一歩引く。
    if (size.width / Math.max(size.height, 1) < 0.72) {
      camera.position.set(5.2, 2.9, 8.1);
    } else {
      camera.position.set(3.25, 2.15, 4.3);
    }
    camera.lookAt(0.1, 1.05, 0);
  }, [camera, size.height, size.width]);

  return null;
}

// 目的地の一本樹だけを360度確認する展示ビュー。URLハッシュ #tree で開く。
export default function TreeViewer() {
  const [animate, setAnimate] = useState(true);
  const [autoRotate, setAutoRotate] = useState(true);

  return (
    <main className="tree-viewer">
      <Canvas
        dpr={[1, 2]}
        shadows
        camera={{ position: [3.25, 2.15, 4.3], fov: 34, near: 0.1, far: 30 }}
      >
        <TreeFraming />
        <color attach="background" args={["#D8E4D9"]} />
        <fog attach="fog" args={["#D8E4D9", 9, 20]} />
        <hemisphereLight args={["#F6EEDC", "#577062", 1.35]} />
        <directionalLight
          castShadow
          color="#FFF0D1"
          intensity={2.1}
          position={[-3.5, 6, 4]}
          shadow-mapSize={[1024, 1024]}
          shadow-camera-near={0.5}
          shadow-camera-far={14}
          shadow-camera-left={-3}
          shadow-camera-right={3}
          shadow-camera-top={3}
          shadow-camera-bottom={-3}
        />
        <directionalLight color="#76A68C" intensity={0.65} position={[4, 2.5, -3]} />

        <WindsweptTree position={[0, 0.03, 0]} scale={1.28} animate={animate} />
        <mesh receiveShadow rotation={[-Math.PI / 2, 0, 0]} position={[0, 0, 0]}>
          <circleGeometry args={[2.15, 64]} />
          <meshStandardMaterial color="#C9C3A7" roughness={1} />
        </mesh>
        <ContactShadows
          position={[0, 0.012, 0]}
          opacity={0.34}
          scale={5}
          blur={2.4}
          far={4}
          color="#243B31"
        />

        <OrbitControls
          target={[0.1, 1.05, 0]}
          enablePan={false}
          enableDamping
          minDistance={2.7}
          maxDistance={10.5}
          minPolarAngle={Math.PI * 0.16}
          maxPolarAngle={Math.PI * 0.49}
          autoRotate={autoRotate}
          autoRotateSpeed={0.65}
          onStart={() => setAutoRotate(false)}
        />
      </Canvas>

      <section className="tree-viewer-caption" aria-label="一本樹の操作">
        <p>WINDSWEPT COASTAL TREE</p>
        <h1>海風の一本樹</h1>
        <span>ドラッグで回転 · ピンチで拡大</span>
      </section>
      <div className="tree-viewer-actions">
        <button type="button" onClick={() => setAnimate((value) => !value)}>
          {animate ? "風を止める" : "風を吹かせる"}
        </button>
        <button
          type="button"
          onClick={() => {
            location.hash = "";
            location.reload();
          }}
        >
          閉じる
        </button>
      </div>
    </main>
  );
}
