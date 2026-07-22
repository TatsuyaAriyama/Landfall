import { useEffect, useState } from "react";
import { onAuthStateChanged, type User } from "firebase/auth";
import {
  collection,
  deleteDoc,
  doc,
  onSnapshot,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { auth, db } from "./firebase";
import { completeRedirectSignIn } from "./auth";
import {
  dayId,
  newUUID,
  startOfDay,
  type StudyDay,
  type StudyItem,
  type StudySession,
} from "./types";

// users/{uid}/items|sessions|days を購読し、iOS と同じ書式(updatedAt LWW)で書く。
// Web はローカルストアを持たず Firestore が直接の真実(iOS 側へはリスナー経由で同期される)。

export function useAuthUser(): { user: User | null; loading: boolean } {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => {
      setUser(u);
      setLoading(false);
    });
    // リダイレクト方式(モバイル Safari)で戻ってきた場合の認証情報を取り込む。
    void completeRedirectSignIn();
    return unsub;
  }, []);
  return { user, loading };
}

function asDate(value: unknown): Date {
  return value instanceof Timestamp ? value.toDate() : new Date(0);
}

export interface UserData {
  items: StudyItem[];
  sessions: StudySession[];
  days: StudyDay[];
  ready: boolean;
}

export function useUserData(uid: string, enabled = true): UserData {
  const [items, setItems] = useState<StudyItem[]>([]);
  const [sessions, setSessions] = useState<StudySession[]>([]);
  const [days, setDays] = useState<StudyDay[]>([]);
  const [readyCount, setReadyCount] = useState(0);

  useEffect(() => {
    if (!enabled) return;
    setItems([]);
    setSessions([]);
    setDays([]);
    setReadyCount(0);
    const bump = () => setReadyCount((n) => Math.min(n + 1, 3));

    const offItems = onSnapshot(collection(db, "users", uid, "items"), (snap) => {
      setItems(
        snap.docs
          .map((d) => {
            const v = d.data();
            return {
              id: d.id,
              name: String(v.name ?? ""),
              styleToken: String(v.styleToken ?? "midnight"),
              symbolToken: String(v.symbolToken ?? "compass"),
              sortOrder: Number(v.sortOrder ?? 0),
              createdAt: asDate(v.createdAt),
              updatedAt: asDate(v.updatedAt),
            };
          })
          .sort((a, b) => a.sortOrder - b.sortOrder),
      );
      bump();
    });

    const offSessions = onSnapshot(collection(db, "users", uid, "sessions"), (snap) => {
      setSessions(
        snap.docs
          .map((d) => {
            const v = d.data();
            return {
              id: d.id,
              date: asDate(v.date),
              minutes: Number(v.minutes ?? 0),
              note: typeof v.note === "string" ? v.note : undefined,
              itemUUID: typeof v.itemUUID === "string" ? v.itemUUID : undefined,
              updatedAt: asDate(v.updatedAt),
            };
          })
          .sort((a, b) => b.date.getTime() - a.date.getTime()),
      );
      bump();
    });

    const offDays = onSnapshot(collection(db, "users", uid, "days"), (snap) => {
      setDays(
        snap.docs.map((d) => {
          const v = d.data();
          return {
            id: d.id,
            date: asDate(v.date),
            note: typeof v.note === "string" ? v.note : undefined,
            updatedAt: asDate(v.updatedAt),
          };
        }),
      );
      bump();
    });

    return () => {
      offItems();
      offSessions();
      offDays();
    };
  }, [uid, enabled]);

  return { items, sessions, days, ready: readyCount >= 3 };
}

// ---- 書き込み(iOS の DTO 形に一致させる。undefined は書かない) ----

export async function saveItem(
  uid: string,
  data: {
    id?: string;
    name: string;
    styleToken: string;
    symbolToken: string;
    sortOrder: number;
    createdAt?: Date;
  },
): Promise<void> {
  const id = data.id ?? newUUID();
  await setDoc(doc(db, "users", uid, "items", id), {
    name: data.name,
    styleToken: data.styleToken,
    symbolToken: data.symbolToken,
    sortOrder: data.sortOrder,
    createdAt: data.createdAt ?? new Date(),
    updatedAt: new Date(),
  });
}

/// 項目の削除。iOS はローカルの cascade で記録も消えるので、Web も紐づく記録を消し、
/// 空になった日の刻印(days)も外して整合を保つ。
export async function deleteItemDeep(
  uid: string,
  itemId: string,
  allSessions: StudySession[],
): Promise<void> {
  const mine = allSessions.filter((s) => s.itemUUID === itemId);
  for (const s of mine) {
    await deleteDoc(doc(db, "users", uid, "sessions", s.id));
  }
  await deleteDoc(doc(db, "users", uid, "items", itemId));
  // 空になった日の刻印を外す。
  const remaining = allSessions.filter((s) => s.itemUUID !== itemId);
  const remainingDayIds = new Set(remaining.map((s) => dayId(s.date)));
  const touchedDayIds = new Set(mine.map((s) => dayId(s.date)));
  for (const dId of touchedDayIds) {
    if (!remainingDayIds.has(dId)) {
      await deleteDoc(doc(db, "users", uid, "days", dId));
    }
  }
}

/// 1回の作業記録を保存し、その日を「学んだ日」として刻む(iOS の save と同じ意味論)。
export async function recordSession(
  uid: string,
  input: { itemId: string; minutes: number; note?: string; date?: Date },
  existingDayIds: Set<string>,
): Promise<void> {
  const date = input.date ?? new Date();
  const note = input.note?.trim();
  await setDoc(doc(db, "users", uid, "sessions", newUUID()), {
    date,
    minutes: input.minutes,
    itemUUID: input.itemId,
    updatedAt: new Date(),
    ...(note ? { note: note.slice(0, 120) } : {}),
  });
  const dId = dayId(date);
  if (!existingDayIds.has(dId)) {
    await setDoc(doc(db, "users", uid, "days", dId), {
      date: startOfDay(date),
      updatedAt: new Date(),
    });
  }
}

/// 記録の削除。その日の記録が全て消えたら「学んだ日」の刻印も外す(iOS の unmarkDayIfEmpty)。
export async function deleteSession(
  uid: string,
  session: StudySession,
  allSessions: StudySession[],
): Promise<void> {
  await deleteDoc(doc(db, "users", uid, "sessions", session.id));
  const dId = dayId(session.date);
  const remains = allSessions.some(
    (s) => s.id !== session.id && dayId(s.date) === dId,
  );
  if (!remains) {
    await deleteDoc(doc(db, "users", uid, "days", dId));
  }
}
