import type { BoatParts } from "./symbols";

// 船の編集は「帆色」だけ。6色すべてを初めから選べる。
// メインセイルと前帆は同色にし、船体・ライン・旗はAftideの標準船へ固定する。
export const SAIL_COLORS = [
  { id: "sand", color: "#EADEBD", labelKey: "sailSand" },
  { id: "coral", color: "#F0997B", labelKey: "sailCoral" },
  { id: "sunYellow", color: "#F3C065", labelKey: "sailSunlight" },
  { id: "seaGreen", color: "#5DCAA5", labelKey: "sailSeaGreen" },
  { id: "lavender", color: "#CECBF6", labelKey: "sailTwilight" },
  { id: "horizonBlue", color: "#7FA8B8", labelKey: "sailHorizon" },
] as const;

export type SailColorId = (typeof SAIL_COLORS)[number]["id"];

const SAIL_KEY = "boat.sail";
const DEFAULT_SAIL = SAIL_COLORS[0];

export function sailColorId(): SailColorId {
  const saved = localStorage.getItem(SAIL_KEY);
  return (SAIL_COLORS.find((option) => option.id === saved) ?? DEFAULT_SAIL).id;
}

export function setSailColor(id: SailColorId) {
  if (SAIL_COLORS.some((option) => option.id === id)) {
    localStorage.setItem(SAIL_KEY, id);
  }
}

function sailOption(id: string = sailColorId()) {
  return SAIL_COLORS.find((option) => option.id === id) ?? DEFAULT_SAIL;
}

// 旧共同航海データを読むための互換API。現在の航路は戦利品を持たず、
// 帆色の解放条件にも使わない。
export type LootKey = "loot.moonlightSail" | "loot.krakenFlag";

const LEGACY_LOOT_KEY = "loot.harborTrial";

export function hasLoot(key: LootKey): boolean {
  return (
    localStorage.getItem(key) === "1" || localStorage.getItem(LEGACY_LOOT_KEY) === "1"
  );
}

export function grantLoot(key: LootKey): boolean {
  if (hasLoot(key)) return false;
  localStorage.setItem(key, "1");
  return true;
}

// ---- 航海士の仕草 ----
// 装いタブで眺めている姿の記憶(船の色と同じくローカル保存)。次に開いたときに
// 続きから見られるようにするためのもので、甲板の航海士の姿は決めない
// (甲板は見張りなので待機+たまに見渡す。three/navigatorPose.ts)。

const POSE_KEY = "navigator.pose";
const POSES = [
  "idle",
  "walk",
  "lookout",
  "raise",
  "hail",
  "point",
  "stargaze",
  "rest",
  "sit",
] as const;
export type NavigatorPose = (typeof POSES)[number];

export function navigatorPose(): NavigatorPose {
  const saved = localStorage.getItem(POSE_KEY);
  return (POSES as readonly string[]).includes(saved ?? "")
    ? (saved as NavigatorPose)
    : "idle";
}

/// 航海士のフードの形。仕草と同じくこの端末に憶えておく
/// (見た目の好みなので、記録と一緒に同期はしない)。
const HOOD_KEY = "navigator.hood";
const HOODS = ["peak", "down"] as const;
export type NavigatorHood = (typeof HOODS)[number];

export function navigatorHood(): NavigatorHood {
  const saved = localStorage.getItem(HOOD_KEY);
  return (HOODS as readonly string[]).includes(saved ?? "")
    ? (saved as NavigatorHood)
    : "peak";
}

export function setNavigatorHood(hood: NavigatorHood) {
  localStorage.setItem(HOOD_KEY, hood);
}

export function setNavigatorPose(pose: NavigatorPose) {
  localStorage.setItem(POSE_KEY, pose);
}

/// いまの標準船。選択色はメインセイルと前帆の両方へ適用する。
export function boatProps(): BoatParts {
  const sail = sailOption().color;
  return {
    sail,
    jib: sail,
    hull: "#EADEBD",
    stripe: "none",
    flag: "none",
  };
}

// 港の既存スキーマとの互換性のため5フィールドは維持し、
// 廃止した部位には標準値を送る。
export function boatShareData(): Record<string, string> {
  const sail = sailColorId();
  return {
    boatSail: sail,
    boatJib: sail,
    boatHull: "sand",
    boatStripe: "none",
    boatFlag: "none",
  };
}

/// 港の旧データに個別部位が残っていても、帆色以外は標準船として表示する。
export function boatPartsFromIds(ids: {
  boatSail?: string;
  boatJib?: string;
  boatHull?: string;
  boatStripe?: string;
  boatFlag?: string;
}): BoatParts {
  const sail = sailOption(ids.boatSail).color;
  return {
    sail,
    jib: sail,
    hull: "#EADEBD",
    stripe: "none",
    flag: "none",
  };
}
