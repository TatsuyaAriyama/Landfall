import { useEffect, useState } from "react";
import { navigatorPose } from "../boat";
import type { PhoenixPose } from "./PhoenixModel";

// 目的地と航海中の甲板に立つ航海士のふるまい。
//
// 装いで選んだ姿はその人の「いつもの姿」だが、ずっと同じ仕草のままだと
// 立ち絵に見えてしまう。ときどき辺りを見渡させて、見張りをしている人が
// そこにいることにする。船は進んでいるのだから、当然あたりを見る。
//
// 見渡す姿を自分で選んでいる人には何もしない(すでに見渡している)。

/// 見渡しているあいだの長さ。PhoenixModel の見渡しの周期(約11秒)より
/// 少し短く、左右をひと巡りしきる前に元の姿へ戻る — 「一周する装置」ではなく
/// 「ふと目を上げた人」に見せたいので、切りのいいところで終わらせない。
const LOOKOUT_MS = 9_500;

/// 次に見渡すまでの間。一定間隔だと機械に見えるので、毎回ばらつかせる。
const GAP_MIN_MS = 20_000;
const GAP_MAX_MS = 38_000;

function gapMs(): number {
  return GAP_MIN_MS + Math.random() * (GAP_MAX_MS - GAP_MIN_MS);
}

/// 甲板の航海士がいま取るべき姿。装いで選んだ姿を基本に、ときどき見渡す。
/// enabled=false(動きを控える設定)のときは、選んだ姿のまま動かさない。
export function useNavigatorPose(enabled = true): PhoenixPose {
  const chosen = navigatorPose();
  const [looking, setLooking] = useState(false);

  useEffect(() => {
    if (!enabled || chosen === "lookout") return;
    let timer = 0;
    // 見渡し始めるまでは gapMs、見渡してから戻るまでは LOOKOUT_MS。
    const schedule = (toLookout: boolean) => {
      timer = window.setTimeout(
        () => {
          setLooking(toLookout);
          schedule(!toLookout);
        },
        toLookout ? gapMs() : LOOKOUT_MS,
      );
    };
    schedule(true);
    return () => {
      window.clearTimeout(timer);
      setLooking(false);
    };
  }, [enabled, chosen]);

  return looking ? "lookout" : chosen;
}
