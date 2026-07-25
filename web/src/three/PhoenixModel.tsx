import { useEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";

// 航海士フェニックス(プレイヤーキャラクター)。
// 紋章を「体」ではなく「衣装のモチーフ」として着せた、小さな旅の航海士:
//  - 尖ったフード = 紋章の冠羽
//  - 燕尾のケープ = 紋章の翼と二叉の尾(背中に紋章のシルエットが宿る)
//  - 胸の留め具   = 紋章の丸い目穴(sandの環+midnightの芯)
//  - 手に提げるランタン = この世界の「今日の灯」
// フードの闇に sand の両目が灯る。体は体積で作り、どの角度でも成立する。
// 配色は世界と同じフラットだが、キャラクターだけは布も体もスムース
// シェーディング — 低ポリの世界(船・島)との対比で「生きもの」を際立たせる。
//
// 原点=接地点(足元 y=0)、前方=+X(船の舳先と同じ向き)。全高≈1.35。
//
// ゲーム内のサイズ目安:
//  - HarborWorld の船(scale 0.45)の甲板に立たせるなら scale 0.20〜0.24
//    (全高 0.27〜0.32 ≒ マストの半分弱。舳先寄り +0.6, デッキ上 y≈0.32)
//  - BoatStudio のような単体ステージなら scale 0.9〜1.1
// 首・両肩・ケープ・ランタンはピボットグループ — 将来の歩行・手振りにも使える。
// 360度ビューアは URL ハッシュ #phoenix(PhoenixViewer.tsx)。

const CORAL = "#F0997B"; // コート・ケープ・フード(紋章の主色)
const RUST = "#7A3B22"; // 深い錆(コートの裾陰・ランタンの枠)
const RUST_DEEP = "#4A1B0C"; // ブーツ・手袋
const SAND = "#EADEBD"; // 襟巻き・目・留め具の環
const MIDNIGHT = "#1A1130"; // フードの闇(顔)・留め具の芯
const LANTERN = "#F3C065"; // ランタンの灯(船のランタンと同色)

// ---- マント(布の格子メッシュ) ----
// 紋章の背景色(midnight)の一枚布。押し出し板ではなく、肩から垂れる
// パラメトリックな格子を毎フレーム波で変位させて「ひらひらと靡く」を作る。
// マントだけはスムースシェーディング(flatShading無し)で、ポリゴンの
// 角を見せない。裾は紋章の名残 — 左右の翼の先端が長く、中央が浅い燕尾。

const CAPE_ROWS = 16; // 縦(肩→裾)
const CAPE_COLS = 13; // 横(左端→右端)

/// マントの一点。u:-1..1(左→右)、v:0..1(肩→裾)。
/// out に位置を書き込む。time で裾ほど大きく波打ち、wind(1=待機)が強いほど
/// 速く大きく、裾が後方へ流される(歩行の向かい風)。
function capePoint(
  u: number,
  v: number,
  time: number,
  wind: number,
  out: { x: number; y: number; z: number },
) {
  const width = 0.16 + 0.21 * Math.pow(v, 1.15); // 裾へ向かって広がる
  const length = 0.38 + 0.19 * Math.pow(Math.abs(u), 1.4); // 端が長い=燕尾の裾
  const flutter = Math.pow(v, 1.5) * wind; // 肩は固定、裾ほど自由に
  const t = time * (0.7 + 0.3 * wind); // 風が強いほど波も速い
  out.x = u * width + flutter * Math.sin(t * 1.3 + v * 2.0) * 0.02;
  out.y = -v * length + flutter * Math.sin(u * 2.4 + t * 1.9) * 0.012;
  out.z =
    -0.02 -
    (0.24 + (wind - 1) * 0.09) * Math.pow(v, 1.1) + // 風で裾が後方へ流される
    flutter *
      (Math.sin(v * 5.2 - t * 2.1) * 0.05 + Math.sin(u * 2.6 + t * 1.5) * 0.04);
}

/// マントの格子ジオメトリ(位置は後で capeUpdate が書く)。
function buildCapeGeometry(): THREE.BufferGeometry {
  const geo = new THREE.BufferGeometry();
  const positions = new Float32Array(CAPE_ROWS * CAPE_COLS * 3);
  geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  const indices: number[] = [];
  for (let r = 0; r < CAPE_ROWS - 1; r++) {
    for (let c = 0; c < CAPE_COLS - 1; c++) {
      const a = r * CAPE_COLS + c;
      const b = a + 1;
      const d = a + CAPE_COLS;
      const e = d + 1;
      indices.push(a, d, b, b, d, e);
    }
  }
  geo.setIndex(indices);
  return geo;
}

const capeScratch = { x: 0, y: 0, z: 0 };

/// マントの全頂点を時刻 time・風 wind の波で書き直す(168頂点なので毎フレームでも軽い)。
function updateCape(geo: THREE.BufferGeometry, time: number, wind = 1) {
  const attr = geo.getAttribute("position") as THREE.BufferAttribute;
  let i = 0;
  for (let r = 0; r < CAPE_ROWS; r++) {
    const v = r / (CAPE_ROWS - 1);
    for (let c = 0; c < CAPE_COLS; c++) {
      const u = (c / (CAPE_COLS - 1)) * 2 - 1;
      capePoint(u, v, time, wind, capeScratch);
      attr.setXYZ(i++, capeScratch.x, capeScratch.y, capeScratch.z);
    }
  }
  attr.needsUpdate = true;
  geo.computeVertexNormals();
}

/// 肩マント(ショルダーケープ)。首から肩を包んで流れ落ちる短い外掛け。
/// フード→肩→コートの衣服の流れを一続きにして、腕の付け根の「図形感」を隠す。
function makeMantleGeometry(): THREE.BufferGeometry {
  const pts = [
    new THREE.Vector2(0.2, 0),
    new THREE.Vector2(0.185, 0.05),
    new THREE.Vector2(0.16, 0.11),
    new THREE.Vector2(0.125, 0.17),
    new THREE.Vector2(0.095, 0.21),
    new THREE.Vector2(0.078, 0.24),
  ];
  return new THREE.LatheGeometry(pts, 22);
}

/// コート。裾へ向かって広がる袍(ローブ)。低ポリのラースで体積を出す。
function makeCoatGeometry(): THREE.BufferGeometry {
  const pts = [
    new THREE.Vector2(0.235, 0.3),
    new THREE.Vector2(0.225, 0.36),
    new THREE.Vector2(0.205, 0.44),
    new THREE.Vector2(0.185, 0.52),
    new THREE.Vector2(0.165, 0.62),
    new THREE.Vector2(0.148, 0.7),
    new THREE.Vector2(0.135, 0.78),
    new THREE.Vector2(0.118, 0.86),
    new THREE.Vector2(0.105, 0.92),
  ];
  return new THREE.LatheGeometry(pts, 22);
}

// ジオメトリと材質は状態に依存しないので、モジュール読み込み時に一度だけ作る
// (マントだけは毎フレーム頂点を書くため、コンポーネント内で個別に作る)。
// キャラクターは布と同じくポリゴン感を出さない — セグメントを増やし、
// 材質はスムースシェーディング(世界の低ポリとの対比で「生きもの」感を作る)。
const COAT_GEO = makeCoatGeometry();
const MANTLE_GEO = makeMantleGeometry();
const HOOD_GEO = new THREE.ConeGeometry(0.125, 0.3, 18);
const FACE_GEO = new THREE.SphereGeometry(0.075, 14, 10);
const EYE_GEO = new THREE.SphereGeometry(0.015, 8, 6);
const SCARF_GEO = new THREE.TorusGeometry(0.105, 0.034, 9, 18);
const ARM_GEO = new THREE.CylinderGeometry(0.036, 0.044, 0.22, 12);
// 袖口: 手首へ向かって開くフレア。「棒」ではなく「袖」に見せる要。
const SLEEVE_CUFF_GEO = new THREE.CylinderGeometry(0.046, 0.064, 0.1, 12);
const HAND_GEO = new THREE.SphereGeometry(0.048, 12, 9);
// 足首はコートの裾内へ消え、ブーツのつま先だけが裾から前へ覗く。
const ANKLE_GEO = new THREE.CylinderGeometry(0.042, 0.048, 0.18, 12);
const BOOT_GEO = new THREE.SphereGeometry(0.075, 14, 10);
const BOOT_CUFF_GEO = new THREE.CylinderGeometry(0.062, 0.07, 0.06, 12);
const CLASP_RING_GEO = new THREE.TorusGeometry(0.036, 0.011, 8, 16);
const CLASP_PIN_GEO = new THREE.CylinderGeometry(0.019, 0.019, 0.02, 12);
// ランタンは開放型(上蓋+灯+底皿)。灯が枠に隠れず、どの角度からも見える。
// 六角のシルエットは職人の道具らしさとして残す(面の陰影は滑らかに)。
const LANTERN_CAP_GEO = new THREE.ConeGeometry(0.058, 0.05, 6);
const LANTERN_BASE_GEO = new THREE.CylinderGeometry(0.045, 0.05, 0.02, 6);
const LANTERN_GLOW_GEO = new THREE.SphereGeometry(0.042, 12, 9);
const LANTERN_HANDLE_GEO = new THREE.CylinderGeometry(0.008, 0.008, 0.06, 8);

const CORAL_MAT = new THREE.MeshStandardMaterial({
  color: CORAL,
  flatShading: false,
  roughness: 0.8,
});
const RUST_MAT = new THREE.MeshStandardMaterial({
  color: RUST,
  flatShading: false,
  roughness: 0.85,
});
const RUST_DEEP_MAT = new THREE.MeshStandardMaterial({
  color: RUST_DEEP,
  flatShading: false,
  roughness: 0.9,
});
const SAND_MAT = new THREE.MeshStandardMaterial({
  color: SAND,
  flatShading: false,
  roughness: 0.85,
});
const FACE_MAT = new THREE.MeshStandardMaterial({
  color: MIDNIGHT,
  flatShading: false,
  roughness: 0.6,
});
/// マント: 紋章の背景色。布だけはスムースシェーディング+両面描画で、
/// 角のないひらひらとした流れを見せる。
const CAPE_MAT = new THREE.MeshStandardMaterial({
  color: MIDNIGHT,
  flatShading: false,
  roughness: 0.9,
  side: THREE.DoubleSide,
});
/// フードの闇に灯る両目。夜でも読めるよう、ごく弱い自照を持たせる。
const EYE_MAT = new THREE.MeshStandardMaterial({
  color: SAND,
  flatShading: false,
  roughness: 0.7,
  emissive: new THREE.Color(SAND),
  emissiveIntensity: 0.55,
  fog: false,
});
/// ランタンの灯。船のランタンと同じ色・同じゆらぎ(同時に1体なので共有で良い)。
const LANTERN_GLOW_MAT = new THREE.MeshStandardMaterial({
  color: LANTERN,
  flatShading: false,
  roughness: 0.8,
  emissive: new THREE.Color(LANTERN),
  emissiveIntensity: 1.5,
  fog: false,
});

/// キャラクターのポーズ。ゲーム側から切り替えると、減衰補間でなめらかに遷移する。
///  - idle:     待機。呼吸と見渡し、ランタンの静かな振り子
///  - walk:     歩行(その場)。移動そのものはゲーム側が position を動かす
///  - raise:    灯を高く掲げる(記録の瞬間・お祝いに)
///  - hail:     手を振って挨拶(港の仲間へ)
///  - point:    空いた手で水平線の先を指す(目的地が見えた)
///  - stargaze: 灯を落として星を読む(進路を確かめる静かな夜)
///  - rest:     灯を両手で囲んで一息つく(休んだ日も、航海のうち)
export type PhoenixPose = "idle" | "walk" | "raise" | "hail" | "point" | "stargaze" | "rest";

/// ポーズごとの基本値(振りの中心)。振動はこの上に足す。
/// 全項目が減衰補間の対象なので、どのポーズからどのポーズへ切り替えても
/// 姿勢・首・呼吸・風・灯が同時に、跳ねずに移り変わる。
interface PoseBase {
  /// 肩からの腕の角(R=ランタンを提げる右腕、L=空いた左手)。
  /// x: 負ほど前へ振り上げる(-π/2 でほぼ水平) / z: 体から左右へ開く。
  armRx: number;
  armRz: number;
  armLx: number;
  armLz: number;
  /// 上体の前傾(正=前、負=のけぞる)。
  lean: number;
  /// マントに当たる風の強さ(1=待機)。
  wind: number;
  /// 首の上下(負=見上げる、正=うつむく)。
  headX: number;
  /// 首の見渡し。振幅(rad)と速さ(rad/s)。何かを見つめるポーズでは小さくする。
  scan: number;
  scanSpeed: number;
  /// 腕とランタンのゆらぎの強さ。止まって見せたいポーズほど小さく。
  sway: number;
  /// 呼吸の深さ(1=待機)と速さ(rad/s)。休むポーズほど深く、遅く。
  breathAmp: number;
  breathSpeed: number;
  /// ランタンの灯の明るさ(1.5=通常)。
  glow: number;
}

const POSE_BASE: Record<PhoenixPose, PoseBase> = {
  idle: {
    armRx: 0, armRz: 0.14, armLx: 0, armLz: -0.14,
    lean: 0, wind: 1, headX: 0, scan: 0.14, scanSpeed: 0.3,
    sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5,
  },
  walk: {
    armRx: 0, armRz: 0.12, armLx: 0, armLz: -0.12,
    lean: 0.09, wind: 1.7, headX: 0, scan: 0.05, scanSpeed: 0.3,
    sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5,
  },
  raise: {
    armRx: -2.35, armRz: 0.06, armLx: 0, armLz: -0.16,
    lean: -0.04, wind: 1.15, headX: -0.14, scan: 0.14, scanSpeed: 0.3,
    sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 2.3,
  },
  hail: {
    armRx: 0, armRz: 0.14, armLx: 0, armLz: -2.55,
    lean: 0, wind: 1.1, headX: 0, scan: 0.14, scanSpeed: 0.3,
    sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5,
  },
  // 陸を指す: 左手をほぼ水平に伸ばして舳先の先を指し、上体は前へ。
  // 首は振らない — 見つけたものから目を離さない姿が、この仕草の要。
  // 灯を提げた右腕は前傾の釣り合いでわずかに後ろへ流れる。
  point: {
    armRx: 0.1, armRz: 0.12, armLx: -1.66, armLz: 0.06,
    lean: 0.12, wind: 1.45, headX: -0.08, scan: 0.02, scanSpeed: 0.2,
    sway: 0.25, breathAmp: 0.8, breathSpeed: 0.9, glow: 1.6,
  },
  // 星を読む: 空を仰ぎ、左手を額にかざす。灯は後ろへ下げて暗く落とす
  // (手元が明るいと星は読めない)。首はゆっくり、星座をなぞる速さで巡る。
  stargaze: {
    armRx: 0.3, armRz: 0.2, armLx: -2.45, armLz: 0.1,
    lean: -0.1, wind: 0.8, headX: -0.46, scan: 0.2, scanSpeed: 0.16,
    sway: 0.5, breathAmp: 1.2, breathSpeed: 0.7, glow: 0.85,
  },
  // 一息つく: 両手を前で合わせて灯を囲み、うつむいてその光を見る。
  // 呼吸は深くゆっくり、風は凪。進んでいない日の姿にも灯は消えていない。
  rest: {
    armRx: -0.8, armRz: -0.3, armLx: -0.86, armLz: 0.32,
    lean: 0.07, wind: 0.75, headX: 0.32, scan: 0.05, scanSpeed: 0.22,
    sway: 0.6, breathAmp: 1.75, breathSpeed: 0.58, glow: 2,
  },
};

/// 小さな航海士。ローブの体積+燕尾のケープ+尖ったフード+提げたランタンで、
/// 「夜の海を渡ってきた旅の相棒」を2.5頭身に凝縮する。
export default function PhoenixModel({
  animate = true,
  pose = "idle",
}: {
  animate?: boolean;
  pose?: PhoenixPose;
}) {
  const core = useRef<THREE.Group>(null); // 足以外(呼吸・歩行の弾み)
  const head = useRef<THREE.Group>(null);
  const armR = useRef<THREE.Group>(null);
  const armL = useRef<THREE.Group>(null);
  const legR = useRef<THREE.Group>(null);
  const legL = useRef<THREE.Group>(null);
  const lantern = useRef<THREE.Group>(null);
  // ポーズの基本値の現在値(減衰補間でPOSE_BASEへ寄せていく)。
  const cur = useRef<PoseBase>({ ...POSE_BASE.idle });
  // 呼吸と見渡しは「速さ」もポーズごとに変わるので、時刻ではなく位相を積む
  // (速さが変わった瞬間に sin の位相が飛んで、動きが跳ねるのを防ぐ)。
  const phase = useRef({ breath: 0, scan: 0 });

  // マントの布。頂点を毎フレーム書くのでインスタンスごとに持ち、離れる時に破棄する。
  const capeGeo = useMemo(() => {
    const geo = buildCapeGeometry();
    updateCape(geo, 0); // 静止時(reduced-motion)もこの初期形で成立させる
    return geo;
  }, []);
  useEffect(() => () => capeGeo.dispose(), [capeGeo]);

  useFrame(({ clock }, delta) => {
    if (!animate) return;
    const time = clock.elapsedTime;
    const target = POSE_BASE[pose];
    const c = cur.current;
    // ポーズの基本値へなめらかに寄せる(切替の瞬間に跳ねない)。
    // 姿勢は速く、風と灯はゆっくり — 体が動いたあとから世界が追いつく。
    const to = (k: keyof PoseBase, lambda = 6) => {
      c[k] = THREE.MathUtils.damp(c[k], target[k], lambda, delta);
    };
    to("armRx");
    to("armRz");
    to("armLx");
    to("armLz");
    to("lean");
    to("headX");
    to("scan");
    to("scanSpeed");
    to("sway");
    to("breathAmp");
    to("breathSpeed");
    to("wind", 4);
    to("glow", 3);

    // 呼吸と見渡しの位相を、いまの速さで進める。
    const ph = phase.current;
    ph.breath += delta * c.breathSpeed;
    ph.scan += delta * c.scanSpeed;

    // マント: 布の波。歩行中は向かい風で強く靡く。
    updateCape(capeGeo, time, c.wind);

    const walking = pose === "walk";
    const stride = 5.4; // 歩調(rad/s)
    const step = Math.sin(time * stride);

    // 体: 待機は呼吸、歩行は歩調に合わせた弾み。
    if (core.current) {
      core.current.position.y = walking
        ? Math.abs(Math.cos(time * stride)) * 0.035
        : Math.sin(ph.breath) * 0.018 * c.breathAmp;
      core.current.rotation.x = c.lean + Math.sin(ph.breath + 0.9) * 0.01 * c.breathAmp;
      core.current.rotation.z = walking ? step * 0.03 : 0;
    }
    // 首: ポーズごとの上下と見渡し。何かを見つめるポーズでは振幅がほぼ0になり、
    // 「目を離さない」ことそのものが仕草の意味になる。
    if (head.current) {
      head.current.rotation.y = Math.sin(ph.scan) * c.scan;
      head.current.rotation.x = c.headX;
      head.current.rotation.z = Math.sin(ph.breath + 2.1) * 0.02 * c.breathAmp;
    }
    // 脚: 歩行は股関節から交互に振る。それ以外は接地に戻す。
    const legSwing = walking ? 0.55 : 0;
    if (legR.current) {
      legR.current.rotation.x = THREE.MathUtils.damp(
        legR.current.rotation.x,
        step * legSwing,
        10,
        delta,
      );
    }
    if (legL.current) {
      legL.current.rotation.x = THREE.MathUtils.damp(
        legL.current.rotation.x,
        -step * legSwing,
        10,
        delta,
      );
    }
    // 腕: 基本角+ポーズごとの振動。歩行は脚と逆位相で振り、挨拶は手を振る。
    // sway が小さいポーズ(指さし等)では、伸ばした腕がほとんど止まって見える。
    const armSwing = walking
      ? -step * 0.32
      : Math.sin(ph.breath + 0.4) * 0.03 * c.sway;
    if (armR.current) {
      armR.current.rotation.x = c.armRx + armSwing;
      armR.current.rotation.z = c.armRz;
    }
    if (armL.current) {
      const wave = pose === "hail" ? Math.sin(time * 7.2) * 0.3 : 0;
      armL.current.rotation.x =
        c.armLx + (walking ? step * 0.32 : Math.sin(ph.breath + 1.1) * 0.025 * c.sway);
      armL.current.rotation.z = c.armLz + wave;
    }
    // ランタン: 腕の傾きを打ち消して常にほぼ鉛直に垂れる振り子。
    if (lantern.current) {
      lantern.current.rotation.x =
        -(c.armRx + armSwing) + Math.sin(time * 0.9) * (walking ? 0.2 : 0.1 * c.sway);
      lantern.current.rotation.z = Math.sin(time * 0.7 + 0.6) * 0.12 * c.sway;
    }
    // 灯: ポーズごとの明るさ。掲げれば燃え、星を読むときは落とす。
    // ゆらぎは明るさに比例させる(暗く落とした灯がちらついて見えないように)。
    LANTERN_GLOW_MAT.emissiveIntensity = c.glow + Math.sin(time * 2.1) * 0.2 * c.glow;
  });

  return (
    // 形は正面=+Zで組み、グループごと+X向きへ(船の舳先と同じ向き)。
    <group rotation={[0, Math.PI / 2, 0]}>
      {/* 足。ピボットは裾に隠れた股関節の高さ — 歩行はここから交互に振る。
          足首は裾の内へ、丸いブーツのつま先が裾の前から覗く */}
      {[1, -1].map((s) => (
        <group
          key={s}
          ref={s === 1 ? legR : legL}
          position={[s * 0.088, 0.42, 0]}
        >
          <mesh geometry={ANKLE_GEO} material={RUST_DEEP_MAT} position={[0, -0.22, 0.02]} />
          <mesh geometry={BOOT_CUFF_GEO} material={RUST_MAT} position={[0, -0.305, 0.03]} />
          <mesh
            geometry={BOOT_GEO}
            material={RUST_DEEP_MAT}
            position={[0, -0.368, 0.09]}
            scale={[0.95, 0.68, 1.55]}
          />
        </group>
      ))}

      {/* 体(呼吸のまとまり) */}
      <group ref={core}>
        {/* コート: 裾へ広がる袍。裾の内側に深錆の縁で重さを出す */}
        <mesh geometry={COAT_GEO} material={CORAL_MAT} />
        <mesh geometry={COAT_GEO} material={RUST_MAT} position={[0, -0.02, 0]} scale={[0.97, 0.35, 0.97]} />
        {/* 肩マント: 首から肩へ流れ落ちる短い外掛け。腕はこの裾の下から出る */}
        <mesh geometry={MANTLE_GEO} material={CORAL_MAT} position={[0, 0.78, 0]} />
        {/* 留め具: 紋章の丸い目穴(sandの環+midnightの芯)。肩マントの前面に */}
        <group position={[0, 0.868, 0.178]} rotation={[-0.34, 0, 0]}>
          <mesh geometry={CLASP_RING_GEO} material={SAND_MAT} />
          <mesh geometry={CLASP_PIN_GEO} material={FACE_MAT} rotation={[Math.PI / 2, 0, 0]} />
        </group>

        {/* 襟巻き: sandの環+背に垂れる端 */}
        <mesh geometry={SCARF_GEO} material={SAND_MAT} position={[0, 0.96, 0]} rotation={[Math.PI / 2 + 0.08, 0, 0]} />

        {/* マント: 紋章の背景色の一枚布。肩に固定され、裾ほど自由に靡く
            (波は updateCape が毎フレーム頂点へ書く) */}
        <mesh geometry={capeGeo} material={CAPE_MAT} position={[0, 0.93, -0.04]} />

        {/* 頭(首振りのピボット): 頭サイズの尖ったフード=紋章の冠羽。
            開口部の闇に両目が灯る */}
        <group ref={head} position={[0, 0.98, 0]}>
          <mesh geometry={HOOD_GEO} material={CORAL_MAT} position={[0, 0.12, 0]} rotation={[-0.05, 0, 0]} />
          <mesh geometry={FACE_GEO} material={FACE_MAT} position={[0, 0.045, 0.062]} scale={[1, 1.1, 0.55]} />
          {[1, -1].map((s) => (
            <mesh
              key={s}
              geometry={EYE_GEO}
              material={EYE_MAT}
              position={[s * 0.028, 0.052, 0.099]}
            />
          ))}
        </group>

        {/* 左腕: 肩マントの裾の下から出る袖。手首でフレアし、手を添えて休める */}
        <group ref={armL} position={[-0.14, 0.8, 0.01]} rotation={[0, 0, -0.14]}>
          <mesh geometry={ARM_GEO} material={CORAL_MAT} position={[0, -0.1, 0]} />
          <mesh geometry={SLEEVE_CUFF_GEO} material={CORAL_MAT} position={[0, -0.22, 0]} />
          <mesh geometry={HAND_GEO} material={RUST_DEEP_MAT} position={[0, -0.28, 0]} />
        </group>

        {/* 右腕+ランタン: 「今日の灯」を提げる */}
        <group ref={armR} position={[0.14, 0.8, 0.01]} rotation={[0, 0, 0.14]}>
          <mesh geometry={ARM_GEO} material={CORAL_MAT} position={[0, -0.1, 0]} />
          <mesh geometry={SLEEVE_CUFF_GEO} material={CORAL_MAT} position={[0, -0.22, 0]} />
          <mesh geometry={HAND_GEO} material={RUST_DEEP_MAT} position={[0, -0.28, 0]} />
          <group ref={lantern} position={[0, -0.33, 0]}>
            <mesh geometry={LANTERN_HANDLE_GEO} material={RUST_MAT} position={[0, -0.03, 0]} />
            <mesh geometry={LANTERN_CAP_GEO} material={RUST_MAT} position={[0, -0.075, 0]} />
            <mesh geometry={LANTERN_GLOW_GEO} material={LANTERN_GLOW_MAT} position={[0, -0.14, 0]} />
            <mesh geometry={LANTERN_BASE_GEO} material={RUST_MAT} position={[0, -0.19, 0]} />
          </group>
        </group>
      </group>
    </group>
  );
}
