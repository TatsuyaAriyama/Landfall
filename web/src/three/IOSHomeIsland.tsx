import { useEffect, useMemo, useRef } from "react";
import { useGLTF } from "@react-three/drei";
import { useFrame } from "@react-three/fiber";
import * as THREE from "three";
import worldDocument from "../world/iosHomeWorld.json";
import {
  buildIOSPaintCap,
  buildIOSTerrain,
  type IOSTerrainHeightField,
  type IOSTerrainStroke,
} from "./iosTerrain";

type Point = { x: number; y: number; z: number };
type Transform = Point & {
  pitch: number;
  yaw: number;
  roll: number;
  scale: number;
};
type Placement = {
  id: string;
  assetID: string;
  studioID?: string;
  transform: Transform;
};
type TerrainStroke = IOSTerrainStroke & {
  id: string;
  studioID?: string;
};
type PaintStroke = {
  id: string;
  studioID?: string;
  material: "grass" | "sand" | "path" | "rock" | "snow";
  width: number;
  points: Point[];
};

const document = worldDocument as {
  activeStudioID?: string;
  placements: Placement[];
  terrainStrokes?: TerrainStroke[];
  paintStrokes?: PaintStroke[];
};

const ACTIVE_STUDIO_ID = document.activeStudioID;
const ACTIVE_PLACEMENTS = document.placements.filter(
  (placement) => placement.studioID === ACTIVE_STUDIO_ID,
);
const ACTIVE_TERRAIN = (document.terrainStrokes ?? []).filter(
  (stroke) => stroke.studioID === ACTIVE_STUDIO_ID,
);
const ACTIVE_PAINT = (document.paintStrokes ?? []).filter(
  (stroke) => stroke.studioID === ACTIVE_STUDIO_ID,
);

const ASSET_URLS = {
  island_base: "/models/island_base.glb",
  small_tree: "/models/small_tree.glb",
} as const;

const MATERIAL_COLOR = {
  grass: "#62A164",
  earth: "#9A6847",
  sand: "#E5C980",
  path: "#929276",
  rock: "#7D8074",
  snow: "#E2E9DF",
} as const;

// Studio文書は島の土台をこの制作座標へ置いている。ランタイムでは原点へ
// 戻してから各シーンのpositionを適用し、カメラ・島名・当たり判定を一致させる。
const AUTHORED_ORIGIN: [number, number, number] = [1.2837114, 0.0119999265, 1.4501432];

function AuthoredAsset({ placement }: { placement: Placement }) {
  const url = ASSET_URLS[placement.assetID as keyof typeof ASSET_URLS];
  const island = useGLTF(ASSET_URLS.island_base);
  const smallTree = useGLTF(ASSET_URLS.small_tree);
  const source = url === ASSET_URLS.island_base ? island.scene : smallTree.scene;
  const model = useMemo(() => {
    const clone = source.clone(true);
    clone.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      child.castShadow = true;
      child.receiveShadow = true;
    });
    return clone;
  }, [source]);
  const t = placement.transform;
  return (
    <primitive
      object={model}
      position={[t.x, t.y, t.z]}
      rotation={[t.pitch, t.yaw, t.roll]}
      scale={t.scale}
    />
  );
}

function lakeBoundaryScale(angle: number): number {
  return 1 + Math.sin(angle * 3.1 + 0.4) * 0.055 + Math.cos(angle * 5.3 - 0.7) * 0.034;
}

