import {
  deleteDoc,
  doc,
  onSnapshot,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { db } from "./firebase";
import type { RunningTimer, TimerMode } from "./timer";

const timerRef = (uid: string) => doc(db, "users", uid, "state", "timer");

function parseTimer(value: Record<string, unknown>): RunningTimer | null {
  const startedAt =
    value.startedAt instanceof Timestamp ? value.startedAt.toMillis() : 0;
  const breakStartedAt =
    value.breakStartedAt instanceof Timestamp
      ? value.breakStartedAt.toMillis()
      : null;
  const itemId = typeof value.itemId === "string" ? value.itemId : "";
  const mode: TimerMode = value.mode === "pomo" ? "pomo" : "free";
  const breakMs =
    typeof value.breakMs === "number" && Number.isFinite(value.breakMs)
      ? Math.max(0, value.breakMs)
      : 0;
  if (!itemId || startedAt <= 0) return null;
  return { itemId, startedAt, mode, breakMs, breakStartedAt };
}

/// PCとスマホのWeb版で、進行中の航海を同じカードとして表示する。
/// 初回だけ存在しないリモートへ端末内の旧タイマーを移行し、それ以降は
/// Firestoreの更新・削除を各端末へリアルタイムに流す。
export function listenRunningTimer(
  uid: string,
  localTimer: RunningTimer | null,
  onChange: (timer: RunningTimer | null) => void,
): () => void {
  let firstSnapshot = true;
  return onSnapshot(
    timerRef(uid),
    (snapshot) => {
      if (!snapshot.exists()) {
        if (firstSnapshot && localTimer) {
          void saveRunningTimer(uid, localTimer);
        } else {
          onChange(null);
        }
        firstSnapshot = false;
        return;
      }
      firstSnapshot = false;
      onChange(parseTimer(snapshot.data()));
    },
    () => {
      // オフライン時は端末内タイマーをそのまま使い、再接続後の購読に任せる。
    },
  );
}

export async function saveRunningTimer(
  uid: string,
  timer: RunningTimer,
): Promise<void> {
  await setDoc(timerRef(uid), {
    itemId: timer.itemId,
    startedAt: new Date(timer.startedAt),
    mode: timer.mode,
    breakMs: Math.max(0, Math.round(timer.breakMs)),
    ...(timer.breakStartedAt
      ? { breakStartedAt: new Date(timer.breakStartedAt) }
      : {}),
    updatedAt: new Date(),
  });
}

export async function deleteRunningTimer(uid: string): Promise<void> {
  await deleteDoc(timerRef(uid));
}
