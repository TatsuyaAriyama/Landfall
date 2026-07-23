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

/// 大きな目標を分解した、航路上の小さな目印(ステップ)。順序付き。
/// ひとつ達成するごとに船が一区画進み、全部達成で着岸。doneAtが立つ=達成。
export interface DestinationStep {
  id: string;
  name: string;
  doneAt?: Date;
}

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
  // ステップ目標(長期の大きな目標向け)。stepsが非空ならステップ目標として扱い、
  // 進捗=完了数/全数、全部完了で着岸。時間/期日/完了とは排他。
  steps?: DestinationStep[];
  createdAt: Date;
  achievedAt?: Date;
  updatedAt: Date;
}

/// 個人の目的地はひとつだけ。いま向かう島に集中する
/// (港などでの共同の目的地は、これとは別の仕組み)。
export const MAX_ACTIVE_DESTINATIONS = 1;

/// ステップの上限。分解しすぎて航路が埋まらない程度に抑える。
export const MAX_STEPS = 20;

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
            const steps: DestinationStep[] | undefined = Array.isArray(v.steps)
              ? (v.steps as unknown[]).flatMap((s) => {
                  if (typeof s !== "object" || s === null) return [];
                  const o = s as Record<string, unknown>;
                  if (typeof o.id !== "string" || typeof o.name !== "string") return [];
                  const step: DestinationStep = { id: o.id, name: o.name };
                  if (o.doneAt instanceof Timestamp) step.doneAt = o.doneAt.toDate();
                  return [step];
                })
              : undefined;
            return {
              id: d.id,
              name: String(v.name ?? ""),
              itemUUID: typeof v.itemUUID === "string" ? v.itemUUID : undefined,
              targetMinutes: typeof v.targetMinutes === "number" ? v.targetMinutes : undefined,
              targetDate: date("targetDate"),
              manual: v.manual === true,
              manualDone: v.manualDone === true,
              steps: steps && steps.length > 0 ? steps : undefined,
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
    steps?: DestinationStep[];
    createdAt?: Date;
    achievedAt?: Date;
  },
): Promise<void> {
  const id = input.id ?? newUUID();
  // ステップは名前を整えて上限で切り、doneAtは立っているものだけ持つ。
  const steps = (input.steps ?? [])
    .slice(0, MAX_STEPS)
    .map((s) => ({
      id: s.id,
      name: trimAll(s.name).slice(0, 60),
      ...(s.doneAt ? { doneAt: s.doneAt } : {}),
    }));
  await setDoc(doc(db, "users", uid, "destinations", id), {
    name: trimAll(input.name).slice(0, 60),
    ...(input.itemUUID ? { itemUUID: input.itemUUID } : {}),
    ...(input.targetMinutes ? { targetMinutes: Math.min(input.targetMinutes, 600000) } : {}),
    ...(input.targetDate ? { targetDate: input.targetDate } : {}),
    ...(input.manual ? { manual: true } : {}),
    ...(input.manualDone ? { manualDone: true } : {}),
    ...(steps.length > 0 ? { steps } : {}),
    ...(input.achievedAt ? { achievedAt: input.achievedAt } : {}),
    createdAt: input.createdAt ?? new Date(),
    updatedAt: new Date(),
  });
}

/// ステップの達成をその場で反転する(パネルのチェック / 世界のブイタップ)。
/// 名前・項目・並びは保ったまま、該当ステップの doneAt だけ立てる/消す。
export async function toggleDestinationStep(
  uid: string,
  dest: Destination,
  stepId: string,
  now: Date = new Date(),
): Promise<void> {
  const steps = (dest.steps ?? []).map((s) =>
    s.id === stepId ? { ...s, doneAt: s.doneAt ? undefined : now } : s,
  );
  await saveDestination(uid, {
    id: dest.id,
    name: dest.name,
    itemUUID: dest.itemUUID,
    steps,
    createdAt: dest.createdAt,
  });
}

export async function deleteDestination(uid: string, id: string): Promise<void> {
  await deleteDoc(doc(db, "users", uid, "destinations", id));
}

/// 完了ゴールの達成をその場で刻む(カード上のチェックから)。名前・項目・締切メモは
/// 保ったまま manualDone だけ立てる。achievedAt自体はDestinationsSectionのreached監視が書く。
export async function markDestinationDone(uid: string, dest: Destination): Promise<void> {
  await saveDestination(uid, {
    id: dest.id,
    name: dest.name,
    itemUUID: dest.itemUUID,
    targetDate: dest.targetDate,
    manual: true,
    manualDone: true,
    createdAt: dest.createdAt,
  });
}

// ---- 進捗 ----

export interface DestinationProgress {
  ratio: number; // 0..1(島までの近さ)
  minutes: number; // 数えた累計(分)
  remainingMinutes?: number; // 時間目標の残り
  remainingDays?: number; // 期日目標の残り日数
  stepsDone?: number; // ステップ目標の完了数
  stepsTotal?: number; // ステップ目標の全数
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

  if (dest.steps && dest.steps.length > 0) {
    // ステップ目標: 進捗=完了数/全数。全部完了で着岸。時間は表示用にだけ数える。
    const done = dest.steps.filter((s) => s.doneAt).length;
    return {
      ratio: done / dest.steps.length,
      minutes,
      stepsDone: done,
      stepsTotal: dest.steps.length,
      reached: done === dest.steps.length,
    };
  }

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
