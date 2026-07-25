// 「実際に見えている高さ」をCSSから使えるようにする。
//
// iOS Safari はキーボードやピッカーが出てもレイアウトビューポート(vh/dvh)を
// 縮めないため、100dvh も 85vh も「キーボードの下」まで含んだ高さになる。
// その結果、全画面の重ね表示やダイアログの中身がキーボードに隠れる。
// visualViewport の実測値を :root に流しておけば、どの階層のCSSからも参照できる
// (確認ダイアログは body 直下に出るので、個々の画面が持つ変数では届かない)。

/// 一度だけ購読を始める。以後 --vv-h / --vv-top が :root で使える。
export function watchViewport(): void {
  if (typeof window === "undefined") return;
  const vv = window.visualViewport;
  const root = document.documentElement;
  const apply = () => {
    const h = vv ? vv.height : window.innerHeight;
    const top = vv ? vv.offsetTop : 0;
    root.style.setProperty("--vv-h", `${Math.round(h)}px`);
    root.style.setProperty("--vv-top", `${Math.round(top)}px`);
    // キーボードで隠れた高さ。下端に貼り付いたパネルをこのぶん持ち上げる。
    // 目的地の世界は自前の --vv-lift を持つ(日付ピッカーのときは持ち上げない
    // 特別扱いが要るため)。そちらはローカルの値が優先されるので干渉しない。
    root.style.setProperty(
      "--vv-lift",
      `${Math.max(0, Math.round(window.innerHeight - h - top))}px`,
    );
  };
  apply();
  if (!vv) return;
  vv.addEventListener("resize", apply);
  vv.addEventListener("scroll", apply);
  // フォーカス移動でキーボードの有無が変わることがある。
  document.addEventListener("focusin", apply);
  document.addEventListener("focusout", apply);
}
