import { useLayoutEffect, useRef } from "react";
import { useFrame } from "@react-three/fiber";
import * as THREE from "three";

// 海から吹き続ける風に沿って育った、目的地の一本樹。
//
// 遠景では「傾いた幹 + 横へ流れる樹冠」という輪郭で読め、上陸時の近景では
// 露出根、枝分かれ、樹皮の色むら、樹冠からこぼれる葉まで見える密度にする。
// ただし枝・葉塊・小葉はそれぞれ InstancedMesh にまとめ、一本あたり3 draw callに留める。

export interface WindsweptTreeProps {
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number;
  animate?: boolean;
  windStrength?: number;
}

interface BranchSegment {
  from: [number, number, number];
  to: [number, number, number];
  radius: number;
  shade: string;
}

interface CrownCluster {
  at: [number, number, number];
  scale: [number, number, number];
  rotation: [number, number, number];
  color: string;
}

const BARK_DEEP = "#3A261B";
const BARK = "#60432B";
const BARK_SUN = "#7B5A36";
const LEAF_DEEP = "#164F43";
const LEAF_MID = "#26705A";
const LEAF_LIGHT = "#4F8D67";
const LEAF_SUN = "#78A572";

// 先端ほど細くなる共通の枝。太さと長さはインスタンス行列で変える。
const BRANCH_GEO = new THREE.CylinderGeometry(0.68, 1, 1, 7, 2, false);
const BRANCH_MAT = new THREE.MeshStandardMaterial({
  color: "#ffffff",
  roughness: 1,
  metalness: 0,
  flatShading: true,
});

// 正球を避け、海風に削られた不均一な葉塊を作る。
const CROWN_GEO = (() => {
  const geometry = new THREE.IcosahedronGeometry(1, 1);
  const position = geometry.getAttribute("position") as THREE.BufferAttribute;
  const point = new THREE.Vector3();
  for (let index = 0; index < position.count; index += 1) {
    point.fromBufferAttribute(position, index);
    const ripple =
      1 +
      Math.sin(point.x * 7.1 + point.y * 3.7) * 0.055 +
      Math.cos(point.z * 6.3 - point.y * 4.1) * 0.04;
    position.setXYZ(index, point.x * ripple, point.y * ripple, point.z * ripple);
  }
  geometry.computeVertexNormals();
  return geometry;
})();
const CROWN_MAT = new THREE.MeshStandardMaterial({
  color: "#ffffff",
  roughness: 0.92,
  metalness: 0,
  flatShading: true,
});

// 樹冠の外周だけに置く小葉。葉塊のシルエットを崩し、球の寄せ集め感を消す。
const LEAF_GEO = new THREE.CircleGeometry(1, 5);
const LEAF_MAT = new THREE.MeshStandardMaterial({
  color: "#ffffff",
  roughness: 0.95,
  metalness: 0,
  flatShading: true,
  side: THREE.DoubleSide,
});

const KNOT_GEO = new THREE.SphereGeometry(1, 7, 5);
const KNOT_MAT = new THREE.MeshStandardMaterial({
  color: BARK_DEEP,
  roughness: 1,
  flatShading: true,
});

// 幹3節、主枝、風下へ伸びる長い枝、地面を掴む露出根。
const BRANCHES: BranchSegment[] = [
  { from: [0, 0.02, 0], to: [0.035, 0.36, 0.015], radius: 0.19, shade: BARK_DEEP },
  { from: [0.035, 0.34, 0.015], to: [-0.035, 0.7, 0], radius: 0.155, shade: BARK },
  { from: [-0.035, 0.68, 0], to: [0.025, 1.01, -0.015], radius: 0.12, shade: BARK_SUN },

  { from: [0.01, 0.83, -0.01], to: [0.3, 1.18, -0.035], radius: 0.092, shade: BARK },
  { from: [0.28, 1.16, -0.035], to: [0.56, 1.42, -0.07], radius: 0.067, shade: BARK_SUN },
  { from: [0.54, 1.4, -0.07], to: [0.84, 1.56, -0.025], radius: 0.047, shade: BARK },
  { from: [0.29, 1.17, -0.02], to: [0.4, 1.5, 0.13], radius: 0.056, shade: BARK_SUN },
  { from: [0.39, 1.48, 0.13], to: [0.49, 1.69, 0.22], radius: 0.036, shade: BARK },

  { from: [-0.02, 0.7, 0.01], to: [-0.29, 1.04, 0.065], radius: 0.078, shade: BARK },
  { from: [-0.28, 1.02, 0.065], to: [-0.45, 1.29, 0.13], radius: 0.052, shade: BARK_SUN },
  { from: [-0.44, 1.27, 0.13], to: [-0.67, 1.43, 0.065], radius: 0.034, shade: BARK },
  { from: [0.015, 0.97, 0], to: [0.13, 1.28, 0.26], radius: 0.061, shade: BARK },
  { from: [0.12, 1.26, 0.25], to: [0.25, 1.46, 0.4], radius: 0.037, shade: BARK_SUN },
  { from: [0.3, 1.17, -0.045], to: [0.47, 1.36, -0.31], radius: 0.047, shade: BARK_DEEP },

  { from: [0.01, 0.08, 0], to: [0.43, 0.015, 0.1], radius: 0.082, shade: BARK_DEEP },
  { from: [0, 0.07, 0], to: [-0.38, 0.012, 0.2], radius: 0.075, shade: BARK },
  { from: [0, 0.065, 0], to: [-0.23, 0.01, -0.36], radius: 0.07, shade: BARK_DEEP },
  { from: [0.015, 0.06, 0], to: [0.31, 0.008, -0.29], radius: 0.065, shade: BARK_SUN },
];

