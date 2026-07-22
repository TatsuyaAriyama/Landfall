import {
  collection,
  deleteDoc,
  doc,
  setDoc,
  Timestamp,
  onSnapshot,
} from "firebase/firestore";
import { db } from "./firebase";
import { newUUID, startOfDay, trimAll, type StudyItem, type StudySession } from "./types";

// 目的地(島)。学習の目標を島として置き、記録するたび船が近づく。
// 到達した日が Landfall(着岸)。users/{uid}/destinations/{uuid} に保存する
// (docs/SCHEMA.md 参照。ルールは users/** の本人のみで既にカバー)。

export interface Destination {
  id: string;
  name: string;
  itemUUID?: string; // 紐づく項目。省略時はすべての記録が進捗に数えられる
  targetMinutes?: number; // 累計時間の目標(分)
  targetDate?: Date; // 期日の目標。manual=trueのときは任意の締切メモとして使う
  // 完了ゴール(課題など、時間や日数では測れないもの向け)。記録からの自動導出ではなく、
  // 本人が「完了にする」を押した時だけ達成になる — このアプリで唯一の手動ゴール。
  manual?: boolean;
  manualDone?: boolean;
  createdAt: Date;
  achievedAt?: Date;
  updatedAt: Date;
}

/// 個人の目的地はひとつだけ。いま向かう島に集中する
/// (港などでの共同の目的地は、これとは別の仕組み)。
export const MAX_ACTIVE_DESTINATIONS = 1;

export function listenDestinations(
  uid: string,
  cb: (list: Destination[]) => void,
): () => void {
  return onSnapshot(
    collection(db, "users", uid, "destinations"),
    (snap) => {
      cb(
        snap.docs
          .map((d) => {
            const v = d.data();
            const date = (k: string) =>
              v[k] instanceof Timestamp ? (v[k] as Timestamp).toDate() : undefined;
            return {
              id: d.id,
              name: String(v.name ?? ""),
              itemUUID: typeof v.itemUUID === "string" ? v.itemUUID : undefined,
              targetMinutes: typeof v.targetMinutes === "number" ? v.targetMinutes : undefined,
              targetDate: date("targetDate"),
              manual: v.manual === true,
              manualDone: v.manualDone === true,
              createdAt: date("createdAt") ?? new Date(0),
              achievedAt: date("achievedAt"),
              updatedAt: date("updatedAt") ?? new Date(0),
            };
          })
          .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime()),
      );
    },
    () => cb([]),
  );
}

export async function saveDestination(
  uid: string,
  input: {
    id?: string;
    name: string;
    itemUUID?: string;
    targetMinutes?: number;
    targetDate?: Date;
    manual?: boolean;
    manualDone?: boolean;
    createdAt?: Date;
    achievedAt?: Date;
  },
): Promise<void> {
  const id = input.id ?? newUUID();
  await setDoc(doc(db, "users", uid, "destinations", id), {
    name: trimAll(input.name).slice(0, 60),
    ...(input.itemUUID ? { itemUUID: input.itemUUID } : {}),
    ...(input.targetMinutes ? { targetMinutes: Math.min(input.targetMinutes, 600000) } : {}),
    ...(input.targetDate ? { targetDate: input.targetDate } : {}),
    ...(input.manual ? { manual: true } : {}),
    ...(input.manualDone ? { manualDone: true } : {}),
    ...(input.achievedAt ? { achievedAt: input.achievedAt } : {}),
    createdAt: input.createdAt ?? new Date(),
    updatedAt: new Date(),
  });
}

export async function deleteDestination(uid: string, id: string): Promise<void> {
  await deleteDoc(doc(db, "users", uid, "destinations", id));
}

// ---- 進捗 ----

export interface DestinationProgress {
  ratio: number; // 0..1(島までの近さ)
  minutes: number; // 数えた累計(分)
  remainingMinutes?: number; // 時間目標の残り
  remainingDays?: number; // 期日目標の残り日数
  reached: boolean;
}

/// 島までの進捗。時間目標は「目的地を決めてからの累計」、期日目標は経過時間で近づく。
/// 完了目標(manual)は記録から自動導出せず、本人が刻んだ manualDone だけで進む。
export function destinationProgress(
  dest: Destination,
  sessions: StudySession[],
  now: Date = new Date(),
): DestinationProgress {
  const since = dest.createdAt;
  const minutes = sessions.reduce((sum, s) => {
    if (s.date < since) return sum;
    if (dest.itemUUID && s.itemUUID !== dest.itemUUID) return sum;
    return sum + s.minutes;
  }, 0);

  if (dest.manual) {
    // targetDate はここでは締切のメモ表示のみに使い、進捗や達成の判定には使わない。
    const remainingDays = dest.targetDate
      ? Math.max(
          0,
          Math.round(
            (startOfDay(dest.targetDate).getTime() - startOfDay(now).getTime()) / 86400000,
          ),
        )
      : undefined;
    return { ratio: dest.manualDone ? 1 : 0, minutes, remainingDays, reached: Boolean(dest.manualDone) };
  }

  if (dest.targetMinutes && dest.targetMinutes > 0) {
    const ratio = Math.min(1, minutes / dest.targetMinutes);
    return {
      ratio,
      minutes,
      remainingMinutes: Math.max(0, dest.targetMinutes - minutes),
      reached: ratio >= 1,
    };
  }

  if (dest.targetDate) {
    const start = startOfDay(since).getTime();
    const end = startOfDay(dest.targetDate).getTime();
    const today = startOfDay(now).getTime();
    const total = Math.max(1, end - start);
    const ratio = Math.min(1, Math.max(0, (today - start) / total));
    const remainingDays = Math.max(0, Math.round((end - today) / 86400000));
    return { ratio, minutes, remainingDays, reached: today >= end };
  }

  return { ratio: 0, minutes, reached: false };
}

// ---- 復習の提案(②) ----

export interface ReviewSuggestion {
  item: StudyItem;
  gapDays: number;
}

/// しばらく触れていない項目をそっと知らせる(最大2件・3〜60日)。
/// 休みを責めない: 事実と、戻ると思い出しやすいという理由だけを言う。
export function reviewSuggestions(
  items: StudyItem[],
  sessions: StudySession[],
  now: Date = new Date(),
): ReviewSuggestion[] {
  const today = startOfDay(now).getTime();
  const result: ReviewSuggestion[] = [];
  for (const item of items) {
    let last: number | null = null;
    for (const s of sessions) {
      if (s.itemUUID !== item.id) continue;
      const d = startOfDay(s.date).getTime();
      if (last === null || d > last) last = d;
    }
    if (last === null) continue;
    const gapDays = Math.round((today - last) / 86400000);
    if (gapDays >= 3 && gapDays <= 60) result.push({ item, gapDays });
  }
  return result.sort((a, b) => b.gapDays - a.gapDays).slice(0, 2);
}
