import { useState } from "react";
import { signInWithGoogle } from "../auth";
import { BoatSvg, CoastSvg } from "../symbols";
import { t } from "../i18n";

// 「夜の入港」。星と月の空、全幅の水平線、静かに揺れる帆船、迎える海岸。
// harborTeal 一色の地に harborSand のフラット塗りのみ(グラデーション・影なし)。
// サインイン=入港、という iOS と同じ物語を、Web ではポスターの構図で描く。

const STARS: Array<{ top: string; left: string; size: number }> = [
  { top: "16%", left: "10%", size: 4 },
  { top: "8%", left: "24%", size: 3 },
  { top: "20%", left: "36%", size: 3 },
  { top: "6%", left: "52%", size: 4 },
  { top: "14%", left: "68%", size: 3 },
  { top: "9%", left: "83%", size: 4 },
  { top: "24%", left: "91%", size: 3 },
];

export function SignInView() {
  const [error, setError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);

  const signIn = async () => {
    if (working) return;
    setWorking(true);
    setError(null);
    try {
      // モバイル Safari はここでリダイレクトし、戻ってきたら自動でサインイン完了。
      // PC はポップアップで完結する。
      await signInWithGoogle();
    } catch (e) {
      const code = (e as { code?: string }).code ?? "";
      if (code !== "auth/popup-closed-by-user" && code !== "auth/cancelled-popup-request") {
        setError(t("signInFailed"));
      }
    } finally {
      setWorking(false);
    }
  };

  return (
    <div className="harbor-signin">
      <p className="harbor-topbar">{t("wordmark")}</p>

      {STARS.map((s, i) => (
        <span
          key={i}
          className="harbor-star"
          style={{ top: s.top, left: s.left, width: s.size, height: s.size }}
        />
      ))}
      <span className="harbor-moon" />

      <div className="harbor-content">
        <h1 className="harbor-enter">{t("signInEnter")}</h1>
        <p className="harbor-sync">{t("signInSync")}</p>
        <div className="harbor-actions">
          <button className="harbor-google" onClick={signIn} disabled={working}>
            {t("signInWithGoogle")}
          </button>
          {error && <p className="harbor-error">{error}</p>}
        </div>
      </div>

      <div className="harbor-sea">
        <div className="harbor-horizon" />
        <span className="harbor-glint harbor-glint-1" />
        <span className="harbor-glint harbor-glint-2" />
        <span className="harbor-glint harbor-glint-3" />
        <div className="harbor-boat-wrap">
          <div className="harbor-boat">
            <BoatSvg />
          </div>
        </div>
        <div className="harbor-coast">
          <CoastSvg />
        </div>
      </div>
    </div>
  );
}