// 主な葉塊は枝先を覆いつつ、風下(+x)へ長い一枚の輪郭を作る。
const CROWN_PIVOT = new THREE.Vector3(0.03, 1.08, 0);
const CROWN: CrownCluster[] = [
  { at: [-0.58, 1.42, 0.08], scale: [0.36, 0.28, 0.32], rotation: [0.1, 0.2, -0.1], color: LEAF_DEEP },
  { at: [-0.31, 1.44, 0.13], scale: [0.4, 0.34, 0.37], rotation: [-0.1, 0.8, 0.08], color: LEAF_MID },
  { at: [0.06, 1.44, 0.27], scale: [0.42, 0.32, 0.36], rotation: [0.1, -0.2, -0.06], color: LEAF_LIGHT },
  { at: [0.2, 1.64, 0.02], scale: [0.42, 0.33, 0.39], rotation: [-0.08, 0.4, -0.12], color: LEAF_MID },
  { at: [0.46, 1.53, 0.17], scale: [0.44, 0.34, 0.37], rotation: [0.08, -0.5, -0.04], color: LEAF_SUN },
  { at: [0.48, 1.49, -0.25], scale: [0.39, 0.29, 0.34], rotation: [-0.12, 0.5, 0.04], color: LEAF_DEEP },
  { at: [0.72, 1.56, -0.04], scale: [0.43, 0.3, 0.35], rotation: [0.04, -0.4, -0.1], color: LEAF_MID },
  { at: [0.83, 1.43, 0.13], scale: [0.32, 0.24, 0.29], rotation: [-0.08, 0.3, -0.12], color: LEAF_LIGHT },
];

const Y_AXIS = new THREE.Vector3(0, 1, 0);
const SCRATCH_FROM = new THREE.Vector3();
const SCRATCH_TO = new THREE.Vector3();
const SCRATCH_MID = new THREE.Vector3();
const SCRATCH_DIRECTION = new THREE.Vector3();
const SCRATCH_SCALE = new THREE.Vector3();
const SCRATCH_QUATERNION = new THREE.Quaternion();
const SCRATCH_MATRIX = new THREE.Matrix4();
const SCRATCH_EULER = new THREE.Euler();
const SCRATCH_COLOR = new THREE.Color();

function setSegmentMatrix(mesh: THREE.InstancedMesh, index: number, branch: BranchSegment) {
  SCRATCH_FROM.fromArray(branch.from);
  SCRATCH_TO.fromArray(branch.to);
  SCRATCH_DIRECTION.subVectors(SCRATCH_TO, SCRATCH_FROM);
  const length = SCRATCH_DIRECTION.length();
  SCRATCH_DIRECTION.multiplyScalar(1 / Math.max(length, 0.0001));
  SCRATCH_MID.copy(SCRATCH_FROM).add(SCRATCH_TO).multiplyScalar(0.5);
  SCRATCH_QUATERNION.setFromUnitVectors(Y_AXIS, SCRATCH_DIRECTION);
  SCRATCH_SCALE.set(branch.radius, length, branch.radius);
  SCRATCH_MATRIX.compose(SCRATCH_MID, SCRATCH_QUATERNION, SCRATCH_SCALE);
  mesh.setMatrixAt(index, SCRATCH_MATRIX);
  mesh.setColorAt(index, SCRATCH_COLOR.set(branch.shade));
}

function setCrownMatrix(mesh: THREE.InstancedMesh, index: number, cluster: CrownCluster) {
  SCRATCH_MID.fromArray(cluster.at).sub(CROWN_PIVOT);
  SCRATCH_EULER.set(...cluster.rotation);
  SCRATCH_QUATERNION.setFromEuler(SCRATCH_EULER);
  SCRATCH_SCALE.fromArray(cluster.scale);
  SCRATCH_MATRIX.compose(SCRATCH_MID, SCRATCH_QUATERNION, SCRATCH_SCALE);
  mesh.setMatrixAt(index, SCRATCH_MATRIX);
  mesh.setColorAt(index, SCRATCH_COLOR.set(cluster.color));
}

