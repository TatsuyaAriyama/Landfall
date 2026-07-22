import { useState } from "react";
import { signInWithPopup } from "firebase/auth";
import { auth, googleProvider } from "../firebase";
import { BrandMark } from "../symbols";
import { t } from "../i18n";

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
      // ポップアップを閉じただけならエラー表示しない。
      const code = (e as { code?: string }).code ?? "";
      if (code !== "auth/popup-closed-by-user" && code !== "auth/cancelled-popup-request") {
        setError(t("signInFailed"));
      }
    } finally {
      setWorking(false);
    }
  };

  return (
    <div className="signin">
      <BrandMark size={96} />
      <h1 className="signin-title">{t("appName")}</h1>
      <p className="signin-tagline">
        {t("tagline")
          .split("\n")
          .map((line, i) => (
            <span key={i}>
              {i > 0 && <br />}
              {line}
            </span>
          ))}
      </p>
      <button className="primary-button" onClick={signIn} disabled={working}>
        {t("signInWithGoogle")}
      </button>
      <p className="page-sub">{t("signInNote")}</p>
      {error && <p className="error-text">{error}</p>}
    </div>
  );
}
