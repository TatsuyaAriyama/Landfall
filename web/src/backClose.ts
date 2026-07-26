import { useEffect, useRef, type RefObject } from "react";

/// 全画面の重ね表示(目的地の世界・航海中の世界など)を、端末の「戻る」で閉じられるようにする。
///
/// これが無いと Android の戻るボタンは履歴を1つ戻ろうとする。manifest が standalone
/// なので戻る先が無く、編集画面ではなく**アプリ自体が終了**してしまう(書きかけが消える)。
/// iOS の standalone には戻る操作自体が無いので、そちらは画面内の「閉じる」が頼りになる
/// — どちらの端末でも詰まないようにするための片側の備え。
///
/// 開いたときに履歴を1つ積み、戻る操作(popstate)で onClose を呼ぶ。
/// 画面内のボタンで閉じたときは、積んだ履歴を自分で戻して残さない
/// (残すと、閉じた後の「戻る」が何も起きない空振りになる)。
/// 複数の重ね表示が同時に開くことがある(設定の上の確認ダイアログなど)。
/// 各画面が個別に popstate を聞くと「戻る」1回で全部閉じてしまうため、
/// モジュール全体で一つのスタックとして扱い、最前面だけを閉じる。
type BackEntry = {
  id: symbol;
  onCloseRef: RefObject<() => void>;
  closedByBack: boolean;
};

const backStack: BackEntry[] = [];
let suppressPops = 0;
let listening = false;

function ensurePopListener(): void {
  if (listening || typeof window === "undefined") return;
  listening = true;
  window.addEventListener("popstate", () => {
    if (suppressPops > 0) {
      suppressPops -= 1;
      return;
    }
    const top = backStack.at(-1);
    if (!top) return;
    top.closedByBack = true;
    top.onCloseRef.current();
  });
}

export function useBackToClose(active: boolean, onClose: () => void): void {
  // onClose の同一性が変わるたびに履歴を積み直さないよう、refで受ける。
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    if (!active) return;
    if (typeof window === "undefined" || !window.history) return;

    ensurePopListener();
    const entry: BackEntry = {
      id: Symbol("landfall-overlay"),
      onCloseRef,
      closedByBack: false,
    };
    backStack.push(entry);
    window.history.pushState({ landfallOverlay: true }, "");

    return () => {
      const index = backStack.findIndex((candidate) => candidate.id === entry.id);
      const wasTop = index === backStack.length - 1;
      if (index >= 0) backStack.splice(index, 1);
      // 戻る操作で閉じた場合は、履歴はもう戻っているので何もしない。
      if (entry.closedByBack) return;
      // 自分で積んだ1つぶんだけ戻す。state を確かめて、他の遷移を巻き戻さない。
      // 背面の画面が先に外された場合は、最前面の履歴を奪わない。
      if (wasTop && window.history.state?.landfallOverlay) {
        suppressPops += 1;
        window.history.back();
      }
    };
  }, [active]);
}
