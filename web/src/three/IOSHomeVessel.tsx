import { useEffect, useMemo, useRef } from "react";
import { useGLTF } from "@react-three/drei";
import { useFrame } from "@react-three/fiber";
import * as THREE from "three";
import { boatPartId } from "../boat";

const BOAT_URL = "/models/landfall_boat.glb";
const IOS_SAIL_COLORS: Record<string, string> = {
  sand: "#EADEBD",
  coral: "#F0997B",
  sunYellow: "#F3C065",
  seaGreen: "#5DCAA5",
  lavender: "#CECBF6",
  horizonBlue: "#7FA8B8",
};

function recolor(material: THREE.Material, color: THREE.ColorRepresentation) {
  if (material instanceof THREE.MeshStandardMaterial) material.color.set(color);
}

/// iOS AftideHomeSceneFactory.makeNavigatorPOVBoat と同じ完成船。
/// カメラは甲板上に置き、航海士本人だけを隠して一人称の前景にする。
export default function IOSHomeVessel({ animate }: { animate: boolean }) {
  const source = useGLTF(BOAT_URL).scene;
  const vessel = useRef<THREE.Group>(null);
  const sailColor = useMemo(
    () => IOS_SAIL_COLORS[boatPartId("sail")] ?? IOS_SAIL_COLORS.sand,
    [],
  );
  const model = useMemo(() => {
    const clone = source.clone(true);
    clone.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      child.castShadow = true;
      child.receiveShadow = true;
      child.frustumCulled = false;
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      const copies = materials.map((material) => material.clone());
      for (const material of copies) {
        switch (material.name) {
          case "LF_BoatHull":
            recolor(material, "#EADEBD");
            break;
          case "LF_BoatDeck":
            recolor(material, new THREE.Color("#EADEBD").multiplyScalar(0.72));
            break;
          case "LF_BoatMainSail":
          case "LF_BoatJib":
            recolor(material, sailColor);
            break;
          case "LF_BoatCockpit":
            recolor(material, "#F0997B");
            break;
          case "LF_BoatStripe":
          case "LF_BoatFlag":
            child.visible = false;
            break;
          default:
            break;
        }
      }
      child.material = Array.isArray(child.material) ? copies : copies[0];
    });
    return clone;
  }, [sailColor, source]);

  useEffect(
    () => () => {
      model.traverse((child) => {
        if (!(child instanceof THREE.Mesh)) return;
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((material) => material.dispose());
      });
    },
    [model],
  );

  useFrame(({ clock }) => {
    const group = vessel.current;
    if (!group) return;
    const time = clock.elapsedTime;
    const roll = animate ? Math.sin(time * 0.52) * 0.012 : 0;
    const rise = animate ? Math.sin(time * 0.68 + 0.7) * 0.035 : 0;
    group.position.y = rise * 0.45;
    group.rotation.x = -roll * 0.55;
    group.rotation.z = roll * 0.35;
  });

  return (
    <group ref={vessel} scale={2.2}>
      <primitive object={model} />
    </group>
  );
}

useGLTF.preload(BOAT_URL);
