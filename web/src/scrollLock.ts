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