function buildLakeShoreGeometry(): THREE.BufferGeometry {
  const segments = 72;
  const positions: number[] = [];
  const colors: number[] = [];
  const indices: number[] = [];
  const innerColor = new THREE.Color("#B2A67C");
  const outerColor = new THREE.Color("#7C8265");
  for (let segment = 0; segment <= segments; segment += 1) {
    const angle = (segment / segments) * Math.PI * 2;
    const boundary = lakeBoundaryScale(angle);
    const inner = boundary * (0.91 + Math.sin(angle * 5.2) * 0.012);
    const outer = boundary * (1.16 + Math.cos(angle * 4.1) * 0.024);
    positions.push(
      Math.cos(angle) * inner, 0.005, Math.sin(angle) * inner * 0.69,
      Math.cos(angle) * outer, Math.sin(angle * 6.3) * 0.01, Math.sin(angle) * outer * 0.72,
    );
    colors.push(innerColor.r, innerColor.g, innerColor.b);
    const shade = 0.96 + Math.sin(angle * 3.7) * 0.05;
    colors.push(outerColor.r * shade, outerColor.g * shade, outerColor.b * shade);
    if (segment < segments) {
      const base = segment * 2;
      indices.push(base, base + 2, base + 1, base + 1, base + 2, base + 3);
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

function buildLakeWaterGeometry(): THREE.BufferGeometry {
  const segments = 72;
  const rings = 7;
  const positions: number[] = [0, 0, 0];
  const colors: number[] = [];
  const indices: number[] = [];
  const center = new THREE.Color("#73CFC2");
  const edge = new THREE.Color("#296F6C");
  colors.push(center.r, center.g, center.b);
  for (let ring = 1; ring <= rings; ring += 1) {
    const radial = ring / rings;
    for (let segment = 0; segment < segments; segment += 1) {
      const angle = (segment / segments) * Math.PI * 2;
      const boundary = lakeBoundaryScale(angle) * 0.9;
      const staticRipple = Math.sin(angle * 5 + radial * 8.3) * 0.004 * radial;
      positions.push(
        Math.cos(angle) * radial * boundary,
        staticRipple,
        Math.sin(angle) * radial * boundary * 0.69,
      );
      const blend = radial * 0.52;
      colors.push(
        THREE.MathUtils.lerp(center.r, edge.r, blend),
        THREE.MathUtils.lerp(center.g, edge.g, blend),
        THREE.MathUtils.lerp(center.b, edge.b, blend),
      );
    }
  }
  for (let segment = 0; segment < segments; segment += 1) {
    indices.push(0, 1 + ((segment + 1) % segments), 1 + segment);
  }
  for (let ring = 1; ring < rings; ring += 1) {
    const innerStart = 1 + (ring - 1) * segments;
    const outerStart = 1 + ring * segments;
    for (let segment = 0; segment < segments; segment += 1) {
      const next = (segment + 1) % segments;
      const inner = innerStart + segment;
      const innerNext = innerStart + next;
      const outer = outerStart + segment;
      const outerNext = outerStart + next;
      indices.push(inner, outerNext, outer, inner, innerNext, outerNext);
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

function LakeWater({ animate }: { animate: boolean }) {
  const geometry = useMemo(buildLakeWaterGeometry, []);
  const basePositions = useMemo(
    () => new Float32Array((geometry.getAttribute("position") as THREE.BufferAttribute).array),
    [geometry],
  );
  useEffect(() => () => geometry.dispose(), [geometry]);
  useFrame(({ clock }) => {
    if (!animate) return;
    const position = geometry.getAttribute("position") as THREE.BufferAttribute;
    for (let index = 0; index < position.count; index += 1) {
      const offset = index * 3;
      const x = basePositions[offset];
      const z = basePositions[offset + 2];
      const waveA = Math.sin(x * 7 + clock.elapsedTime * 1.35);
      const waveB = Math.cos(z * 9 - clock.elapsedTime * 1.05);
      position.setY(index, basePositions[offset + 1] + (waveA + waveB) * 0.0065);
    }
    position.needsUpdate = true;
  });
  return (
    <mesh geometry={geometry} position={[0, 0.122, 0]} renderOrder={80}>
      <meshStandardMaterial
        color="#4A9F98"
        vertexColors
        emissive="#1E5C59"
        emissiveIntensity={0.06}
        roughness={0.2}
        metalness={0.03}
        side={THREE.DoubleSide}
        transparent
        opacity={0.9}
        depthWrite={false}
      />
    </mesh>
  );
}

function LakeRipples({ animate }: { animate: boolean }) {
  const meshes = useRef<(THREE.Mesh | null)[]>([]);
  const materials = useRef<(THREE.MeshBasicMaterial | null)[]>([]);
  useFrame(({ clock }) => {
    for (let index = 0; index < 3; index += 1) {
      const mesh = meshes.current[index];
      const material = materials.current[index];
      if (!mesh || !material) continue;
      if (!animate) {
        material.opacity = 0;
        continue;
      }
      const delay = index * 0.92;
      const cycle = 3 + delay;
      const phaseTime = clock.elapsedTime % cycle;
      if (phaseTime < delay) {
        material.opacity = 0;
        continue;
      }
      const progress = Math.min(1, (phaseTime - delay) / 3);
      const scale = 0.36 + progress * 0.92;
      mesh.scale.set(scale, scale * 0.7, 1);
      material.opacity = Math.sin(progress * Math.PI) * 0.34;
    }
  });
  return (
    <>
      {[0, 1, 2].map((index) => (
        <mesh
          key={index}
          ref={(node) => { meshes.current[index] = node; }}
          position={[-0.32 + index * 0.28, 0.143 + index * 0.001, -0.12 + (index % 2) * 0.22]}
          rotation={[-Math.PI / 2, 0, 0]}
          renderOrder={82 + index}
        >
          <torusGeometry args={[0.68, 0.008, 5, 64]} />
          <meshBasicMaterial
            ref={(material) => { materials.current[index] = material; }}
            color="#BCE8DC"
            transparent
            opacity={0}
            blending={THREE.AdditiveBlending}
            depthWrite={false}
          />
        </mesh>
      ))}
    </>
  );
}

function LakeReeds() {
  return (
    <>
      {[0, 1, 2, 3].map((cluster) => {
        const angle = cluster * 1.47 + 0.46;
        return (
          <group
            key={cluster}
            position={[
              Math.cos(angle) * 1.02 * lakeBoundaryScale(angle),
              0.1,
              Math.sin(angle) * 0.7 * lakeBoundaryScale(angle),
            ]}
            rotation={[0, -angle, 0]}
          >
            {[0, 1, 2, 3, 4].map((reedIndex) => {
              const height = 0.25 + ((reedIndex + cluster) % 3) * 0.055;
              const x = (reedIndex - 2) * 0.045;
              const z = Math.sin(reedIndex * 2.3) * 0.035;
              return (
                <group key={reedIndex}>
                  <mesh position={[x, height * 0.5, z]} rotation={[0, 0, (reedIndex - 2) * 0.018]} castShadow>
                    <cylinderGeometry args={[0.01, 0.01, height, 6]} />
                    <meshStandardMaterial color="#456A4D" roughness={0.9} />
                  </mesh>
                  {reedIndex % 2 === 0 ? (
                    <mesh position={[x, height + 0.018, z]} scale={[1, 1.8, 1]}>
                      <sphereGeometry args={[0.024, 7, 5]} />
                      <meshStandardMaterial color="#5B4634" roughness={0.96} />
                    </mesh>
                  ) : null}
                </group>
              );
            })}
          </group>
        );
      })}
    </>
  );
}

function SmallLake({ transform, animate }: { transform: Transform; animate: boolean }) {
  const shoreGeometry = useMemo(buildLakeShoreGeometry, []);
  useEffect(() => () => shoreGeometry.dispose(), [shoreGeometry]);
  return (
    <group
      position={[transform.x, transform.y, transform.z]}
      rotation={[transform.pitch, transform.yaw, transform.roll]}
      scale={transform.scale}
    >
      <mesh position={[0, 0.05, 0]} scale={[1.34, 1, 0.91]} castShadow receiveShadow>
        <cylinderGeometry args={[1, 1, 0.1, 48]} />
        <meshStandardMaterial color="#74715E" roughness={0.98} />
      </mesh>
      <mesh geometry={shoreGeometry} position={[0, 0.105, 0]} castShadow receiveShadow>
        <meshStandardMaterial color="#FFFFFF" vertexColors roughness={0.97} side={THREE.DoubleSide} />
      </mesh>
      <LakeWater animate={animate} />
      {Array.from({ length: 14 }, (_, index) => {
        const angle = (index / 14) * Math.PI * 2 + Math.sin(index * 2.19) * 0.08;
        const boundary = lakeBoundaryScale(angle);
        const radius = 1.13 + Math.sin(index * 1.71) * 0.08;
        return (
          <mesh
            key={index}
            position={[
              Math.cos(angle) * radius * boundary * 1.1,
              0.14 + (index % 2) * 0.012,
              Math.sin(angle) * radius * boundary * 0.76,
            ]}
            rotation={[0, angle * 1.7, 0]}
            scale={[
              1 + Math.sin(index * 0.9) * 0.2,
              0.58 + (index % 4) * 0.06,
              0.82 + Math.cos(index * 1.3) * 0.14,
            ]}
            castShadow
          >
            <sphereGeometry args={[0.085 + (index % 3) * 0.014, 7, 5]} />
            <meshStandardMaterial color="#777A6D" roughness={0.92} />
          </mesh>
        );
      })}
      <LakeReeds />
      <LakeRipples animate={animate} />
    </group>
  );
}

function PaintMark({
  stroke,
  heightField,
}: {
  stroke: PaintStroke;
  heightField: IOSTerrainHeightField | undefined;
}) {
  const color = MATERIAL_COLOR[stroke.material];
  const geometries = useMemo(
    () =>
      stroke.points.map((point) => buildIOSPaintCap(stroke.id, point, stroke.width, heightField)),
    [heightField, stroke],
  );
  useEffect(() => () => geometries.forEach((geometry) => geometry.dispose()), [geometries]);
  return (
    <>
      {geometries.map((geometry, index) => (
        <mesh key={index} geometry={geometry} receiveShadow renderOrder={61}>
          <meshStandardMaterial
            color={color}
            vertexColors
            emissive={color}
            emissiveIntensity={0.26}
            roughness={0.96}
            side={THREE.DoubleSide}
            polygonOffset
            polygonOffsetFactor={-1}
          />
        </mesh>
      ))}
    </>
  );
}

export interface IOSHomeIslandProps {
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number;
  animate?: boolean;
}

/// iOSの3Dスタジオで最後に保存された「潮風の峰島」を読むだけのランタイム。
/// Webへ編集UIや保存機能は持ち込まず、完成した配置データだけを再生する。
export default function IOSHomeIsland({
  position = [0, 0, 0],
  rotation = [0, -0.16, 0],
  scale = 1,
  animate = true,
}: IOSHomeIslandProps) {
  const terrain = useMemo(() => buildIOSTerrain(ACTIVE_TERRAIN), []);
  useEffect(() => () => terrain?.geometry.dispose(), [terrain]);
  return (
    <group position={position} rotation={rotation} scale={scale}>
      <group position={AUTHORED_ORIGIN}>
        {ACTIVE_PLACEMENTS.map((placement) => {
          if (placement.assetID === "small_lake") {
            return <SmallLake key={placement.id} transform={placement.transform} animate={animate} />;
          }
          if (placement.assetID === "island_base" || placement.assetID === "small_tree") {
            return <AuthoredAsset key={placement.id} placement={placement} />;
          }
          return null;
        })}
        {terrain ? (
          <mesh geometry={terrain.geometry} castShadow receiveShadow renderOrder={12}>
            <meshStandardMaterial
              color="#FFFFFF"
              vertexColors
              roughness={0.94}
              side={THREE.DoubleSide}
            />
          </mesh>
        ) : null}
        {ACTIVE_PAINT.map((stroke) => (
          <PaintMark key={stroke.id} stroke={stroke} heightField={terrain?.heightField} />
        ))}
      </group>
    </group>
  );
}

useGLTF.preload(ASSET_URLS.island_base);
useGLTF.preload(ASSET_URLS.small_tree);
