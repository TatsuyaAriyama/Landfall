// 最小限の i18n。iOS と同じく辞書キーで引く。
// 言語は設定(localStorage)→ブラウザ設定の順で決まる(ja 以外は英語)。

const ja = {
  appName: "Landfall",
  wordmark: "Landfall-StudyLog",
  signInEnter: "サインインして、入港しましょう。",
  signInSync: "記録は、複数の端末で同期されます。",
  signInWithGoogle: "Googleで続ける",
  today: "ホーム",
  trace: "軌跡",
  harbor: "港",
  signOut: "サインアウト",
  loading: "読み込み中…",
  items: "作業項目",
  addItem: "項目を追加",
  newItem: "新しい項目",
  editItem: "項目を編集",
  name: "名前",
  namePlaceholder: "名前(例: 読書、英語)",
  color: "配色",
  symbol: "シンボル",
  save: "保存する",
  cancel: "キャンセル",
  delete: "削除",
  deleteItem: "この項目を削除",
  deleteItemConfirm: "この項目と、その記録をすべて削除しますか。",
  duplicateItemName: "同じ名前の項目が、すでにあります。",
  record: "記録する",
  minutesLabel: "時間(分)",
  minutesUnit: "分",
  noteOptional: "ひとこと(任意)",
  todaysLog: "今日の記録",
  emptyToday: "最初の項目を作って、今日の一歩を刻もう。",
  emptyTiles: "ここに作業項目のタイルが並びます。",
  deleteSessionConfirm: "この記録を削除しますか。",
  studiedDays: "学んだ日",
  restedDays: "休んだ日",
  quitCount: "やめた回数",
  noDayRecords: "この日の記録はありません。休んだ日も、航海のうち。",
  tapDayHint: "日付を押すと、その日の記録が表示されます。",
  calendarTab: "カレンダー",
  indexTab: "索引",
  searchNotes: "ひとことを検索",
  noNotes: "ひとことは、まだありません。記録に一言添えると、ここに集まります。",
  dayNote: "この日の振り返り",
  dayNotePlaceholder: "この日の振り返り",
  signInFailed: "サインインに失敗しました。もう一度お試しください。",

  // プレイヤーカード
  sailor: "船乗り",
  playerCard: "プレイヤーカード",
  edit: "編集",
  playerName: "プレイヤー名",
  resolve: "決意",
  resolvePlaceholder: "座右の一文(任意)",
  saveCard: "このカードで保存",

  // 港
  publicSection: "パブリック",
  privateSection: "プライベート",
  inHarbor: "入港中",
  harborLanguage: "語学",
  harborCertification: "資格",
  harborStudent: "学生",
  harborReading: "読書",
  harborMaking: "制作",
  tagLanguage: "言葉を手に、世界へ飛び出そう。",
  tagCertification: "合格までの長い航海を、ひとりにしない。",
  tagStudent: "教室の外にも、学びは続いていく。",
  tagReading: "一冊が、知らない景色へ連れていく。",
  tagMaking: "つくるほど、世界が広がっていく。",
  joinHarbor: "この港に入る",
  joinDisclosure: "参加すると、名前・アイコン・作業記録がこの港に表示されます。",
  leaveHarbor: "この港を出る",
  leavePublicConfirm: "あなたの名前と共有した記録が、この港から消えます。いつでも戻れます。",
  sailors: "在港の船乗り",
  noSailors: "まだ誰もいません。最初の錨を下ろしませんか。",
  you: "あなた",
  report: "通報する",
  reportSailorTitle: "この船乗りを通報しますか。",
  reportMessageTitle: "この発言を通報しますか。",
  reportNote: "開発者に送られ、確認されます。",
  block: "ブロックする",
  blockTitle: "この船乗りをブロックしますか。",
  blockNote: "この人が見えなくなります。相手に通知はされません。",
  openHarbor: "港をひらく",
  joinByCode: "コードで入る",
  harborName: "港の名前",
  codePlaceholder: "コード(6文字)",
  create: "ひらく",
  join: "入る",
  inviteCode: "招待コード",
  copy: "コピー",
  copied: "コピーしました",
  leaveRoomConfirm: "この港から出ます。招待コードがあれば、いつでも戻れます。",
  chatTitle: "みんなの航海",
  chatEmpty: "記録はひとりでに流れ着きます。言葉は、添えたいときだけ。",
  chatPlaceholder: "港にひとこと(任意)",
  send: "送る",
  reactionLighthouse: "見てるよ。",
  reactionAnchor: "ゆっくり休んで。",
  reactionPhoenix: "おかえり。",
  errRoomFull: "この港は満員です(4人まで)。",
  errTooManyRooms: "入れる港は、3つまでです。",
  errAlreadyOwns: "ひらける港は、ひとつまで。あなたの港が、もう海のどこかにあります。",
  errRoomNotFound: "その港は見つかりませんでした。コードを確かめてください。",
  errGeneric: "うまくいきませんでした。もう一度お試しください。",
  back: "戻る",

  // みんなの海(港の3D)
  takePhoto: "写真を撮る",
  lanternHint: "今日走った船には、灯がともる。",

  // 共同航海(海図と航路)
  voyageTitle: "共同航海",
  voyageIntro:
    "目的地までの時間を決めると、海図がひらく。航路によって、待ち受けるものが変わる。",
  voyageTargetLabel: "目的地までの時間",
  voyageCustomHours: "自由入力",
  openChart: "海図をひらく",
  redrawChart: "海図を引き直す",
  routeCalm: "凪の航路",
  routeSquall: "嵐の航路",
  routeDeep: "深みの航路",
  routeCalmDesc: "静かな海が続く。波乱は少ない。",
  routeSquallDesc: "嵐の海域を抜けていく。",
  routeDeepDesc: "海獣の棲む深みの上を渡る。",
  routeLootMoonlight: "到着で「月光の帆」",
  routeLootKraken: "到着で「海獣の旗」",
  routeLootNone: "戦利品なし",
  encounterStorm: "嵐",
  encounterKraken: "海獣",
  setSail: "この航路で出航",
  setSailConfirm:
    "この航路で出航しますか。ここからの全員の記録が、船団を進めます。",
  stormCleared: "嵐は晴れた。",
  krakenCleared: "海獣は深みへ帰った。",
  voyageArrivedTitle: "島へ着いた。",
  voyageArrivedBadge: "到着",
  voyageNew: "次の航海",
  voyageNewConfirm: "済んだ航海を仕舞って、新しい海図をひらきますか。",
  lootMoonlightNotice: "戦利品 — 月光の帆が解放された。",
  lootKrakenNotice: "戦利品 — 海獣の旗が解放された。",
  lootToast: "航海の戦利品が解放された。船スタジオへ。",
  lootLock: "共同航海で解放",
  flagKraken: "海獣の旗",

  // フィードバック
  recordedToast: "記録しました。",
  joinedToast: "入港しました。",
  leftToast: "退港しました。",
  sentReport: "通報しました。",
  blockedToast: "ブロックしました。",
  savedToast: "保存しました。",
  offlineToast: "オフラインです。接続が戻ると反映されます。",
  onlineToast: "接続が戻りました。",
  setNameFirst: "先にプレイヤーカードを整えましょう。",
  moveEarlier: "前へ",
  moveLater: "後ろへ",

  // 目的地(島)
  destinations: "目的地",
  setDestinationPrompt: "目的地を設定しよう。",
  addDestination: "目的地を追加",
  destinationTitle: "目的地",
  islandName: "島の名前",
  islandNamePlaceholder: "例: TOEIC、読了、資格試験",
  goalKind: "目標",
  goalHours: "累計時間",
  goalDate: "期日",
  goalDone: "完了",
  goalDoneDesc: "時間や日数では測れないもの向け。終わったら、一覧のカードにあるチェックで完了にしよう。",
  optionalDateLabel: "締切(任意)",
  markDone: "完了にする",
  markDoneConfirm: "この目的地を完了にしますか。",
  hoursUnit: "時間",
  countsToward: "対象の項目",
  allItems: "すべての項目",
  landfallExcl: "着岸。",
  reachedIsland: "{name}に到達しました。",
  voyageStays: "この航海は、航海誌に残ります。",
  reachedIslands: "到達した島",
  deleteDestination: "この目的地を削除",
  deleteDestinationConfirm: "この目的地を削除しますか。作業の記録は消えません。",
  close: "閉じる",

  // タイマー
  startTimer: "計測をはじめる",
  startPomodoro: "ポモドーロ(25分+5分)",
  focusLabel: "集中",
  breakLabel: "休憩",
  soundOff: "音: オフ",
  soundWaves: "音: 波",
  soundPiano: "音: ピアノ",
  timerFinish: "終了",
  timerDiscardConfirm: "計測をやめますか。記録は残りません。",

  // 航海誌の追加
  monthCards: "月のカード",
  yearChart: "年間海図",
  saveImage: "画像で保存",

  // 船
  boatSection: "船",
  boatTab: "船",
  boatStudioTitle: "あなたの船",
  boatHint: "ドラッグで一周できます。",
  sailColor: "帆の色",
  jibLabel: "前帆",
  hullLabel: "船体",
  stripeLabel: "ライン",
  flagLabel: "旗",
  flagNone: "なし",
  flagPennant: "三角の旗",
  flagSwallow: "二又の旗",
  totalVoyage: "これまでの航海",

  // エクスポート
  dataSection: "データ",
  exportJSON: "JSONで書き出す",
  exportCSV: "CSVで書き出す",

  // 航海誌
  logbook: "航海誌",
  firstLogbook: "最初の航海誌は、月末に生まれる。",
  returnsLabel: "帰還",
  longestGapLabel: "いちばん長い空白",
  daysUnit: "日",
  timesUnit: "回",
  typePhoenix: "不死鳥型",
  typeStoneBridge: "石橋型",
  typeWaveRider: "波乗り型",
  typeComet: "彗星型",
  typeMorningCalm: "朝凪型",
  tagPhoenix: "深く沈んでも、また浮かび上がる。",
  tagStoneBridge: "静かに、確実に、積む。",
  tagWaveRider: "あなたには、あなたの潮がある。",
  tagComet: "燃えるときは、一気に。",
  tagMorningCalm: "騒がず、焦らず、途切れず。",
  subPhoenix: "空白がどれだけ長くても、また始められる。",
  subStoneBridge: "派手さはいらない。積んだものが残る。",
  subWaveRider: "引く日があるから、満ちる日がある。",
  subComet: "静けさは、次の助走にすぎない。",
  subMorningCalm: "その静けさが、いちばん強い。",

  // 設定
  settings: "設定",
  language: "言語",
  system: "システム",
  appearance: "外観",
  light: "ライト",
  dark: "ダーク",
  account: "アカウント",
  deleteAccount: "アカウント削除",
  deleteAccountConfirm: "アカウントと同期された記録が完全に削除されます。元に戻せません。",
  deleteFailed: "削除に失敗しました。サインインし直してから、もう一度お試しください。",
} as const;

