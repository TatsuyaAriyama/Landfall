import { useEffect, useRef, useState } from "react";
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
import { listenDestinations, type Destination } from "./destinations";
import {
  gapDaysBeforeToday,
  publishChatLog,
  publishCurrentMonth,
  type PublishSource,
} from "./harbor";
import {
  dayId,
  newUUID,
  startOfDay,
  trimAll,
  type StudyDay,
  type StudyItem,
  type StudySession,
  type VoyageLogEntry,
} from "./types";

// users/{uid}/items|sessions|days を購読し、iOS と同じ書式(updatedAt LWW)で書く。
// Web はローカルストアを持たず Firestore が直接の真実(iOS 側へはリスナー経由で同期される)。

export function useAuthUser(): {
  user: User | null;
  loading: boolean;
  redirectError: string | null;
} {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [redirectError, setRedirectError] = useState<string | null>(null);
  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => {
      setUser(u);
      setLoading(false);
    });
    // リダイレクト方式(モバイル Safari)で戻ってきた場合の認証情報を取り込む。
    // 失敗コードが返ってきたら、サインイン画面で案内できるように保持しておく
    // (以前は握りつぶすだけで、押しても無反応に見える原因になっていた)。
    void completeRedirectSignIn().then((code) => {
      if (code) setRedirectError(code);
    });
    return unsub;
  }, []);
  return { user, loading, redirectError };
}

function asDate(value: unknown): Date {
  return value instanceof Timestamp ? value.toDate() : new Date(0);
}

export interface UserData {
  items: StudyItem[];
  sessions: StudySession[];
  days: StudyDay[];
  voyageLogs: VoyageLogEntry[];
  destinations: Destination[];
  ready: boolean;
  /// 購読が失敗した、または待っても何も届かなかった。
  /// 画面を「読み込み中…」のまま放置せず、理由と再試行を出すために使う。
  failed: boolean;
  /// もう一度購読しなおす。
  retry: () => void;
}

/// どのコレクションが届いたか。1つのカウンタで数えてはいけない —
/// Firestoreは同じコレクションについて「キャッシュ→サーバ」と2回流すことがあり、
/// 合計3回に達しても days が一度も来ていない、という状態が起きる。
/// その場合 ready になってしまい、カレンダーが全ての過去日を「休んだ日」として
/// 塗ってしまう(繋がっているのに嘘を表示する)。
interface Loaded {
  items: boolean;
  sessions: boolean;
  days: boolean;
  voyageLogs: boolean;
}

/// これだけ待って何も届かなければ、繋がらないものとして扱う。
/// Firestoreはオフラインでも onSnapshot をエラーにせず、ただ黙るだけなので、
/// 時間で見切らないと「読み込み中…」から永久に戻らない。
const CONNECT_TIMEOUT_MS = 12000;

export function useUserData(uid: string, enabled = true): UserData {
  const [items, setItems] = useState<StudyItem[]>([]);
  const [sessions, setSessions] = useState<StudySession[]>([]);
  const [days, setDays] = useState<StudyDay[]>([]);
  const [voyageLogs, setVoyageLogs] = useState<VoyageLogEntry[]>([]);
  const [destinations, setDestinations] = useState<Destination[]>([]);
  const [loaded, setLoaded] = useState<Loaded>({
    items: false,
    sessions: false,
    days: false,
    voyageLogs: false,
  });
  const [failed, setFailed] = useState(false);
  // 再試行のたびに増やして、購読を張り直す。
  const [attempt, setAttempt] = useState(0);
  const loadedRef = useRef<Loaded>({
    items: false,
    sessions: false,
    days: false,
    voyageLogs: false,
  });

  useEffect(() => {
    if (!enabled) return;
    setItems([]);
    setSessions([]);
    setDays([]);
    setVoyageLogs([]);
    setDestinations([]);
    setFailed(false);
    loadedRef.current = {
      items: false,
      sessions: false,
      days: false,
      voyageLogs: false,
    };
    setLoaded(loadedRef.current);

    const mark = (key: keyof Loaded) => {
      if (loadedRef.current[key]) return;
      loadedRef.current = { ...loadedRef.current, [key]: true };
      setLoaded(loadedRef.current);
    };
    // 購読が落ちたら、待たせ続けずにその場で伝える(権限切れ・トークン失効など)。
    const onError = () => setFailed(true);

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
      mark("items");
    }, onError);

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
      mark("sessions");
    }, onError);

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
      mark("days");
    }, onError);

    const offVoyageLogs = onSnapshot(
      collection(db, "users", uid, "voyageLogs"),
      (snap) => {
        setVoyageLogs(
          snap.docs
            .map((d) => {
              const v = d.data();
              return {
                id: d.id,
                date: asDate(v.date),
                body: String(v.body ?? ""),
                updatedAt: asDate(v.updatedAt),
              };
            })
            .filter((entry) => entry.body.length > 0)
            .sort((a, b) => b.date.getTime() - a.date.getTime()),
        );
        mark("voyageLogs");
      },
      onError,
    );

    const offDestinations = listenDestinations(uid, setDestinations);

    // 黙ったまま何も来ない場合の見切り。
    const timer = setTimeout(() => {
      const l = loadedRef.current;
      if (!(l.items && l.sessions && l.days && l.voyageLogs)) setFailed(true);
    }, CONNECT_TIMEOUT_MS);

    return () => {
      clearTimeout(timer);
      offItems();
      offSessions();
      offDays();
      offVoyageLogs();
      offDestinations();
    };
  }, [uid, enabled, attempt]);

  const ready = loaded.items && loaded.sessions && loaded.days && loaded.voyageLogs;
  return {
    items,
    sessions,
    days,
    voyageLogs,
    destinations,
    ready,
    // 届いた後の失敗で画面を作り直さない(既に見えているものは見せ続ける)。
    failed: failed && !ready,
    retry: () => setAttempt((n) => n + 1),
  };
}

