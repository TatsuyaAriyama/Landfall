import { dayId, startOfDay } from "./types";
import type { UserData } from "./data";

// URLに #demo を付けたときだけ使う見本データ(デザイン確認用。Firestoreには触れない)。

export const isDemo =
  typeof window !== "undefined" && window.location.hash === "#demo";

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
    { id: "S-3", date: at(2), minutes: 60, itemUUID: "DEMO-3", updatedAt: at(2) },
    { id: "S-4", date: at(3), minutes: 25, itemUUID: "DEMO-1", updatedAt: at(3) },
    { id: "S-5", date: at(7), minutes: 90, note: "戻ってきた。", itemUUID: "DEMO-2", updatedAt: at(7) },
    { id: "S-6", date: at(8), minutes: 40, itemUUID: "DEMO-1", updatedAt: at(8) },
    { id: "S-7", date: at(12), minutes: 20, itemUUID: "DEMO-3", updatedAt: at(12) },
  ];
  const dayIds = [...new Set(sessions.map((s) => dayId(s.date)))];
  const days = dayIds.map((id) => ({
    id,
    date: startOfDay(new Date(id)),
    updatedAt: now,
  }));
  return { items, sessions, days, ready: true };
}
