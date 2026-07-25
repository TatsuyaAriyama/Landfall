import { useEffect, useState } from "react";
import type { PhoenixPose } from "./PhoenixModel";

// 目的地と航海中の甲板に立つ航海士のふるまい。
//
// 甲板の航海士は見張りであって、着せ替えの見本ではない。装いで選んだ姿は
// ここでは使わない — あれは装いタブの中で自分の航海士を眺めるためのもので、
// 進んでいる船の上で灯を掲げ続けたり一息つき続けたりするのは姿として嘘になる。
//
// だから甲板では待機を基本にして、ときどき辺りを見渡す。船は進んでいるの
// だから、当然あたりを見る。ずっと同じ仕草だと立ち絵に見えてしまうので、
// その息継ぎでもある。

/// 甲板での基本の姿。
const BASE_POSE: PhoenixPose = "idle";

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

/// 甲板の航海士がいま取るべき姿。待機を基本に、ときどき見渡す。
/// enabled=false(動きを控える設定)のときは、待機のまま動かさない。
///
/// override は、世界の側に「いまはこの姿でいてほしい」事情があるときに渡す
/// (休憩中の sit など)。そのあいだ見渡しは差し込まない — 休んでいる人が
/// ときどき立ち上がって見張りを始めては、休憩に見えない。
export function useNavigatorPose(
  enabled = true,
  override: PhoenixPose | null = null,
): PhoenixPose {
  const [looking, setLooking] = useState(false);

  useEffect(() => {
    if (!enabled || override) return;
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
  }, [enabled, override]);

  if (override) return override;
  return looking ? "lookout" : BASE_POSE;
}
