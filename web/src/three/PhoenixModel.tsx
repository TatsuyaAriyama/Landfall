import { useEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";
import { useGLTF } from "@react-three/drei";
import { navigatorHood } from "../boat";

// 航海士フェニックス(プレイヤーキャラクター)。
// 紋章を「体」ではなく「衣装のモチーフ」として着せた、小さな旅の航海士:
//  - 尖ったフード = 紋章の冠羽
//  - 燕尾のケープ = 紋章の翼と二叉の尾(背中に紋章のシルエットが宿る)
//  - 胸の留め具   = 紋章の丸い目穴(sandの環+midnightの芯)
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
// 首・両肩・ケープはピボットグループ — 将来の歩行・手振りにも使える。
// 360度ビューアは URL ハッシュ #phoenix(PhoenixViewer.tsx)。

const CORAL = "#F0997B"; // コート・ケープ・フード(紋章の主色)
const RUST = "#7A3B22"; // 深い錆(コートの裾陰)
const RUST_DEEP = "#4A1B0C"; // ブーツ・手袋
const SAND = "#EADEBD"; // 襟巻き・目・留め具の環
const MIDNIGHT = "#1A1130"; // フードの闇(顔)・留め具の芯

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
  const width = 0.17 + 0.25 * Math.pow(v, 1.1); // 裾へ向かって広がる
  // 端を長くして燕尾にするが、伸ばしすぎると布ではなく刃物に見える。
  // 指数を上げて「ごく端だけ少し長い」に留め、伸びる量も抑える。
  const length = 0.40 + 0.10 * Math.pow(Math.abs(u), 2.4);
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
  // 首元は高く伸ばさない。伸ばすと、この面がフードの開口より手前に来て
  // 顔の闇を下から隠し、目の上に細い黒帯が乗っただけの顔になる。
  // 上端は襟とフードの裾で隠れる高さで止める。
  const pts = [
    new THREE.Vector2(0.2, 0),
    new THREE.Vector2(0.185, 0.05),
    new THREE.Vector2(0.16, 0.11),
    new THREE.Vector2(0.128, 0.155),
    new THREE.Vector2(0.1, 0.175),
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
/// フード。円錐だと頭ではなく三角コーンに見えるので、頭を包む布として作る:
/// 肩の上で広く、頭のまわりで丸く張り、上へ行くほど細って柔らかい先になる。
///
/// profile は (半径, 高さ) の並び。lean は「上へ行くほど後ろへ倒す量」で、
/// これがゼロだとまっすぐ尖って作り物に見える。高さの二次で効かせるので、
/// 根元は動かず先だけが背中へ流れる。
function makeHood(profile: [number, number][], lean: number): THREE.BufferGeometry {
  const pts = profile.map(([r, y]) => new THREE.Vector2(r, y));
  // 前面を開けたまま回す。閉じた回転体だと顔が布に埋まってしまう。
  // ただし開けすぎると、闇そのものが「黒い頭」の形として見えてしまい、
  // 「フードの奥に目だけが灯る」にならない。
  // 低い円錐にしてからは頭のあたりの半径が小さく、同じ角度でも開口が
  // 相対的に広く見える(顔が横一文字の帯になる)。約41度まで絞る。
  const gap = 0.72;
  const geo = new THREE.LatheGeometry(pts, 20, gap / 2, Math.PI * 2 - gap);
  const pos = geo.attributes.position as THREE.BufferAttribute;
  const base = profile[0][1];
  const top = profile[profile.length - 1][1];
  const span = Math.max(0.001, top - base);
  for (let i = 0; i < pos.count; i += 1) {
    const k = Math.max(0, (pos.getY(i) - base) / span);
    pos.setZ(i, pos.getZ(i) - k * k * lean);
  }
  pos.needsUpdate = true;
  geo.computeVertexNormals();
  return geo;
}

/// 選べるフードの形。
/// peak = 被った頭巾。down = 肩へ下ろして畳んだ姿。
export const HOOD_SHAPES = ["peak", "down"] as const;
export type HoodShape = (typeof HOOD_SHAPES)[number];

const HOOD_GEOS: Record<"peak", THREE.BufferGeometry> = {
  // 頭巾: 肩からそのまま立ち上がる低い円錐。
  //
  // 以前は頭の上に高い尖り布を載せていたが、それだと体とは別の「帽子」に
  // 見えてしまう。裾を肩マントの高さまで下ろして幅を合わせ、コート→肩→頭巾が
  // 一本の稜線でつながるようにする。高さも半分ほどに詰めて、頭のぶんだけ
  // 盛り上がる小さな円錐にする。
  // 低いぶん倒す量も減らす(短い布を強く倒すと折れて見える)。
  peak: makeHood(
    [
      [0.148, -0.06],
      [0.14, 0.0],
      [0.126, 0.055],
      [0.104, 0.105],
      [0.07, 0.15],
      [0.0, 0.185],
    ],
    0.05,
  ),
};

// ---- フードを下ろした姿 ----
// 尖った布の塊をやめる。頭が出るとシルエットが人になり、円錐の子供っぽさが消える。
// 頭は夜色の一塊にして、その中で目だけが灯る(顔の造作は作らない — 作ると
// 低ポリの世界から浮くうえ、この航海士は「顔の見えない人」であることが持ち味)。

/// 頭。わずかに縦長の卵形。真球だと人形になる。
const HEAD_GEO = new THREE.SphereGeometry(0.099, 18, 14);

/// 背中に落ちた頭巾のかたまり。畳まれた布なので、丸くたわませる。
const FOLD_GEO = new THREE.SphereGeometry(0.115, 16, 12);

const FACE_GEO = new THREE.SphereGeometry(0.075, 14, 10);
const EYE_GEO = new THREE.SphereGeometry(0.016, 10, 8);
/// 立ち襟。以前は太いドーナツを首に一周させていたが、輪が一本通るだけで
/// 浮き輪のように見えて、いちばん野暮ったい部分になっていた。
/// 首に沿って低く立ち上げ、前は開けて顎の下を塞がない。
/// 色はコートと分けて夜色にする(頭と同じ色にすると、頭・首・顔が一続きの
/// 影になって、コーラルのコートが際立つ)。
/// 上へ向かって「すぼめる」のが要。広げるとフードの裾より外へ出て、
/// 頭の両脇に黒い角タブが立つ(実機で見て分かった)。
const COLLAR_GEO = (() => {
  const pts: THREE.Vector2[] = [
    [0.12, 0.0],
    [0.115, 0.028],
    [0.106, 0.055],
    [0.094, 0.078],
  ].map(([r, y]) => new THREE.Vector2(r, y));
  const gap = 1.05;
  return new THREE.LatheGeometry(pts, 22, gap / 2, Math.PI * 2 - gap);
})();

/// フードの合わせ目を留める撚り紐。船で使う綱と同じ撚りを入れる。
///
/// 素のトーラスだと「輪ゴム」に見えるので、大円まわりの角度と管まわりの角度を
/// 足した位相で管の太さを膨らませる。これで螺旋の稜が立ち、撚った綱になる。
function makeRopeRing(R: number, r: number, strands: number): THREE.BufferGeometry {
  const geo = new THREE.TorusGeometry(R, r, 6, 108);
  const pos = geo.attributes.position as THREE.BufferAttribute;
  const v = new THREE.Vector3();
  for (let i = 0; i < pos.count; i += 1) {
    v.fromBufferAttribute(pos, i);
    // トーラスは XY 平面。大円上の位置と、そこからの管のずれに分ける
    const a = Math.atan2(v.y, v.x);
    const cx = Math.cos(a) * R;
    const cy = Math.sin(a) * R;
    const ox = v.x - cx;
    const oy = v.y - cy;
    const radial = ox * Math.cos(a) + oy * Math.sin(a);
    const b = Math.atan2(v.z, radial);
    const k = 1 + 0.36 * Math.cos(strands * a - b);
    pos.setXYZ(i, cx + ox * k, cy + oy * k, v.z * k);
  }
  pos.needsUpdate = true;
  geo.computeVertexNormals();
  return geo;
}

const ROPE_RING_GEO = makeRopeRing(0.15, 0.0125, 15);
/// 正面の結び目。輪だけだと「どこで留めたか」が読めない。
const ROPE_KNOT_GEO = new THREE.SphereGeometry(0.022, 10, 8);
/// 結び目から垂れる端。先を細らせて綱の切り口に見せる。
const ROPE_TAIL_GEO = new THREE.CylinderGeometry(0.0115, 0.008, 0.072, 8);

const ARM_GEO = new THREE.CylinderGeometry(0.036, 0.044, 0.22, 12);
// 袖口: 手首へ向かって開くフレア。「棒」ではなく「袖」に見せる要。
const SLEEVE_CUFF_GEO = new THREE.CylinderGeometry(0.046, 0.064, 0.1, 12);
const HAND_GEO = new THREE.SphereGeometry(0.048, 12, 9);
// 足首はコートの裾内へ消え、ブーツのつま先だけが裾から前へ覗く。
const ANKLE_GEO = new THREE.CylinderGeometry(0.042, 0.048, 0.18, 12);
const BOOT_GEO = new THREE.SphereGeometry(0.075, 14, 10);
const BOOT_CUFF_GEO = new THREE.CylinderGeometry(0.062, 0.07, 0.06, 12);
/// 靴底。ブーツ本体が一番暗い色なので、底に一段明るい面を入れないと
/// 足が「暗い塊」になって、どこが床でどこが足か読み取れない。
const SOLE_GEO = new THREE.BoxGeometry(0.115, 0.026, 0.2);
/// かかと。底の後ろを一段落として、前後の向きを分かるようにする。
const HEEL_GEO = new THREE.BoxGeometry(0.1, 0.03, 0.055);
/// 腰のベルト。裾へ広がるだけの円錐に見えるのを、胴の位置を示して止める。
const BELT_GEO = new THREE.TorusGeometry(0.176, 0.021, 8, 22);
/// ベルトの留め具。正面に小さく置く。
const BUCKLE_GEO = new THREE.BoxGeometry(0.05, 0.038, 0.016);
/// 胸の羅針図。以前は「目」の紋章だったが、目的地へ向かうアプリの中心概念は
/// 羅針盤なので、八方位の星に置き換える。
/// 真鍮の環・夜色の盤・砂色の星の三層。環の内側に星が収まる寸法で組む
/// (はみ出すと環が「縁」ではなく「別の輪」に見える)。
const ROSE_RIM_GEO = new THREE.TorusGeometry(0.044, 0.0095, 8, 20);
const ROSE_FACE_GEO = new THREE.CylinderGeometry(0.038, 0.038, 0.007, 20);
/// 方位の針。四角錐を薄く潰して刃にする。長さは scale で四方位/間方位を分ける。
const ROSE_POINT_GEO = new THREE.ConeGeometry(0.0085, 0.032, 4);
const ROSE_HUB_GEO = new THREE.SphereGeometry(0.0075, 10, 8);
/// 八方位。偶数が四方位(長い)、奇数が間方位(短い)。
const ROSE_DIRS = [0, 1, 2, 3, 4, 5, 6, 7];
const CORAL_MAT = new THREE.MeshStandardMaterial({
  color: CORAL,
  flatShading: false,
  roughness: 0.8,
});
/// フードは前面を開けた一枚布なので、内側も見える。両面で描く。
const HOOD_MAT = new THREE.MeshStandardMaterial({
  color: CORAL,
  flatShading: false,
  roughness: 0.85,
  side: THREE.DoubleSide,
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
/// 撚り紐(綱)。麻の粗さを出すため、他の面より荒く反射を落とす。
const ROPE_MAT = new THREE.MeshStandardMaterial({
  color: SAND,
  flatShading: false,
  roughness: 0.95,
});
/// 立ち襟。前を開けた一枚なので内側も見える。
const COLLAR_MAT = new THREE.MeshStandardMaterial({
  color: MIDNIGHT,
  flatShading: false,
  roughness: 0.7,
  side: THREE.DoubleSide,
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
  emissiveIntensity: 0.85,
  fog: false,
});
/// キャラクターのポーズ。ゲーム側から切り替えると、減衰補間でなめらかに遷移する。
///  - idle:     待機。呼吸と見渡し
///  - walk:     歩行(その場)。移動そのものはゲーム側が position を動かす
///  - raise:    右手を高く掲げる(記録の瞬間・お祝いに)
///  - hail:     手を振って挨拶(港の仲間へ)
///  - point:    空いた手で水平線の先を指す(目的地が見えた)
///  - stargaze: 灯を落として星を読む(進路を確かめる静かな夜)
///  - rest:     灯を両手で囲んで一息つく(休んだ日も、航海のうち)
///  - lookout:  体ごと向きを変えて辺りを見渡す(見張り)
///  - sit:      甲板に腰を下ろす(休憩。立ち座りだけは遅く補間される)
export type PhoenixPose =
  | "idle"
  | "walk"
  | "lookout"
  | "raise"
  | "hail"
  | "point"
  | "stargaze"
  | "rest"
  | "sit"
  | "pickupRod"
  | "equipRod"
  | "holdRod"
  | "walkRod"
  | "stowRod";

/// ポーズごとの基本値(振りの中心)。振動はこの上に足す。
/// 全項目が減衰補間の対象なので、どのポーズからどのポーズへ切り替えても
/// 姿勢・首・呼吸・風・灯が同時に、跳ねずに移り変わる。
interface PoseBase {
  /// 肩からの腕の角(R=右腕、L=左腕)。
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
  /// 上体ごと左右へ向き直る振幅(rad)。首と同じ周期で、少し遅れて追う
  /// (首だけが動くのは「気配を窺う」、体まで回るのが「見渡す」)。
  turn: number;
  /// 腕のゆらぎの強さ。止まって見せたいポーズほど小さく。
  sway: number;
  /// 呼吸の深さ(1=待機)と速さ(rad/s)。休むポーズほど深く、遅く。
  breathAmp: number;
  breathSpeed: number;
  /// 旧ポーズデータとの互換値。見た目には使用しない。
  glow: number;
  /// 腰を下ろしている度合い(0=立つ、1=座る)。腰の高さと脚の角度を同時に動かす。
  sit: number;
}

// ---- 接地(当たり判定) ----
// このモデルの原点 y=0 は「床」そのもの — 甲板に立たせるときも y=0 が甲板の高さになる。
// ポーズによっては体のどこかが y=0 より下へ出てしまう(座る、など)。そこで毎フレーム、
// 実際に姿勢を当てたあとの体の当たり判定(AABB)を測り、床を割ったぶんだけ全体を
// 持ち上げる。数値の手調整で「これ以上下げない」と決めるより確実で、これから足す
// ポーズにも自動で効く。押し上げるだけで、決して下げない(歩行で足が浮くのは正しい)。
const CONTACT_BOX = new THREE.Box3();
const CONTACT_INV = new THREE.Matrix4();
/// 当たり判定を測り直す間隔(フレーム)。最下点はゆっくりしか変わらないので毎フレームは要らない。
const CONTACT_EVERY = 5;

// ---- 立ち座りの寸法 ----
/// 股関節の高さ(立っているとき)。JSXの脚グループの初期位置と同値。
const LEG_HIP_Y = 0.42;
/// 座ったときに股関節が落ちる量。裾が床に着くあたりが自然に見える。
/// 下げすぎても接地判定(上記)が押し戻すので、床にめり込むことはない。
const SIT_DROP = 0.3;
/// 座ったときに脚を前へ倒す角(rad)。水平まで倒すと下がった腰の高さのぶん
/// 脚が甲板から浮くので、少し手前で止めて爪先を甲板に着ける。
const SIT_SPREAD = 1.24;

const POSE_BASE: Record<PhoenixPose, PoseBase> = {
  idle: {
    armRx: 0, armRz: 0.14, armLx: 0, armLz: -0.14,
    lean: 0, wind: 1, headX: 0, scan: 0.14, scanSpeed: 0.3,
    turn: 0,
    sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5,
    sit: 0,
  },
  walk: {
    armRx: 0, armRz: 0.12, armLx: 0, armLz: -0.12,
    lean: 0.09, wind: 1.7, headX: 0, scan: 0.05, scanSpeed: 0.3,
    turn: 0,
    sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5,
    sit: 0,
  },
  // 見渡す: 上体ごと左右へ向き直り、左手を額にかざして水平線を追う。
  // 首だけ動かす待機と違い、体まで回る — しかも体は首より遅れて追う。
  // 星を読む(見上げて静止)とは、首の上下と体の回転で対になる。
  lookout: {
    armRx: 0.02, armRz: 0.16, armLx: -2.3, armLz: 0.14,
    lean: 0.02, wind: 1.2, headX: -0.02, scan: 0.46, scanSpeed: 0.55,
    turn: 0.4,
    sway: 0.7, breathAmp: 1, breathSpeed: 0.8, glow: 1.5,
    sit: 0,
  },
  raise: {
    armRx: -2.35, armRz: 0.06, armLx: 0, armLz: -0.16,
    lean: -0.04, wind: 1.15, headX: -0.14, scan: 0.14, scanSpeed: 0.3,
    turn: 0,
    sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 2.3,
    sit: 0,
  },
  hail: {
    armRx: 0, armRz: 0.14, armLx: 0, armLz: -2.55,
    lean: 0, wind: 1.1, headX: 0, scan: 0.14, scanSpeed: 0.3,
    turn: 0,
    sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5,
    sit: 0,
  },
  // 陸を指す: 左手をほぼ水平に伸ばして舳先の先を指し、上体は前へ。
  // 首は振らない — 見つけたものから目を離さない姿が、この仕草の要。
  // 灯を提げた右腕は前傾の釣り合いでわずかに後ろへ流れる。
  point: {
    armRx: 0.1, armRz: 0.12, armLx: -1.8, armLz: 0.06,
    lean: 0.14, wind: 1.45, headX: -0.08, scan: 0.02, scanSpeed: 0.2,
    turn: 0,
    sway: 0.25, breathAmp: 0.8, breathSpeed: 0.9, glow: 1.6,
    sit: 0,
  },
  // 星を読む: 空を仰ぎ、左手を額にかざす。灯は後ろへ下げて暗く落とす
  // (手元が明るいと星は読めない)。首はゆっくり、星座をなぞる速さで巡る。
  stargaze: {
    armRx: 0.3, armRz: 0.2, armLx: -2.58, armLz: 0.1,
    lean: -0.1, wind: 0.8, headX: -0.46, scan: 0.2, scanSpeed: 0.16,
    turn: 0,
    sway: 0.5, breathAmp: 1.2, breathSpeed: 0.7, glow: 0.85,
    sit: 0,
  },
  // 一息つく: 両手を前で合わせて灯を囲み、うつむいてその光を見る。
  // 呼吸は深くゆっくり、風は凪。進んでいない日の姿にも灯は消えていない。
  rest: {
    armRx: -0.8, armRz: -0.3, armLx: -0.86, armLz: 0.32,
    lean: 0.07, wind: 0.75, headX: 0.32, scan: 0.05, scanSpeed: 0.22,
    turn: 0,
    sway: 0.6, breathAmp: 1.75, breathSpeed: 0.58, glow: 2,
    sit: 0,
  },
  // 腰を下ろす: 甲板に座り、脚を前へ投げ出して、両手を後ろの床につく。
  // 腕は力を抜き、自然と傍らへ下がる。
  // 顔は水平線へ — 休んでいるのであって、うなだれているのではない。
  sit: {
    armRx: 0.62, armRz: 0.3, armLx: 0.62, armLz: -0.3,
    lean: -0.12, wind: 0.7, headX: -0.05, scan: 0.13, scanSpeed: 0.18,
    turn: 0,
    sway: 0.45, breathAmp: 1.6, breathSpeed: 0.6, glow: 1.8,
    sit: 1,
  },
  // 砂に置かれた道具へ目線から先に近づき、腰を折って左手を下ろす。
  pickupRod: {
    armRx: 0.2, armRz: 0.24, armLx: 0.42, armLz: -0.12,
    lean: 0.42, wind: 0.62, headX: 0.46, scan: 0.01, scanSpeed: 0.12,
    turn: 0,
    sway: 0.08, breathAmp: 0.65, breathSpeed: 0.66, glow: 1.05,
    sit: 0,
  },
  // 腰のバッグから道具を取り出す。視線→空いた左手→道具の順で動かす。
  equipRod: {
    armRx: 0.34, armRz: 0.36, armLx: -0.58, armLz: 0.34,
    lean: 0.08, wind: 0.82, headX: 0.3, scan: 0.02, scanSpeed: 0.18,
    turn: 0,
    sway: 0.18, breathAmp: 0.75, breathSpeed: 0.72, glow: 1.25,
    sit: 0,
  },
  // 釣竿を左手で支える待機姿勢。穂先が呼吸に合わせてわずかに揺れる。
  holdRod: {
    armRx: 0.04, armRz: 0.1, armLx: -1.12, armLz: -0.06,
    lean: 0.035, wind: 1.0, headX: -0.08, scan: 0.08, scanSpeed: 0.24,
    turn: 0,
    sway: 0.36, breathAmp: 0.9, breathSpeed: 0.78, glow: 1.45,
    sit: 0,
  },
  // 装備したまま歩く。竿を支える左腕は固定し、歩調は脚と右腕で見せる。
  walkRod: {
    armRx: 0, armRz: 0.12, armLx: -1.08, armLz: -0.05,
    lean: 0.095, wind: 1.7, headX: -0.02, scan: 0.04, scanSpeed: 0.24,
    turn: 0,
    sway: 0.2, breathAmp: 1, breathSpeed: 0.85, glow: 1.45,
    sit: 0,
  },
  // 釣竿をバッグへ戻す。装備時と同じ経路を逆に辿り、瞬間移動を避ける。
  stowRod: {
    armRx: 0.24, armRz: 0.3, armLx: -0.36, armLz: 0.42,
    lean: 0.1, wind: 0.78, headX: 0.34, scan: 0.02, scanSpeed: 0.18,
    turn: 0,
    sway: 0.12, breathAmp: 0.72, breathSpeed: 0.7, glow: 1.2,
    sit: 0,
  },
};

const FISHING_ROD_URL = "/models/fishing_rod.glb";

/// GLBの GripSocket を左手に合わせる。手首を返し、穂先は航海士の前上方へ向ける。
function HeldFishingRod() {
  const { scene } = useGLTF(FISHING_ROD_URL);
  const model = useMemo(() => scene.clone(true), [scene]);
  return (
    <group position={[0, -0.28, 0]} rotation={[1.95, 0, -0.08]}>
      <primitive object={model} />
    </group>
  );
}

useGLTF.preload(FISHING_ROD_URL);

/// 小さな航海士。ローブの体積+燕尾のケープ+尖ったフードで、
/// 「夜の海を渡ってきた旅の相棒」を2.5頭身に凝縮する。
export default function PhoenixModel({
  animate = true,
  pose = "idle",
  hood,
  fishingRod = false,
}: {
  animate?: boolean;
  pose?: PhoenixPose;
  /// フードの形。省略時はこの端末で選ばれているものを使う。
  hood?: HoodShape;
  /// 左手の GripSocket に釣竿を装着する。
  fishingRod?: boolean;
}) {
  // フードは指定が無ければ、この端末で選ばれている形を使う
  // (甲板・港・カードなど、呼び出し側が装いを知らない場所のため)。
  const shape: HoodShape = hood ?? navigatorHood();

  const core = useRef<THREE.Group>(null); // 足以外(呼吸・歩行の弾み)
  const head = useRef<THREE.Group>(null);
  const armR = useRef<THREE.Group>(null);
  const armL = useRef<THREE.Group>(null);
  const legR = useRef<THREE.Group>(null);
  const legL = useRef<THREE.Group>(null);
  // 接地判定用。root=モデルの座標系、contact=床に押し上げられる体ぜんたい。
  const root = useRef<THREE.Group>(null);
  // 座ったとき、床に広がる裾。
  const skirt = useRef<THREE.Group>(null);
  const contact = useRef<THREE.Group>(null);
  const lift = useRef(0);
  const tick = useRef(0);
  // ポーズの基本値の現在値(減衰補間でPOSE_BASEへ寄せていく)。
  const cur = useRef<PoseBase>({ ...POSE_BASE.idle });
  // 呼吸と見渡しは「速さ」もポーズごとに変わるので、時刻ではなく位相を積む
  // (速さが変わった瞬間に sin の位相が飛んで、動きが跳ねるのを防ぐ)。
  const phase = useRef({ breath: 0, scan: 0 });
  // 立ち座りだけは、他の持ち替えと同じ速さでは軽すぎる。腰を下ろすとき・
  // 立ち上がるときは体重が移るぶん時間がかかるので、その遷移のあいだだけ
  // 補間をゆっくりにする(座り終えても、次にポーズが変わるまでこの速さのまま)。
  const lastPose = useRef<PhoenixPose>(pose);
  const heavy = useRef(false);

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
    // 立ち座りをまたぐ持ち替えかどうかを、ポーズが変わった瞬間に決める。
    if (pose !== lastPose.current) {
      heavy.current = pose === "sit" || lastPose.current === "sit";
      lastPose.current = pose;
    }
    // ポーズの基本値へなめらかに寄せる(切替の瞬間に跳ねない)。
    // 姿勢は速く、風と灯はゆっくり — 体が動いたあとから世界が追いつく。
    // 立ち座りだけは 1/4 の速さ(落ち着くまで約2秒)。ゆっくり腰を下ろし、
    // ゆっくり立ち上がる。体重の移動は、持ち替えより時間がかかる。
    const settle = heavy.current ? 1.5 : 6;
    const to = (k: keyof PoseBase, lambda = settle) => {
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
    to("turn");
    to("sway");
    to("breathAmp");
    to("breathSpeed");
    to("sit");
    to("wind", settle * 0.66);
    to("glow", settle * 0.5);

    // 呼吸と見渡しの位相を、いまの速さで進める。
    const ph = phase.current;
    ph.breath += delta * c.breathSpeed;
    ph.scan += delta * c.scanSpeed;

    // マント: 布の波。歩行中は向かい風で強く靡く。
    updateCape(capeGeo, time, c.wind);

    const walking = pose === "walk" || pose === "walkRod";
    const stride = 5.4; // 歩調(rad/s)
    const step = Math.sin(time * stride);
    // 座ったときに股関節が落ちる量。脚を前へ倒したときブーツが甲板に触れる高さ。
    const drop = c.sit * SIT_DROP;

    // 体: 待機は呼吸、歩行は歩調に合わせた弾み。
    if (core.current) {
      core.current.position.y =
        (walking
          ? Math.abs(Math.cos(time * stride)) * 0.035
          : Math.sin(ph.breath) * 0.018 * c.breathAmp) - drop;
      core.current.rotation.x = c.lean + Math.sin(ph.breath + 0.9) * 0.01 * c.breathAmp;
      core.current.rotation.z = walking ? step * 0.03 : 0;
      // 見渡し: 上体ごと左右へ。首と同じ周期を少し遅れて追いかけることで、
      // 「首が先に向いて、体があとからついてくる」生きものの順序になる。
      core.current.rotation.y = Math.sin(ph.scan - 0.55) * c.turn;
    }
    // 首: ポーズごとの上下と見渡し。何かを見つめるポーズでは振幅がほぼ0になり、
    // 「目を離さない」ことそのものが仕草の意味になる。
    if (head.current) {
      head.current.rotation.y = Math.sin(ph.scan) * c.scan;
      head.current.rotation.x = c.headX;
      head.current.rotation.z = Math.sin(ph.breath + 2.1) * 0.02 * c.breathAmp;
    }
    // 脚: 歩行は股関節から交互に振る。座るときは股関節ごと下がり、脚は前へ倒れる
    // (一本の脚なので膝は折らない — 甲板に脚を投げ出して座る姿になる)。
    // それ以外は接地に戻す。
    const legSwing = walking ? 0.55 : 0;
    const legSit = -SIT_SPREAD * c.sit;
    for (const [leg, sign] of [
      [legR, 1],
      [legL, -1],
    ] as const) {
      if (!leg.current) continue;
      leg.current.position.y = LEG_HIP_Y - drop;
      leg.current.rotation.x = THREE.MathUtils.damp(
        leg.current.rotation.x,
        sign * step * legSwing + legSit,
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
        c.armLx +
        (pose === "walk"
          ? step * 0.32
          : Math.sin(ph.breath + 1.1) * 0.025 * c.sway);
      armL.current.rotation.z = c.armLz + wave;
    }
    // 裾: 座ると布は床に溜まって外へ広がる。コートは硬い円錐なので、そのままだと
    // 「立ったまま脚だけ前に出した人」に見えてしまう。腰の高さに合わせて裾を
    // 広げ、低くすると、はじめて座って見える(接地判定がこの形も含めて測る)。
    if (skirt.current) {
      skirt.current.scale.set(1 + 0.3 * c.sit, 1 - 0.22 * c.sit, 1 + 0.3 * c.sit);
    }

    // 接地: 姿勢を当てたあとの体を実際に測り、床(y=0)を割ったぶんだけ押し上げる。
    // 測るときだけ補正を外した素の姿に戻す(補正込みで測ると押し上げが積み上がる)。
    const body = contact.current;
    if (body && root.current) {
      if (tick.current++ % CONTACT_EVERY === 0) {
        const applied = body.position.y;
        body.position.y = 0;
        CONTACT_BOX.setFromObject(body);
        // ワールドで測った箱をモデルの座標系へ戻す(親は Y 回転と一様拡大だけなので
        // 上下の向きは保たれ、min.y がそのまま「床からの深さ」になる)。
        CONTACT_INV.copy(root.current.matrixWorld).invert();
        CONTACT_BOX.applyMatrix4(CONTACT_INV);
        lift.current = Math.max(0, -CONTACT_BOX.min.y);
        body.position.y = applied;
      }
      // 測り直しは間引くので、その間は補間でつなぐ(段になって見えないように)。
      body.position.y = THREE.MathUtils.damp(body.position.y, lift.current, 12, delta);
    }
  });

  return (
    // 形は正面=+Zで組み、グループごと+X向きへ(船の舳先と同じ向き)。
    <group ref={root} rotation={[0, Math.PI / 2, 0]}>
      {/* 体ぜんたい。床にめり込むポーズのとき、この群ごと押し上げられる
          (接地判定は useFrame の末尾)。 */}
      <group ref={contact}>
        {/* 足。ピボットは裾に隠れた股関節の高さ — 歩行はここから交互に振る。
            足首は裾の内へ、丸いブーツのつま先が裾の前から覗く */}
        {[1, -1].map((s) => (
          <group
            key={s}
            ref={s === 1 ? legR : legL}
            position={[s * 0.088, LEG_HIP_Y, 0]}
          >
            <mesh geometry={ANKLE_GEO} material={RUST_DEEP_MAT} position={[0, -0.22, 0.02]} />
            <mesh geometry={BOOT_CUFF_GEO} material={RUST_MAT} position={[0, -0.305, 0.03]} />
            <mesh
              geometry={BOOT_GEO}
              material={RUST_DEEP_MAT}
              position={[0, -0.368, 0.09]}
              scale={[0.95, 0.68, 1.55]}
            />
            {/* 靴底とかかと。一段明るい面で足の輪郭と前後の向きを出す */}
            <mesh geometry={SOLE_GEO} material={RUST_MAT} position={[0, -0.404, 0.088]} />
            <mesh geometry={HEEL_GEO} material={RUST_DEEP_MAT} position={[0, -0.418, 0.012]} />
          </group>
        ))}

        {/* 体(呼吸のまとまり) */}
        <group ref={core}>
          {/* 腰のベルト。これが無いとコートが「裾へ広がる円錐」にしか見えない */}
          <mesh
            geometry={BELT_GEO}
            material={RUST_DEEP_MAT}
            position={[0, 0.585, 0]}
            rotation={[Math.PI / 2, 0, 0]}
          />
          <mesh geometry={BUCKLE_GEO} material={SAND_MAT} position={[0, 0.585, 0.172]} />

          {/* コート: 裾へ広がる袍。裾の内側に深錆の縁で重さを出す */}
          <group ref={skirt}>
            <mesh geometry={COAT_GEO} material={CORAL_MAT} />
            <mesh geometry={COAT_GEO} material={RUST_MAT} position={[0, -0.02, 0]} scale={[0.97, 0.35, 0.97]} />
          </group>
          {/* 肩マント: 首から肩へ流れ落ちる短い外掛け。腕はこの裾の下から出る */}
          <mesh geometry={MANTLE_GEO} material={CORAL_MAT} position={[0, 0.78, 0]} />
          {/* 留め具: 紋章の丸い目穴(sandの環+midnightの芯)。肩マントの前面に */}
          <group position={[0, 0.868, 0.178]} rotation={[-0.34, 0, 0]}>
            <mesh geometry={ROSE_RIM_GEO} material={SAND_MAT} />
            <mesh geometry={ROSE_FACE_GEO} material={FACE_MAT} rotation={[Math.PI / 2, 0, 0]} />
            {ROSE_DIRS.map((k) => {
              const a = (k * Math.PI) / 4;
              const cardinal = k % 2 === 0;
              const len = cardinal ? 0.032 : 0.019;
              return (
                <mesh
                  key={k}
                  geometry={ROSE_POINT_GEO}
                  material={SAND_MAT}
                  position={[Math.cos(a) * (len / 2), Math.sin(a) * (len / 2), 0.006]}
                  rotation={[0, 0, a - Math.PI / 2]}
                  scale={[cardinal ? 1 : 0.66, len / 0.032, 0.28]}
                />
              );
            })}
            <mesh geometry={ROSE_HUB_GEO} material={SAND_MAT} position={[0, 0, 0.008]} />
          </group>

          {/* 襟巻き: sandの環+背に垂れる端 */}
          <mesh geometry={COLLAR_GEO} material={COLLAR_MAT} position={[0, 0.935, 0]} />

          {/* フードの合わせ目を留める撚り紐。頭と一緒に回らないよう体側に置く
              (綱は肩に留まっていて、首を振っても動かない) */}
          <group position={[0, 0.905, 0]}>
            <mesh
              geometry={ROPE_RING_GEO}
              material={ROPE_MAT}
              rotation={[Math.PI / 2, 0, 0]}
            />
            {/* 結び目は正面をわずかに外す。真正面だと胸の留め具と重なって
                隠れてしまうし、少し斜めのほうが結んだ手つきに見える */}
            <group rotation={[0, -0.62, 0]}>
            <group position={[0, -0.004, 0.147]}>
              <mesh geometry={ROPE_KNOT_GEO} material={ROPE_MAT} scale={[1.15, 0.85, 0.85]} />
              {[1, -1].map((s) => (
                <mesh
                  key={s}
                  geometry={ROPE_TAIL_GEO}
                  material={ROPE_MAT}
                  position={[s * 0.021, -0.038, 0.004]}
                  rotation={[0.14, 0, s * 0.32]}
                />
              ))}
            </group>
            </group>
          </group>
        {shape === "down" && (
          <>
            {/* 背中に落ちた頭巾。畳まれた布なので丸くたわませる。
                首まわりは立ち襟(COLLAR)が受け持つ。ここにコーラルの
                カウルを重ねると、開口の縁が肩の両脇にツノとして立つ。 */}
            <mesh
              geometry={FOLD_GEO}
              material={CORAL_MAT}
              position={[0, 0.9, -0.115]}
              scale={[1.05, 0.78, 0.72]}
            />
          </>
        )}

          {/* マント: 紋章の背景色の一枚布。肩に固定され、裾ほど自由に靡く
              (波は updateCape が毎フレーム頂点へ書く) */}
          <mesh geometry={capeGeo} material={CAPE_MAT} position={[0, 0.93, -0.04]} />

          {/* 頭(首振りのピボット): 頭サイズの尖ったフード=紋章の冠羽。
              開口部の闇に両目が灯る */}
          <group ref={head} position={[0, 0.98, 0]}>
            {shape === "peak" ? (
            <>
              <mesh
                geometry={HOOD_GEOS.peak}
                material={HOOD_MAT}
                position={[0, -0.02, 0]}
                rotation={[-0.03, 0, 0]}
              />
              {/* 顔の闇。フードの開口部に収まる大きさで、少しだけ前に出す */}
              <mesh
                geometry={FACE_GEO}
                material={FACE_MAT}
                position={[0, 0.03, 0.006]}
                scale={[0.98, 1.05, 0.9]}
              />
            </>
          ) : (
            /* 下ろした姿: 頭そのものを夜色の一塊として出す。
               顔の造作は作らない(目だけが灯る)。 */
            <mesh
              geometry={HEAD_GEO}
              material={FACE_MAT}
              position={[0, 0.115, 0.006]}
              scale={[1, 1.08, 0.97]}
            />
          )}
          {[1, -1].map((s) => (
              <mesh
                key={s}
                geometry={EYE_GEO}
                material={EYE_MAT}
                position={
                shape === "peak"
                  ? [s * 0.028, 0.022, 0.094]
                  : [s * 0.034, 0.124, 0.092]
              }
              />
            ))}
          </group>

          {/* 左腕: 肩マントの裾の下から出る袖。手首でフレアし、手を添えて休める */}
          <group ref={armL} position={[-0.163, 0.8, 0.035]} rotation={[0, 0, -0.14]}>
            <mesh geometry={ARM_GEO} material={CORAL_MAT} position={[0, -0.1, 0]} />
            <mesh geometry={SLEEVE_CUFF_GEO} material={RUST_MAT} position={[0, -0.22, 0]} />
            <mesh geometry={HAND_GEO} material={RUST_DEEP_MAT} position={[0, -0.28, 0]} />
            {fishingRod && <HeldFishingRod />}
          </group>

          {/* 右腕。旧ランタンは採用デザインに合わせて外した。 */}
          <group ref={armR} position={[0.163, 0.8, 0.035]} rotation={[0, 0, 0.14]}>
            <mesh geometry={ARM_GEO} material={CORAL_MAT} position={[0, -0.1, 0]} />
            <mesh geometry={SLEEVE_CUFF_GEO} material={RUST_MAT} position={[0, -0.22, 0]} />
            <mesh geometry={HAND_GEO} material={RUST_DEEP_MAT} position={[0, -0.28, 0]} />
          </group>
        </group>
      </group>
    </group>
  );
}
