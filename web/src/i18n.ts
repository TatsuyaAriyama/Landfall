// 最小限の i18n。iOS と同じく英語をキー言語にせず、辞書キーで引く。
// 言語はブラウザ設定から判定(ja 以外は英語)。

const ja = {
  appName: "Landfall",
  tagline: "休んでも戻れる学習記録。\nやめた回数はいつも0。",
  signInWithGoogle: "Googleで続ける",
  signInNote: "iOSアプリと同じアカウントで、記録がそのままつながります。",
  today: "今日",
  trace: "軌跡",
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
  dayNote: "この日のひとこと",
  signInFailed: "サインインに失敗しました。もう一度お試しください。",
} as const;

export type I18nKey = keyof typeof ja;

const en: Record<I18nKey, string> = {
  appName: "Landfall",
  tagline: "A study log you can always come back to.\nTimes quit: always zero.",
  signInWithGoogle: "Continue with Google",
  signInNote: "Sign in with the same account as the iOS app and your record carries over.",
  today: "Today",
  trace: "Trace",
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
  dayNote: "A word about this day",
  signInFailed: "Sign-in failed. Please try again.",
};

export const lang: "ja" | "en" =
  typeof navigator !== "undefined" && navigator.language.startsWith("ja") ? "ja" : "en";

const dict = lang === "ja" ? ja : en;

export function t(key: I18nKey): string {
  return dict[key];
}