export type I18nKey = keyof typeof ja;

const en: Record<I18nKey, string> = {
  appName: "Landfall",
  wordmark: "Landfall-StudyLog",
  signInEnter: "Sign in to enter the harbor.",
  signInSync: "Your record syncs across your devices.",
  signInWithGoogle: "Continue with Google",
  today: "Home",
  trace: "Trace",
  harbor: "Harbor",
  signOut: "Sign out",
  loading: "Loading…",
  items: "Items",
  addItem: "Add an item",
  newItem: "New item",
  editItem: "Edit item",
  name: "Name",
  namePlaceholder: "Name (e.g. Reading, Coding)",
  color: "Color",
  symbol: "Symbol",
  save: "Save",
  cancel: "Cancel",
  delete: "Delete",
  deleteItem: "Delete this item",
  deleteItemConfirm: "Delete this item and all of its records?",
  duplicateItemName: "An item with this name already exists.",
  record: "Record",
  minutesLabel: "Time (minutes)",
  minutesUnit: "min",
  noteOptional: "A note (optional)",
  todaysLog: "Today's log",
  emptyToday: "Create your first item and log a step today.",
  emptyTiles: "Your item tiles will live here.",
  deleteSessionConfirm: "Delete this record?",
  studiedDays: "Days studied",
  restedDays: "Days rested",
  quitCount: "Times quit",
  noDayRecords: "No records this day. Rest is part of the voyage.",
  tapDayHint: "Tap a day to see its records.",
  calendarTab: "Calendar",
  indexTab: "Index",
  searchNotes: "Search notes",
  noNotes: "No notes yet. Add a word to a record and it gathers here.",
  dayNote: "Reflections on this day",
  dayNotePlaceholder: "Reflections on this day",
  signInFailed: "Sign-in failed. Please try again.",

  sailor: "Sailor",
  playerCard: "Player card",
  edit: "Edit",
  playerName: "Player name",
  resolve: "Resolve",
  resolvePlaceholder: "One line you sail by (optional)",
  saveCard: "Save this card",

  publicSection: "Public",
  privateSection: "Private",
  inHarbor: "In harbor",
  harborLanguage: "Languages",
  harborCertification: "Certifications",
  harborStudent: "Students",
  harborReading: "Reading",
  harborMaking: "Making",
  tagLanguage: "Take these words, and step out into the world.",
  tagCertification: "A long voyage to the pass line, never alone.",
  tagStudent: "Learning keeps going, even outside the classroom.",
  tagReading: "One book can carry you somewhere new.",
  tagMaking: "Everything you make widens your world.",
  joinHarbor: "Join this harbor",
  joinDisclosure: "Joining shares your name, icon, and study records here.",
  leaveHarbor: "Leave this harbor",
  leavePublicConfirm:
    "Your name and shared records will be removed from this harbor. You can rejoin anytime.",
  sailors: "Sailors in harbor",
  noSailors: "No one is in this harbor yet. Be the first to drop anchor.",
  you: "You",
  report: "Report",
  reportSailorTitle: "Report this sailor?",
  reportMessageTitle: "Report this message?",
  reportNote: "This sends a report to the developer for review.",
  block: "Block",
  blockTitle: "Block this sailor?",
  blockNote: "You won't see them anymore. They won't be told.",
  openHarbor: "Open a harbor",
  joinByCode: "Enter with a code",
  harborName: "Harbor name",
  codePlaceholder: "Code (6 letters)",
  create: "Open",
  join: "Enter",
  inviteCode: "Invite code",
  copy: "Copy",
  copied: "Copied",
  leaveRoomConfirm: "You'll leave this harbor. With the code, you can return anytime.",
  chatTitle: "The voyage together",
  chatEmpty: "Records land here on their own. Words are optional.",
  chatPlaceholder: "A word to the harbor (optional)",
  send: "Send",
  reactionLighthouse: "I see you.",
  reactionAnchor: "Rest easy.",
  reactionPhoenix: "Welcome back.",
  errRoomFull: "This harbor is full (up to 4 sailors).",
  errTooManyRooms: "You can be in up to 3 harbors.",
  errAlreadyOwns: "You can open one harbor. Yours is already out there.",
  errRoomNotFound: "That harbor could not be found. Check the code.",
  errGeneric: "Something went wrong. Please try again.",
  back: "Back",

  takePhoto: "Take a photo",
  lanternHint: "Boats that sailed today carry a light.",

  voyageTitle: "Voyage together",
  voyageIntro:
    "Set the hours to your destination and a sea chart opens. What awaits depends on the route.",
  voyageTargetLabel: "Hours to destination",
  voyageCustomHours: "Custom",
  openChart: "Open the chart",
  redrawChart: "Redraw the chart",
  routeCalm: "Calm route",
  routeSquall: "Storm route",
  routeDeep: "Deep route",
  routeCalmDesc: "Quiet waters, few surprises.",
  routeSquallDesc: "Cuts through storm waters.",
  routeDeepDesc: "Crosses the deep where the kraken dwells.",
  routeLootMoonlight: "Arrival unlocks the Moonlight sail",
  routeLootKraken: "Arrival unlocks the Kraken flag",
  routeLootNone: "No spoils",
  encounterStorm: "Storm",
  encounterKraken: "Kraken",
  setSail: "Set sail on this route",
  setSailConfirm:
    "Set sail on this route? Everyone's records from here on carry the fleet forward.",
  stormCleared: "The storm has cleared.",
  krakenCleared: "The kraken returned to the deep.",
  voyageArrivedTitle: "You reached the island.",
  voyageArrivedBadge: "Arrived",
  voyageNew: "Next voyage",
  voyageNewConfirm: "Stow the finished voyage and open a new chart?",
  lootMoonlightNotice: "Spoils — the Moonlight sail is unlocked.",
  lootKrakenNotice: "Spoils — the Kraken flag is unlocked.",
  lootToast: "Voyage spoils unlocked. Visit your boat.",
  lootLock: "Unlocks on a voyage together",
  flagKraken: "Kraken flag",

  recordedToast: "Recorded.",
  joinedToast: "You're in the harbor.",
  leftToast: "You left the harbor.",
  sentReport: "Report sent.",
  blockedToast: "Blocked.",
  savedToast: "Saved.",
  offlineToast: "You're offline. Changes sync when you reconnect.",
  onlineToast: "Back online.",
  setNameFirst: "Set up your player card first.",
  moveEarlier: "Move up",
  moveLater: "Move down",

  destinations: "Destinations",
  setDestinationPrompt: "Set a destination.",
  addDestination: "Add a destination",
  destinationTitle: "Destination",
  islandName: "Island name",
  islandNamePlaceholder: "e.g. TOEIC, finish the book",
  goalKind: "Goal",
  goalHours: "Total hours",
  goalDate: "Target date",
  goalDone: "Done",
  goalDoneDesc:
    "For things hours or days can't measure. When it's done, mark it complete with the check on the card in the list.",
  optionalDateLabel: "Deadline (optional)",
  markDone: "Mark complete",
  markDoneConfirm: "Mark this destination complete?",
  hoursUnit: "hours",
  countsToward: "Counts toward",
  allItems: "All items",
  landfallExcl: "Landfall.",
  reachedIsland: "You reached {name}.",
  voyageStays: "This voyage stays in your Logbook.",
  reachedIslands: "Islands reached",
  deleteDestination: "Delete this destination",
  deleteDestinationConfirm: "Delete this destination? Your records stay.",
  close: "Close",

  startTimer: "Start the clock",
  startPomodoro: "Pomodoro (25 + 5 min)",
  focusLabel: "Focus",
  breakLabel: "Break",
  soundOff: "Sound: off",
  soundWaves: "Sound: waves",
  soundPiano: "Sound: piano",
  timerFinish: "Finish",
  timerDiscardConfirm: "Stop timing? Nothing will be recorded.",

  monthCards: "Monthly cards",
  yearChart: "Year chart",
  saveImage: "Save as image",

  boatSection: "Boat",
  boatTab: "Boat",
  boatStudioTitle: "Your boat",
  boatHint: "Drag to look around.",
  sailColor: "Sail color",
  jibLabel: "Jib",
  hullLabel: "Hull",
  stripeLabel: "Stripe",
  flagLabel: "Flag",
  flagNone: "None",
  flagPennant: "Pennant",
  flagSwallow: "Swallowtail",
  totalVoyage: "Voyage so far",

  dataSection: "Data",
  exportJSON: "Export as JSON",
  exportCSV: "Export as CSV",

  logbook: "Logbook",
  firstLogbook: "Your first Logbook arrives at month's end.",
  returnsLabel: "Returns",
  longestGapLabel: "Your longest gap",
  daysUnit: "days",
  timesUnit: "×",
  typePhoenix: "Phoenix",
  typeStoneBridge: "Stone Bridge",
  typeWaveRider: "Wave Rider",
  typeComet: "Comet",
  typeMorningCalm: "Morning Calm",
  tagPhoenix: "Sink for long, then rise again.",
  tagStoneBridge: "Quietly, surely, you build.",
  tagWaveRider: "You have your own tide.",
  tagComet: "When you burn, you burn all at once.",
  tagMorningCalm: "No noise, no rush, no break.",
  subPhoenix: "However long the gap, you begin again.",
  subStoneBridge: "No flourish needed. What you stack remains.",
  subWaveRider: "Some days ebb so others can flow.",
  subComet: "The stillness is only your next approach.",
  subMorningCalm: "That calm is your greatest strength.",

  settings: "Settings",
  language: "Language",
  system: "System",
  appearance: "Appearance",
  light: "Light",
  dark: "Dark",
  account: "Account",
  deleteAccount: "Delete account",
  deleteAccountConfirm:
    "This permanently deletes your account and synced record. This cannot be undone.",
  deleteFailed: "Deleting your account failed. Please sign in again and retry.",
} as const;

