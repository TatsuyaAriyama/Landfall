import { auth } from "./firebase";
import { startOfDay, type StudyDay, type StudySession } from "./types";

// このサービスを使い始めた日(航海のはじまり)。
//
// これが無いと「まだ使っていなかった日」まで休んだ日に数えてしまう。
// 初めてログインした人が、その月の1日から今日までずっと休んでいたことに
// なるのは事実に反するので、数える範囲の起点として使う。
//
// 基準はアカウントを作った日(Firebase Auth の creationTime)。サーバ由来で
// 端末をまたいでも同じ値になる。ただし記録の方が古いこともありうる
// (手入力・端末の時計ずれ・他プラットフォームからの移行)ので、
// 記録の最古日がそれより前ならそちらを採る。記録が範囲の外に落ちないことを
// 優先する。

/// Firestoreの日付が欠けていると new Date(0) になる(data.ts の asDate)。
/// 1970年は「はじまり」ではないので、明らかに古い値は無視する。
const EPOCH_GUARD = Date.UTC(2000, 0, 1);

/// アカウントを作った日。サインインしていなければ null(デモ表示など)。
function accountCreatedAt(): number | null {
  const raw = auth.currentUser?.metadata?.creationTime;
  if (!raw) return null;
  const ms = new Date(raw).getTime();
  return Number.isFinite(ms) && ms > EPOCH_GUARD ? ms : null;
}

/// 使い始めた日(その日の0時)。何も手がかりが無ければ null。
export function serviceStartDay(
  days: StudyDay[],
  sessions: StudySession[],
): Date | null {
  let earliest = accountCreatedAt();
  const consider = (date: Date) => {
    const ms = date.getTime();
    if (!Number.isFinite(ms) || ms <= EPOCH_GUARD) return;
    if (earliest === null || ms < earliest) earliest = ms;
  };
  for (const d of days) consider(d.date);
  for (const s of sessions) consider(s.date);
  return earliest === null ? null : startOfDay(new Date(earliest));
}
