import { useState } from "react";
import { signInWithPopup } from "firebase/auth";
import { auth, googleProvider } from "../firebase";
import { HarborScene } from "../symbols";
import { t } from "../i18n";

// iOS の SignInView と同じ構図。harborTeal 地に港の情景を描き、
// 「サインイン=入港」を表す。左寄せ・ボタンは下寄せ。
export function SignInView() {
  const [error, setError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);

  const signIn = async () => {
    if (working) return;
    setWorking(true);
    setError(null);
    try {
      await signInWithPopup(auth, googleProvider);
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
      <div className="harbor-signin-inner">
        <div className="harbor-scene-wrap">
          <HarborScene />
        </div>

        <p className="harbor-wordmark">{t("wordmark")}</p>
        <p className="harbor-enter">{t("signInEnter")}</p>
        <p className="harbor-sync">{t("signInSync")}</p>

        <div className="harbor-actions">
          <button
            className="harbor-google"
            onClick={signIn}
            disabled={working}
          >
            <span className="harbor-google-g">G</span>
            {t("signInWithGoogle")}
          </button>
        </div>

        {error && <p className="harbor-error">{error}</p>}
      </div>
    </div>
  );
}