// ---- 書き込み(iOS の DTO 形に一致させる。undefined は書かない) ----
// 記録の保存・編集・削除では、参加中の港への月間ペイロード公開と、
// プライベート港チャットへの自動の行(着岸/帰還)も iOS と同じく行う。

/// 航海日録を一日一件で保存する。空文字は記録の削除として扱う。
export async function saveVoyageLog(
  uid: string,
  date: Date,
  body: string,
): Promise<void> {
  const id = dayId(date);
  const trimmed = trimAll(body).slice(0, 260);
  const ref = doc(db, "users", uid, "voyageLogs", id);
  if (!trimmed) {
    await deleteDoc(ref);
    return;
  }
  await setDoc(ref, {
    date: startOfDay(date),
    body: trimmed,
    updatedAt: new Date(),
  });
}

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
    name: trimAll(data.name).slice(0, 60),
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
  source: PublishSource,
): Promise<void> {
  const allSessions = source.sessions;
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
  await publishCurrentMonth({
    items: source.items.filter((i) => i.id !== itemId),
    sessions: remaining,
    days: source.days.filter(
      (d) => remainingDayIds.has(d.id) || !touchedDayIds.has(d.id),
    ),
  });
}

/// 1回の作業記録を保存し、その日を「学んだ日」として刻む(iOS の save と同じ意味論)。
/// 港に入っていれば月間ペイロードを公開し、今日の記録ならチャットに自動の行を流す。
export async function recordSession(
  uid: string,
  input: { item: StudyItem; minutes: number; note?: string; date?: Date },
  source: PublishSource,
): Promise<void> {
  const date = input.date ?? new Date();
  const note = input.note?.trim();
  const sessionId = newUUID();
  await setDoc(doc(db, "users", uid, "sessions", sessionId), {
    date,
    minutes: input.minutes,
    itemUUID: input.item.id,
    updatedAt: new Date(),
    ...(note ? { note: note.slice(0, 120) } : {}),
  });
  const dId = dayId(date);
  const existingDayIds = new Set(source.days.map((d) => d.id));
  const isNewDay = !existingDayIds.has(dId);
  if (isNewDay) {
    await setDoc(doc(db, "users", uid, "days", dId), {
      date: startOfDay(date),
      updatedAt: new Date(),
    });
  }

  // 空白日数は「今日の刻印を打つ前」の状態から数える(何日ぶりの航海か)。
  const gapDays = gapDaysBeforeToday(source.days);
  const isToday = dId === dayId(new Date());

  const nextSession: StudySession = {
    id: sessionId,
    date,
    minutes: input.minutes,
    note: note ? note.slice(0, 120) : undefined,
    itemUUID: input.item.id,
    updatedAt: new Date(),
  };
  const nextDays = isNewDay
    ? [...source.days, { id: dId, date: startOfDay(date), updatedAt: new Date() }]
    : source.days;
  await publishCurrentMonth({
    items: source.items,
    sessions: [...source.sessions, nextSession],
    days: nextDays,
  });
  if (isToday) {
    await publishChatLog({ item: input.item, minutes: input.minutes, gapDays });
  }
}

/// 記録の削除。その日の記録が全て消えたら「学んだ日」の刻印も外す(iOS の unmarkDayIfEmpty)。
export async function deleteSession(
  uid: string,
  session: StudySession,
  source: PublishSource,
): Promise<void> {
  await deleteDoc(doc(db, "users", uid, "sessions", session.id));
  const dId = dayId(session.date);
  const remainingSessions = source.sessions.filter((s) => s.id !== session.id);
  const remains = remainingSessions.some((s) => dayId(s.date) === dId);
  if (!remains) {
    await deleteDoc(doc(db, "users", uid, "days", dId));
  }
  await publishCurrentMonth({
    items: source.items,
    sessions: remainingSessions,
    days: remains ? source.days : source.days.filter((d) => d.id !== dId),
  });
}

/// その日のひとことを書き換える(学んだ日にだけ書ける。iOS の setComment と同じ)。
export async function setDayNote(
  uid: string,
  day: StudyDay,
  note: string | null,
  source: PublishSource,
): Promise<void> {
  const trimmed = note?.trim().slice(0, 120);
  await setDoc(doc(db, "users", uid, "days", day.id), {
    date: startOfDay(day.date),
    updatedAt: new Date(),
    ...(trimmed ? { note: trimmed } : {}),
  });
  await publishCurrentMonth({
    items: source.items,
    sessions: source.sessions,
    days: source.days.map((d) =>
      d.id === day.id ? { ...d, note: trimmed || undefined } : d,
    ),
  });
}