export const LANGUAGE_KEY = "appLanguage";

function resolveLang(): "ja" | "en" {
  const saved =
    typeof localStorage !== "undefined" ? localStorage.getItem(LANGUAGE_KEY) : null;
  if (saved === "ja" || saved === "en") return saved;
  return typeof navigator !== "undefined" && navigator.language.startsWith("ja")
    ? "ja"
    : "en";
}

export const lang: "ja" | "en" = resolveLang();

const dict = lang === "ja" ? ja : en;

export function t(key: I18nKey): string {
  return dict[key];
}

/// 書式付き文字列({name} 形式の穴埋め)。チャットの自動行などに使う。
export function tf(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k: string) => String(vars[k] ?? ""));
}

/// 年間海図のタイトルと、解放条件の表示。
export function yearChartTitle(year: number): string {
  return lang === "ja" ? `${year}年の海図` : `Chart of ${year}`;
}

export function unlockAtLabel(hours: number): string {
  return lang === "ja" ? `${hours}時間で解放` : `Unlocks at ${hours}h`;
}

/// 目的地の残り表示。「あと3時間20分」「あと12日」。
export function remainingHoursLabel(remainingMinutes: number): string {
  const h = Math.floor(remainingMinutes / 60);
  const m = remainingMinutes % 60;
  if (lang === "ja") return `あと${h > 0 ? `${h}時間` : ""}${m > 0 || h === 0 ? `${m}分` : ""}`;
  return `${h > 0 ? `${h}h ` : ""}${m}m to go`;
}

