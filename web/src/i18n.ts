// 最小限の i18n。iOS と同じく辞書キーで引く。
// 言語は設定(localStorage)→ブラウザ設定の順で決まる(ja 以外は英語)。

const ja = {
  appName: "Landfall",
  wordmark: "Landfall-StudyLog",
  signInEnter: "サインインして、入港しましょう。",
  signInSync: "記録は、複数の端末で同期されます。",
  signInWithGoogle: "Googleで続ける",
  signInWithApple: "Appleで続ける",
  signInNote: "アカウントは記録の同期にだけ使います。",
  signInWebviewWarning:
    "Instagram・LINEなどアプリ内のブラウザでは、Googleサインインができません。右上のメニューから「ブラウザで開く」を選んでください。",
  signInStorageBlocked:
    "この端末の設定(プライベートブラウズ等)でサインインがブロックされました。通常のブラウズモードでお試しください。",
  signInPopupBlocked:
    "ポップアップがブロックされました。ブラウザの設定でこのサイトのポップアップを許可して、もう一度お試しください。",
  today: "ホーム",
  trace: "軌跡",
  harbor: "港",
  signOut: "サインアウト",
  signOutConfirm: "サインアウトしますか。記録は同期済みなので消えません。",
  loading: "読み込み中…",
  loadFailed: "記録に繋がりませんでした。電波の届くところで、もう一度お試しください。",
  retry: "もう一度試す",
  render3dFailed: "この端末では3Dを表示できませんでした。少し時間をおいて開き直してください。",
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
  deleteItemConfirm: "この項目を削除しますか。過去の作業記録は航海の履歴として残ります。",
  duplicateItemName: "同じ名前の項目が、すでにあります。",
  record: "記録する",
  minutesLabel: "時間(分)",
  minutesUnit: "分",
  manualTimeTotal: "合計 {time}",
  manualTimeAddHint: "時間ボタンは、押すたびに加算されます。",
  undo: "ひとつ戻す",
  clear: "クリア",
  previousTime: "前回 {time}",
  noteOptional: "作業内容のメモ(任意)",
  todaysLog: "今日の記録",
  emptyToday: "最初の項目を作って、今日の一歩を刻もう。",
  emptyTiles: "ここに作業項目のタイルが並びます。",
  deleteSessionConfirm: "この記録を削除しますか。",
  studiedDays: "学んだ日",
  restedDays: "休んだ日",
  quitCount: "やめた回数",
  noDayRecords: "この日の記録はありません。休んだ日も、航海のうち。",
  // 今日はまだ終わっていないので「休んだ日」とは言わない。
  noRecordsToday: "今日の記録はまだありません。一日はこれから。",
  tapDayHint: "日付を押すと、その日の記録が表示されます。",
  calendarTab: "カレンダー",
  indexTab: "索引",
  todayJump: "今日",
  monthTotal: "合計",
  prevMonth: "前の月",
  nextMonth: "次の月",
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
  resolvePlaceholder: "決意を入力しよう",
  saveCard: "このカードで保存",
  sailingSince: "{date}から航海中",

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
  copyFailed: "コピーできませんでした。コードを長押しして選んでください。",
  leaveRoomConfirm: "この港から出ます。招待コードがあれば、いつでも戻れます。",
  chatTitle: "みんなの航海",
  chatEmpty: "記録はひとりでに流れ着きます。言葉は、添えたいときだけ。",
  chatPlaceholder: "港にひとこと(任意)",
  send: "送る",
  share: "共有",
  inviteNudge: "まだあなただけの港です。招待コードを送って、仲間を呼ぼう。",
  errRoomFull: "この港は満員です(4人まで)。",
  errTooManyRooms: "入れる港は、3つまでです。",
  errAlreadyOwns: "ひらける港は、ひとつまで。あなたの港が、もう海のどこかにあります。",
  errRoomNotFound: "その港は見つかりませんでした。コードを確かめてください。",
  errGeneric: "うまくいきませんでした。もう一度お試しください。",
  back: "戻る",

  // 帰る場所(港の3Dホームタウン)
  takePhoto: "写真を撮る",
  lanternHint: "今日、海へ出た船には灯がともる。",
  enterWorldHint: "港をタップして、帰る場所へ",
  harborWalkHint: "歩く：WASD・矢印　見る：ドラッグ",
  bag: "バッグ",
  bagEmpty: "バッグは空です。港を歩いて探してみよう。",
  fishingRod: "古びた釣竿",
  fishingRodDesc: "港の砂地で見つけた、よくしなる一本。",
  equip: "装備する",
  unequip: "装備を外す",
  equipped: "装備中",
  pickUpFishingRod: "釣竿を拾う",
  fishingRodFound: "古びた釣竿をバッグにしまった。",
  fishingRodEquipped: "釣竿を装備した。",
  fishingRodUnequipped: "釣竿をバッグに戻した。",
  emotes: "エモート",
  emoteWave: "手を振る",
  emoteLantern: "灯を掲げる",
  emotePoint: "指し示す",
  emoteLookout: "見渡す",
  harborLive: "港の仲間と同期中",
  harborWalkControls: "歩く",
  harborWalkForward: "前へ歩く",
  harborWalkLeft: "左へ歩く",
  harborWalkRight: "右へ歩く",
  harborWalkBack: "後ろへ歩く",
  harborBoardBoat: "船に乗る",
  harborLeaveBoat: "船を降りる",
  restInTent: "テントで休む",
  leaveTent: "テントの外へ出る",

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
  routeSquallDesc: "巨大なハリケーンの海域を渡る。",
  routeDeepDesc: "海獣の棲む深みの上を渡る。",
  routeLootMoonlight: "到着で「月光の帆」",
  routeLootKraken: "到着で「深海色の船体」",
  routeLootNone: "戦利品なし",
  encounterStorm: "ハリケーン",
  encounterKraken: "海獣",
  stormEventTitle: "嵐の航海",
  stormEventSub: "巨大なハリケーンが近づいてくる。",
  setSail: "この航路で出航",
  setSailConfirm:
    "この航路で出航しますか。ここからの全員の記録が、船団を進めます。",
  stormCleared: "嵐は過ぎ去った。",
  krakenCleared: "海獣は深みへ帰った。",
  voyageArrivedTitle: "島へ着いた。",
  voyageArrivedBadge: "到着",
  voyageNew: "次の航海",
  voyageNewConfirm: "済んだ航海を仕舞って、新しい海図をひらきますか。",
  lootMoonlightNotice: "戦利品 — 月光の帆が解放された。",
  lootKrakenNotice: "戦利品 — 深海色の船体が解放された。",
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
  goalQuestion: "この島へは、どう向かう?",
  goalDateOption: "期日を決める",
  goalStepsOption: "ステップで辿る",
  goalDateDesc: "決めた日に向かって、船が進む。時刻を決めなければ、その日いっぱいが締切。",
  goalTimeToggle: "時刻も決める",
  goalTime: "締切の時刻",
  goalTimeDesc: "この時刻に着岸する。",
  goalTimePast: "過ぎた時刻は選べない。先の時刻にしよう。",
  goalDatePast: "過ぎた日は選べない。今日より先にしよう。",
  goalKind: "目標",
  goalHours: "累計時間",
  goalDate: "期日",
  goalDone: "完了",
  goalDoneDesc: "時間や日数では測れないもの向け。終わったら、一覧のカードにあるチェックで完了にしよう。",
  goalSteps: "ステップ",
  goalStepsDesc: "大きな目標を、小さなステップに分けて辿る。ひとつ達成するごとに船が進み、全部で着岸。",
  landfallTime: "作業時間 {time}",
  addStep: "ステップを追加",
  stepPlaceholder: "例: 単語帳を1周",
  stepScheduledAt: "予定日時",
  stepCompletedAt: "達成日時",
  stepsCount: "{done} / {total}",
  nextStepLabel: "次: {name}",
  optionalDateLabel: "締切(任意)",
  markDone: "完了にする",
  markDoneConfirm: "この目的地を完了にしますか。",
  landNow: "上陸する",
  landReady: "島に着いた",
  landHere: "ここで上陸する",
  landHereConfirm: "まだ目的地に届いていない。ここで上陸して、この航海を終えますか。",
  hoursUnit: "時間",
  countsToward: "対象の項目",
  allItems: "すべての項目",
  landfallExcl: "着岸。",
  reachedIsland: "{name}に到着しました。",
  voyageStays: "この航海は、航海誌に残ります。",
  reachedIslands: "到達した島",
  deleteDestination: "この目的地を削除",
  deleteDestinationConfirm: "この目的地を削除しますか。作業の記録は消えません。",
  close: "閉じる",

  // タイマー
  focusLabel: "集中",
  breakLabel: "休憩",
  soundOff: "音: オフ",
  soundWaves: "音: 波",
  soundPiano: "音: クラシック",
  timerFinish: "終了",
  timerDiscardConfirm: "計測をやめますか。記録は残りません。",

  // 航海中(ストップウォッチの世界)
  voyagingNow: "航海中",
  pomodoroChip: "ポモドーロ 25分+5分",
  enterByHand: "作業時間を入力する",
  finishVoyage: "ここまでを記録する",
  discardVoyage: "航海をやめる",
  backToVoyage: "航海に戻る",
  lookAroundHint: "ドラッグで見渡せる。世界をタップすると、これだけになる。",
  takeBreak: "休憩する",
  endBreak: "航海に戻る",
  // 浮きピルは幅が狭いので短く。意味は上と同じ。
  takeBreakShort: "休憩",
  endBreakShort: "再開",
  // 休憩中は時計が止まる。止まっていることが伝わる言い方にする。
  restingNow: "錨を下ろしている",
  // 浮きピルは幅が厳しいので短く(長いと右端の✕がはみ出す)。
  restingShort: "休憩中",
  switchVoyageConfirm: "いまの航海をやめて、別の項目を始めますか。いまの記録は残りません。",

  // 航海誌の追加
  monthCards: "月のカード",
  voyageJournal: "航海日録",
  voyageJournalIntro: "その日、心に残ったことを記す場所。",
  voyageJournalPrompt: "今日の海は、どんな様子でしたか。",
  voyageJournalSave: "航海記を残す",
  voyageJournalSaved: "航海誌に記しました。",
  voyageJournalSaveFailed: "記せませんでした。もう一度お試しください。",
  voyageJournalEmpty: "航海記は、まだありません。",
  voyageJournalEmptyYear: "この年の航海記は、まだありません。",
  voyageJournalRecent: "これまでの航海記",
  deleteVoyageJournalConfirm: "この日の航海日録を削除しますか。",
  voyageJournalTime: "航海時間",
  yearChart: "年間海図",
  saveImage: "画像で保存",
  saveDaysCard: "「日々」を保存",
  saveVoyageCard: "「航海」を保存",
  saveTypeCard: "「タイプ」を保存",

  // 装い(船+航海士)
  boatSection: "船",
  boatTab: "装い",
  boatStudioTitle: "あなたの船",
  dressBoat: "船",
  dressSailor: "航海士",
  sailorTitle: "あなたの航海士",
  hoodLabel: "フード",
  hoodPeak: "頭巾",
  hoodDown: "肩に下ろす",
  poseLabel: "仕草",
  poseIdle: "待機",
  poseWalk: "歩く",
  poseLookout: "見渡す",
  poseRaise: "掲げる",
  poseHail: "手を振る",
  posePoint: "陸を指す",
  poseStargaze: "星を読む",
  poseRest: "一息つく",
  poseSit: "腰を下ろす",
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
  exportVoyageLogsCSV: "航海日録をCSVで書き出す",

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
  signInWithApple: "Continue with Apple",
  signInNote: "Your account is only used to sync your record.",
  signInWebviewWarning:
    "Google sign-in doesn't work inside Instagram, LINE, or similar in-app browsers. Please open this page in Safari or Chrome from the menu.",
  signInStorageBlocked:
    "Sign-in was blocked by this browser's settings (e.g. private browsing). Please try again in normal browsing mode.",
  signInPopupBlocked:
    "The sign-in popup was blocked. Please allow popups for this site in your browser settings and try again.",
  today: "Home",
  trace: "Trace",
  harbor: "Harbor",
  signOut: "Sign out",
  signOutConfirm: "Sign out? Your records are synced and will not be lost.",
  loading: "Loading…",
  loadFailed: "Couldn't reach your records. Check your connection and try again.",
  retry: "Try again",
  render3dFailed: "Couldn't draw the 3D view on this device. Try reopening in a moment.",
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
  deleteItemConfirm: "Delete this item? Its past work records will remain in your history.",
  duplicateItemName: "An item with this name already exists.",
  record: "Record",
  minutesLabel: "Time (minutes)",
  minutesUnit: "min",
  manualTimeTotal: "Total {time}",
  manualTimeAddHint: "Time buttons add to the total each time you press them.",
  undo: "Undo",
  clear: "Clear",
  previousTime: "Last: {time}",
  noteOptional: "What you worked on (optional)",
  todaysLog: "Today's log",
  emptyToday: "Create your first item and log a step today.",
  emptyTiles: "Your item tiles will live here.",
  deleteSessionConfirm: "Delete this record?",
  studiedDays: "Days studied",
  restedDays: "Days rested",
  quitCount: "Times quit",
  noDayRecords: "No records this day. Rest is part of the voyage.",
  noRecordsToday: "No records yet today. The day is still ahead.",
  tapDayHint: "Tap a day to see its records.",
  calendarTab: "Calendar",
  todayJump: "Today",
  monthTotal: "Total",
  prevMonth: "Previous month",
  nextMonth: "Next month",
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
  resolvePlaceholder: "Write your resolve",
  saveCard: "Save this card",
  sailingSince: "Sailing since {date}",

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
  copyFailed: "Couldn't copy. Long-press the code to select it.",
  leaveRoomConfirm: "You'll leave this harbor. With the code, you can return anytime.",
  chatTitle: "The voyage together",
  chatEmpty: "Records land here on their own. Words are optional.",
  chatPlaceholder: "A word to the harbor (optional)",
  send: "Send",
  share: "Share",
  inviteNudge: "This harbor is just you so far. Send the invite code to bring friends aboard.",
  errRoomFull: "This harbor is full (up to 4 sailors).",
  errTooManyRooms: "You can be in up to 3 harbors.",
  errAlreadyOwns: "You can open one harbor. Yours is already out there.",
  errRoomNotFound: "That harbor could not be found. Check the code.",
  errGeneric: "Something went wrong. Please try again.",
  back: "Back",

  takePhoto: "Take a photo",
  lanternHint: "Boats that sailed today carry a light.",
  enterWorldHint: "Tap the harbor to return home",
  harborWalkHint: "Walk: WASD or arrows · Look: drag",
  bag: "Bag",
  bagEmpty: "Your bag is empty. Explore the harbor to find something.",
  fishingRod: "Weathered fishing rod",
  fishingRodDesc: "A flexible old rod found on the harbor sand.",
  equip: "Equip",
  unequip: "Unequip",
  equipped: "Equipped",
  pickUpFishingRod: "Pick up the fishing rod",
  fishingRodFound: "You put the weathered fishing rod in your bag.",
  fishingRodEquipped: "Fishing rod equipped.",
  fishingRodUnequipped: "Fishing rod returned to your bag.",
  emotes: "Emotes",
  emoteWave: "Wave",
  emoteLantern: "Raise light",
  emotePoint: "Point",
  emoteLookout: "Look around",
  harborLive: "Live with harbor friends",
  harborWalkControls: "Walk",
  harborWalkForward: "Walk forward",
  harborWalkLeft: "Walk left",
  harborWalkRight: "Walk right",
  harborWalkBack: "Walk back",
  harborBoardBoat: "Board your boat",
  harborLeaveBoat: "Step ashore",
  restInTent: "Rest in the tent",
  leaveTent: "Step outside",

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
  routeSquallDesc: "Crosses the waters of a giant hurricane.",
  routeDeepDesc: "Crosses the deep where the kraken dwells.",
  routeLootMoonlight: "Arrival unlocks the Moonlight sail",
  routeLootKraken: "Arrival unlocks the abyss hull",
  routeLootNone: "No spoils",
  encounterStorm: "Hurricane",
  encounterKraken: "Kraken",
  stormEventTitle: "The Storm Voyage",
  stormEventSub: "A giant hurricane is closing in.",
  setSail: "Set sail on this route",
  setSailConfirm:
    "Set sail on this route? Everyone's records from here on carry the fleet forward.",
  stormCleared: "The hurricane has passed.",
  krakenCleared: "The kraken returned to the deep.",
  voyageArrivedTitle: "You reached the island.",
  voyageArrivedBadge: "Arrived",
  voyageNew: "Next voyage",
  voyageNewConfirm: "Stow the finished voyage and open a new chart?",
  lootMoonlightNotice: "Spoils — the Moonlight sail is unlocked.",
  lootKrakenNotice: "Spoils — the abyss hull is unlocked.",
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
  goalQuestion: "How will you reach this island?",
  goalDateOption: "Set a date",
  goalStepsOption: "Follow steps",
  goalDateDesc:
    "The boat drifts toward the island as the day draws near. Without a time, the whole day counts.",
  goalTimeToggle: "Set a time too",
  goalTime: "Deadline time",
  goalTimeDesc: "You'll make landfall at this time.",
  goalTimePast: "That time has passed. Pick a later one.",
  goalDatePast: "That day has passed. Pick today or later.",
  goalKind: "Goal",
  goalHours: "Total hours",
  goalDate: "Target date",
  goalDone: "Done",
  goalDoneDesc:
    "For things hours or days can't measure. When it's done, mark it complete with the check on the card in the list.",
  goalSteps: "Steps",
  goalStepsDesc:
    "Break a big goal into small steps. Each one you finish moves the boat forward; finish them all to make landfall.",
  landfallTime: "Work time {time}",
  addStep: "Add a step",
  stepPlaceholder: "e.g. one pass of the vocab book",
  stepScheduledAt: "Scheduled for",
  stepCompletedAt: "Completed at",
  stepsCount: "{done} / {total}",
  nextStepLabel: "Next: {name}",
  optionalDateLabel: "Deadline (optional)",
  markDone: "Mark complete",
  markDoneConfirm: "Mark this destination complete?",
  landNow: "Go ashore",
  landReady: "You've arrived",
  landHere: "Go ashore here",
  landHereConfirm: "You haven't reached the destination yet. Go ashore here and end this voyage?",
  hoursUnit: "hours",
  countsToward: "Counts toward",
  allItems: "All items",
  landfallExcl: "Landfall.",
  reachedIsland: "Arrived at {name}.",
  voyageStays: "This voyage stays in your Logbook.",
  reachedIslands: "Islands reached",
  deleteDestination: "Delete this destination",
  deleteDestinationConfirm: "Delete this destination? Your records stay.",
  close: "Close",

  focusLabel: "Focus",
  breakLabel: "Break",
  soundOff: "Sound: off",
  soundWaves: "Sound: waves",
  soundPiano: "Sound: classical",
  timerFinish: "Finish",
  timerDiscardConfirm: "Stop timing? Nothing will be recorded.",

  // 航海中(ストップウォッチの世界)
  voyagingNow: "Under way",
  pomodoroChip: "Pomodoro 25 + 5 min",
  enterByHand: "Enter the time instead",
  finishVoyage: "Log this far",
  discardVoyage: "Abandon the voyage",
  backToVoyage: "Back to the voyage",
  lookAroundHint: "Drag to look around. Tap the world to see only it.",
  takeBreak: "Take a break",
  endBreak: "Back to the voyage",
  takeBreakShort: "Break",
  endBreakShort: "Resume",
  restingNow: "At anchor",
  restingShort: "Resting",
  switchVoyageConfirm:
    "Abandon this voyage and start another item? Nothing will be recorded.",

  monthCards: "Monthly cards",
  voyageJournal: "Daily Log",
  voyageJournalIntro: "A place to record what stayed with you that day.",
  voyageJournalPrompt: "What were the waters like today?",
  voyageJournalSave: "Add to the logbook",
  voyageJournalSaved: "Added to your Logbook.",
  voyageJournalSaveFailed: "Could not save. Please try again.",
  voyageJournalEmpty: "No daily entries yet.",
  voyageJournalEmptyYear: "No daily entries in this year.",
  voyageJournalRecent: "Earlier entries",
  deleteVoyageJournalConfirm: "Delete this day's voyage log?",
  voyageJournalTime: "Time underway",
  yearChart: "Year chart",
  saveImage: "Save as image",
  saveDaysCard: "Save “Days”",
  saveVoyageCard: "Save “Voyage”",
  saveTypeCard: "Save “Type”",

  boatSection: "Boat",
  boatTab: "Style",
  boatStudioTitle: "Your boat",
  dressBoat: "Boat",
  dressSailor: "Navigator",
  sailorTitle: "Your navigator",
  hoodLabel: "Hood",
  hoodPeak: "Peaked",
  hoodDown: "Down",
  poseLabel: "Pose",
  poseIdle: "Idle",
  poseWalk: "Walk",
  poseLookout: "Look out",
  poseRaise: "Raise",
  poseHail: "Wave",
  posePoint: "Sight land",
  poseStargaze: "Stargaze",
  poseRest: "Rest",
  poseSit: "Sit",
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
  exportVoyageLogsCSV: "Export Daily Logs as CSV",

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

/// 期日までの残り。1日以上あれば日で、切ったら時間・分で言う
/// (時刻まで決められるので、締切当日は「あと3時間」と出したい)。
export function deadlineRemainingLabel(remainingMs: number): string {
  const minutes = Math.max(0, Math.ceil(remainingMs / 60000));
  if (minutes >= 1440) return remainingDaysLabel(Math.round(minutes / 1440));
  // 1時間を超えたら分を捨てていた(90分残りが「あと1時間」に見えていた)。
  // 時間の表記はアプリ全体で durationLabel に揃える。
  if (lang === "ja") return `あと${durationLabel(minutes)}`;
  return `${durationLabel(minutes)} to go`;
}

/// チャットの発言時刻。「14:32」。
export function chatTimeLabel(date: Date): string {
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

/// チャットの日付区切り。「7月21日(火)」。年が違えば年も付ける。
export function chatDateLabel(date: Date, now: Date = new Date()): string {
  const sameYear = date.getFullYear() === now.getFullYear();
  return new Intl.DateTimeFormat(lang, {
    ...(sameYear ? {} : { year: "numeric" }),
    month: "long",
    day: "numeric",
    weekday: "short",
  }).format(date);
}

/// 短い日付。「7月25日」/ "Jul 25"。ステップを達成した日の記録に使う
/// (iOS の LF.dayMonth と同じ書式)。
export function shortDateLabel(date: Date): string {
  return new Intl.DateTimeFormat(lang, { month: lang === "ja" ? "long" : "short", day: "numeric" })
    .format(date);
}

/// 年まで入れた日付。「2026年7月25日」/ "Jul 25, 2026"。
/// いつから使っているかのように、年が要る場面で使う。
export function fullDateLabel(date: Date): string {
  return new Intl.DateTimeFormat(lang, {
    year: "numeric",
    month: lang === "ja" ? "long" : "short",
    day: "numeric",
  }).format(date);
}

/// 時間量の表示。「1時間15分」「45分」「2時間」/ "1h 15m"。0分は「0分」。
export function durationLabel(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (lang === "ja") {
    if (h === 0) return `${m}分`;
    return m === 0 ? `${h}時間` : `${h}時間${m}分`;
  }
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

/// 学びの索引の件数。「12件」/「12 notes」。
export function noteCountLabel(n: number): string {
  return lang === "ja" ? `${n}件` : n === 1 ? "1 note" : `${n} notes`;
}

/// 港の招待の共有文。コードと合わせてOSの共有シートへ渡す。
export function inviteShareLine(name: string, code: string): string {
  return lang === "ja"
    ? `Landfallの港「${name}」に招待されました。コード: ${code}`
    : `You're invited to the harbor "${name}" on Landfall. Code: ${code}`;
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
    ? `${name}が着岸 — ${item}、${durationLabel(minutes)}`
    : `${name} made landfall — ${item}, ${durationLabel(minutes)}`;
}

export function chatReturnLine(name: string, gapDays: number): string {
  return lang === "ja"
    ? `${name}が帰還 — ${gapDays}日ぶりの航海。`
    : `${name} returned — first sail in ${gapDays} days.`;
}
