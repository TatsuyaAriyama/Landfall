import { useEffect } from "react";

// 全画面表示とモーダルが重なっても、最後の一枚が閉じるまでは背景を固定し、
// すべて閉じた時だけ元のスクロール状態へ戻す。
//
// 各コンポーネントが個別に body.style.overflow を保存すると、
//  1. 航海画面が "" → hidden
//  2. 確認ダイアログが hidden → hidden
//  3. 航海画面が "" に戻す
//  4. ダイアログが保存済みの hidden に戻す
// となり、何も表示されていないのにページだけ永久に固定される。

let lockCount = 0;
let originalOverflow = "";

export function lockBodyScroll(): () => void {
  if (lockCount === 0) {
    originalOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
  }
  lockCount += 1;

  let released = false;
  return () => {
    if (released) return;
    released = true;
    lockCount = Math.max(0, lockCount - 1);
    if (lockCount === 0) {
      document.body.style.overflow = originalOverflow;
      originalOverflow = "";
    }
  };
}

/**
 * 表示している間だけ背景を固定する。
 *
 * Escなど別の副作用と同じuseEffectへ混ぜると、その依存値が変わるたびに
 * overflowを解除→再設定してしまう。iOS Safariはこの短い切り替えでも
 * スクロール対象を見失うことがあるため、固定の寿命はコンポーネントの
 * マウント期間だけに揃える。
 */
export function useBodyScrollLock(enabled = true): void {
  useEffect(() => {
    if (!enabled) return;
    return lockBodyScroll();
  }, [enabled]);
}