export function remainingDaysLabel(days: number): string {
  return lang === "ja" ? `あと${days}日` : `${days} days to go`;
}

/// チャットの発言時刻。「14:32」。
export function chatTimeLabel(date: Date): string {
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

/// 共同航海の残り表示。「あと◯時間」(1時間未満は分)。
export function voyageRemainingLabel(remainingMinutes: number): string {
  const m = Math.max(remainingMinutes, 0);
  if (m < 60) return lang === "ja" ? `あと${m}分` : `${m}m to go`;
  const h = Math.ceil(m / 60);
  return lang === "ja" ? `あと${h}時間` : `${h}h to go`;
}

/// 時間数の短い表示(海図のプリセットなど)。「20時間」/「20h」。
export function hoursShortLabel(hours: number): string {
  return lang === "ja" ? `${hours}時間` : `${hours}h`;
}

/// 復習の提案。意味が一読で分かる、責めない文にする。
export function reviewLine(name: string, gapDays: number): string {
  return lang === "ja"
    ? `${name}は${gapDays}日休んでいます。少し触れると、思い出しやすくなります。`
    : `${name} has rested for ${gapDays} days. A short visit makes it easier to remember.`;
}

/// チャットの自動行。iOS の書式と同じ文になるようにする。
export function chatLandfallLine(name: string, item: string, minutes: number): string {
  return lang === "ja"
    ? `${name}が着岸 — ${item}、${minutes}分`
    : `${name} made landfall — ${item}, ${minutes} min`;
}

export function chatReturnLine(name: string, gapDays: number): string {
  return lang === "ja"
    ? `${name}が帰還 — ${gapDays}日ぶりの航海。`
    : `${name} returned — first sail in ${gapDays} days.`;
}
