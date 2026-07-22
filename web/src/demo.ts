import { dayId, startOfDay } from "./types";
import type { UserData } from "./data";
import type { HarborMember, HarborRoom } from "./harbor";

// URLに #demo を付けたときだけ使う見本データ(デザイン確認用。Firestoreには触れない)。

export const isDemo =
  typeof window !== "undefined" && window.location.hash === "#demo";

// ---- 港のデモ(プライベートの港と「みんなの海」の見本) ----

export function demoRoom(): HarborRoom {
  return {
    id: "DEMO42",
    name: "夜光虫の港",
    memberIds: ["demo", "D-2", "D-3", "D-4"],
    ownerUid: "demo",
  };
}

export function demoHarborMembers(): HarborMember[] {
  return [
    {
      id: "demo",
      displayName: "ハル",
      styleToken: "seaGreen",
      symbolToken: "compass",
      resolve: "毎日は無理でも、また戻る。",
      boatSail: "coral",
      boatJib: "sand",
      boatHull: "sand",
      boatStripe: "returnOrange",
      boatFlag: "pennant",
    },
    {
      id: "D-2",
      displayName: "ミナト",
      styleToken: "midnight",
      symbolToken: "lighthouse",
      resolve: "",
      boatSail: "sunYellow",
      boatJib: "seaGreen",
      boatHull: "coral",
      boatStripe: "none",
      boatFlag: "none",
    },
    {
      id: "D-3",
      displayName: "ヨル",
      styleToken: "violet",
      symbolToken: "book",
      resolve: "",
      boatSail: "lavender",
      boatJib: "coral",
      boatHull: "deepRust",
      boatStripe: "deepRust",
      boatFlag: "swallow",
    },
    {
      id: "D-4",
      displayName: "アオイ",
      styleToken: "sunYellow",
      symbolToken: "pen",
      resolve: "",
      boatSail: "seaGreen",
      boatJib: "sunYellow",
      boatHull: "sand",
      boatStripe: "none",
      boatFlag: "none",
    },
  ];
}

/// 「今日走った」ことにするデモメンバー(みんなの海のランタン見本)。
export const demoLitMemberIds: ReadonlySet<string> = new Set(["demo", "D-3"]);

export function demoData(): UserData {
  const now = new Date();
  const at = (daysAgo: number, hour = 20) => {
    const d = new Date(now);
    d.setDate(d.getDate() - daysAgo);
    d.setHours(hour, 0, 0, 0);
    return d;
  };
  const items = [
    {
      id: "DEMO-1",
      name: "英語",
      styleToken: "seaGreen",
      symbolToken: "compass",
      sortOrder: 0,
      createdAt: at(40),
      updatedAt: at(0),
    },
    {
      id: "DEMO-2",
      name: "読書",
      styleToken: "midnight",
      symbolToken: "book",
      sortOrder: 1,
      createdAt: at(35),
      updatedAt: at(0),
    },
    {
      id: "DEMO-3",
      name: "制作",
      styleToken: "sunYellow",
      symbolToken: "pen",
      sortOrder: 2,
      createdAt: at(20),
      updatedAt: at(0),
    },
  ];
  const sessions = [
    { id: "S-1", date: at(0, 9), minutes: 30, note: "朝の30分。", itemUUID: "DEMO-1", updatedAt: at(0) },
    { id: "S-2", date: at(0, 21), minutes: 45, itemUUID: "DEMO-2", updatedAt: at(0) },
    { id: "S-3", date: at(5), minutes: 60, itemUUID: "DEMO-3", updatedAt: at(5) },
    { id: "S-4", date: at(3), minutes: 25, itemUUID: "DEMO-1", updatedAt: at(3) },
    { id: "S-5", date: at(7), minutes: 90, note: "戻ってきた。", itemUUID: "DEMO-2", updatedAt: at(7) },
    { id: "S-6", date: at(8), minutes: 40, itemUUID: "DEMO-1", updatedAt: at(8) },
    { id: "S-7", date: at(12), minutes: 20, itemUUID: "DEMO-3", updatedAt: at(12) },
    // 先月の記録(航海誌のデモ用: 帰還のある月)。
    { id: "S-8", date: at(30), minutes: 45, itemUUID: "DEMO-1", updatedAt: at(30) },
    { id: "S-9", date: at(33), minutes: 30, itemUUID: "DEMO-2", updatedAt: at(33) },
    { id: "S-10", date: at(34), minutes: 60, itemUUID: "DEMO-1", updatedAt: at(34) },
    { id: "S-11", date: at(41), minutes: 25, itemUUID: "DEMO-3", updatedAt: at(41) },
    { id: "S-12", date: at(42), minutes: 50, itemUUID: "DEMO-1", updatedAt: at(42) },
    { id: "S-13", date: at(45), minutes: 40, itemUUID: "DEMO-2", updatedAt: at(45) },
  ];
  const dayIds = [...new Set(sessions.map((s) => dayId(s.date)))];
  const days = dayIds.map((id) => ({
    id,
    date: startOfDay(new Date(id)),
    updatedAt: now,
  }));
  const destinations = [
    {
      id: "DEST-1",
      name: "TOEIC",
      itemUUID: "DEMO-1",
      targetMinutes: 20 * 60,
      createdAt: at(40),
      updatedAt: now,
    },
    {
      id: "DEST-2",
      name: "『百年の孤独』読了",
      itemUUID: "DEMO-2",
      targetMinutes: 10 * 60,
      createdAt: at(50),
      achievedAt: at(10),
      updatedAt: now,
    },
  ];
  return { items, sessions, days, destinations, ready: true };
}