// 小葉の位置は固定値から決定的に生成する。再描画のたびに姿が変わらない。
const LEAVES = CROWN.flatMap((cluster, clusterIndex) =>
  [0, 1, 2].map((leafIndex) => {
    const phase = clusterIndex * 2.17 + leafIndex * 1.91;
    return {
      at: [
        cluster.at[0] + Math.cos(phase) * cluster.scale[0] * 0.83,
        cluster.at[1] + Math.sin(phase * 1.37) * cluster.scale[1] * 0.72,
        cluster.at[2] + Math.sin(phase) * cluster.scale[2] * 0.78,
      ] as [number, number, number],
      rotation: [phase * 0.23, phase + 0.4, Math.sin(phase) * 0.8] as [number, number, number],
      scale: [0.07 + (clusterIndex % 3) * 0.008, 0.13 + leafIndex * 0.012, 0.07] as [number, number, number],
      color: leafIndex === 0 ? LEAF_SUN : cluster.color,
    };
  }),
);

export default function WindsweptTree({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  animate = true,
  windStrength = 1,
}: WindsweptTreeProps) {
  const branches = useRef<THREE.InstancedMesh>(null);
  const crown = useRef<THREE.Group>(null);
  const crownClusters = useRef<THREE.InstancedMesh>(null);
  const leaves = useRef<THREE.InstancedMesh>(null);

  useLayoutEffect(() => {
    const branchMesh = branches.current;
    const crownMesh = crownClusters.current;
    const leafMesh = leaves.current;
    if (!branchMesh || !crownMesh || !leafMesh) return;

    BRANCHES.forEach((branch, index) => setSegmentMatrix(branchMesh, index, branch));
    branchMesh.instanceMatrix.needsUpdate = true;
    if (branchMesh.instanceColor) branchMesh.instanceColor.needsUpdate = true;
    branchMesh.computeBoundingSphere();

    CROWN.forEach((cluster, index) => setCrownMatrix(crownMesh, index, cluster));
    crownMesh.instanceMatrix.needsUpdate = true;
    if (crownMesh.instanceColor) crownMesh.instanceColor.needsUpdate = true;
    crownMesh.computeBoundingSphere();

    LEAVES.forEach((leaf, index) => {
      SCRATCH_MID.fromArray(leaf.at).sub(CROWN_PIVOT);
      SCRATCH_EULER.set(...leaf.rotation);
      SCRATCH_QUATERNION.setFromEuler(SCRATCH_EULER);
      SCRATCH_SCALE.fromArray(leaf.scale);
      SCRATCH_MATRIX.compose(SCRATCH_MID, SCRATCH_QUATERNION, SCRATCH_SCALE);
      leafMesh.setMatrixAt(index, SCRATCH_MATRIX);
      leafMesh.setColorAt(index, SCRATCH_COLOR.set(leaf.color));
    });
    leafMesh.instanceMatrix.needsUpdate = true;
    if (leafMesh.instanceColor) leafMesh.instanceColor.needsUpdate = true;
    leafMesh.computeBoundingSphere();
  }, []);

  useFrame(({ clock }) => {
    if (!animate || !crown.current) return;
    const time = clock.elapsedTime;
    // 長い周期の風に、短く弱い息を混ぜる。振り子のような等速往復を避ける。
    const wind =
      Math.sin(time * 0.54 + 0.8) * 0.65 +
      Math.sin(time * 1.31 + 2.2) * 0.24 +
      Math.sin(time * 2.73) * 0.06;
    crown.current.rotation.z = wind * 0.009 * windStrength;
    crown.current.rotation.x = Math.sin(time * 0.43 + 1.7) * 0.004 * windStrength;
    crown.current.position.x = wind * 0.006 * windStrength;
  });

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <instancedMesh
        ref={branches}
        args={[BRANCH_GEO, BRANCH_MAT, BRANCHES.length]}
        castShadow
        receiveShadow
      />

      {/* 古い枝が折れた節。近景で幹の時間を感じさせる小さな非対称。 */}
      <mesh
        geometry={KNOT_GEO}
        material={KNOT_MAT}
        position={[0.055, 0.58, 0.115]}
        scale={[0.075, 0.055, 0.025]}
        rotation={[0.2, 0.1, -0.35]}
        castShadow
      />

      <group ref={crown} position={CROWN_PIVOT.toArray()}>
        <instancedMesh
          ref={crownClusters}
          args={[CROWN_GEO, CROWN_MAT, CROWN.length]}
          castShadow
          receiveShadow
        />
        <instancedMesh ref={leaves} args={[LEAF_GEO, LEAF_MAT, LEAVES.length]} castShadow />
      </group>
    </group>
  );
}
