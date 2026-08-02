import { useEffect, useMemo, useRef } from "react";
import { useFrame } from "@react-three/fiber";
import { useGLTF } from "@react-three/drei";
import * as THREE from "three";

// Blender-authored hero tree.  The asset uses connected curved wood, raised bark
// and lichen, fine twigs, and more than a thousand individually folded leaves.
// Runtime work is limited to a very small foliage vertex displacement; the trunk
// remains perfectly rooted while leaves and thin twigs yield to the sea wind.

export interface WindsweptTreeProps {
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number;
  animate?: boolean;
  windStrength?: number;
}

interface WindShader {
  uniforms: {
    lfTreeTime: { value: number };
    lfTreeWind: { value: number };
  };
}

const MODEL_URL = "/models/windswept_tree.glb";

function addWind(
  material: THREE.MeshStandardMaterial,
  strength: number,
  shaders: React.RefObject<WindShader[]>,
) {
  material.onBeforeCompile = (shader) => {
    shader.uniforms.lfTreeTime = { value: 0 };
    shader.uniforms.lfTreeWind = { value: 1 };
    shader.vertexShader = `
      uniform float lfTreeTime;
      uniform float lfTreeWind;
      ${shader.vertexShader}
    `.replace(
      "#include <begin_vertex>",
      `#include <begin_vertex>
      float lfTreeHeight = smoothstep(0.62, 2.42, position.y);
      float lfTreeLongGust = sin(lfTreeTime * 0.54 + position.y * 1.8 + position.z * 0.75);
      float lfTreeBreath = sin(lfTreeTime * 1.31 + position.x * 2.2 - position.z * 1.35);
      float lfTreeFlutter = sin(lfTreeTime * 2.73 + position.x * 5.1 + position.y * 3.7);
      float lfTreeWave = lfTreeLongGust * 0.66 + lfTreeBreath * 0.26 + lfTreeFlutter * 0.08;
      transformed.x += lfTreeWave * ${strength.toFixed(4)} * lfTreeWind * lfTreeHeight;
      transformed.z += lfTreeBreath * ${(strength * 0.38).toFixed(4)} * lfTreeWind * lfTreeHeight;
      `,
    );
    const registered = shader as unknown as WindShader;
    if (!shaders.current.includes(registered)) shaders.current.push(registered);
  };
  material.customProgramCacheKey = () => `lf-windswept-tree-${strength}`;
  material.needsUpdate = true;
}

export default function WindsweptTree({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  animate = true,
  windStrength = 1,
}: WindsweptTreeProps) {
  const { scene } = useGLTF(MODEL_URL);
  const windShaders = useRef<WindShader[]>([]);

  const model = useMemo(() => {
    windShaders.current = [];
    const clone = scene.clone(true);
    clone.name = "WindsweptTree_Hero";
    clone.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      child.castShadow = true;
      child.receiveShadow = true;
      const sourceMaterials = Array.isArray(child.material) ? child.material : [child.material];
      const clonedMaterials = sourceMaterials.map((source) => {
        const cloned = source.clone();
        const isLeaf = cloned.name.includes("TreeLeaf");
        const isTwig = cloned.name.includes("TreeTwig");
        if ((isLeaf || isTwig) && cloned instanceof THREE.MeshStandardMaterial) {
          addWind(cloned, isLeaf ? 0.026 : 0.008, windShaders);
        }
        return cloned;
      });
      child.material = Array.isArray(child.material) ? clonedMaterials : clonedMaterials[0];
    });
    return clone;
  }, [scene]);

  useEffect(
    () => () => {
      model.traverse((child) => {
        if (!(child instanceof THREE.Mesh)) return;
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((value) => value.dispose());
      });
      windShaders.current = [];
    },
    [model],
  );

  useFrame(({ clock }) => {
    const time = clock.elapsedTime;
    for (const shader of windShaders.current) {
      shader.uniforms.lfTreeTime.value = time;
      shader.uniforms.lfTreeWind.value = animate ? windStrength : 0;
    }
  });

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={model} />
    </group>
  );
}

useGLTF.preload(MODEL_URL);
