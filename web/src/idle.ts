/**
 * 初期描画と操作を邪魔せず、端末が空いたところで先読みする。
 * Safari は requestIdleCallback を持たないため、短いタイマーへフォールバックする。
 */
export function whenIdle(
  task: () => void,
  { delay = 1400, timeout = 3000 }: { delay?: number; timeout?: number } = {},
): () => void {
  // TypeScriptのDOM型には常に存在する定義だが、Safariでは実行時に未実装。
  const idleWindow = window as unknown as {
    requestIdleCallback?: (callback: () => void, options: { timeout: number }) => number;
    cancelIdleCallback?: (id: number) => void;
  };
  let idleId: number | null = null;
  // requestIdleCallback は描画直後にも呼ばれ得る。まず最低限の猶予を置き、
  // 初期データの描画や最初のスクロールと先読み通信が競合しないようにする。
  const timerId = globalThis.setTimeout(() => {
    if (idleWindow.requestIdleCallback) {
      idleId = idleWindow.requestIdleCallback(task, { timeout });
    } else {
      task();
    }
  }, delay);

  return () => {
    globalThis.clearTimeout(timerId);
    if (idleId !== null) idleWindow.cancelIdleCallback?.(idleId);
  };
}
