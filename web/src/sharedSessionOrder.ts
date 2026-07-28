export interface DatedSharedSession {
  day?: number;
  date?: Date;
}

/**
 * 港の共有記録を新しい順に揃える。
 *
 * 現行データは記録時刻で比較し、時刻を持たない旧データは日付で比較する。
 * コピーを返すため、React state や Firestore 由来の配列を破壊しない。
 */
export function newestSharedSessionsFirst<T extends DatedSharedSession>(
  sessions: readonly T[],
): T[] {
  return [...sessions].sort((a, b) => {
    const aTime = a.date?.getTime();
    const bTime = b.date?.getTime();

    if (aTime !== undefined && bTime !== undefined && aTime !== bTime) {
      return bTime - aTime;
    }
    const aDay = a.day ?? a.date?.getDate() ?? 0;
    const bDay = b.day ?? b.date?.getDate() ?? 0;
    if (aDay !== bDay) return bDay - aDay;
    if (aTime !== undefined && bTime === undefined) return -1;
    if (aTime === undefined && bTime !== undefined) return 1;
    return 0;
  });
}
