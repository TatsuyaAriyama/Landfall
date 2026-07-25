import { useEffect, useRef } from "react";

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
/// 自分で戻した履歴ぶんの popstate を数えて読み飛ばすためのカウンタ。
///
/// history.back() は非同期なので、後片付けで戻したぶんの popstate が、次に開いた
/// 側のリスナーに届いてしまう(開いた瞬間に閉じる)。React の開発モードは効果を
/// 意図的に2回走らせるため、これは確実に起きる。モジュール共有のカウンタで、
/// 「自分が起こした戻り」を1回だけ無視する。
let suppressPops = 0;

export function useBackToClose(active: boolean, onClose: () => void): void {
  // onClose の同一性が変わるたびに履歴を積み直さないよう、refで受ける。
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    if (!active) return;
    if (typeof window === "undefined" || !window.history) return;

    window.history.pushState({ landfallOverlay: true }, "");
    let closedByBack = false;

    const onPop = () => {
      // 自分の後片付けで起きた戻りなら、閉じる指示ではない。
      if (suppressPops > 0) {
        suppressPops -= 1;
        return;
      }
      closedByBack = true;
      onCloseRef.current();
    };
    window.addEventListener("popstate", onPop);

    return () => {
      window.removeEventListener("popstate", onPop);
      // 戻る操作で閉じた場合は、履歴はもう戻っているので何もしない。
      if (closedByBack) return;
      // 自分で積んだ1つぶんだけ戻す。state を確かめて、他の遷移を巻き戻さない。
      if (window.history.state?.landfallOverlay) {
        suppressPops += 1;
        window.history.back();
      }
    };
  }, [active]);
}
