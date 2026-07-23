import { useState } from "react";
import { signOut } from "firebase/auth";
import { auth } from "../firebase";
import { deleteEverything } from "../harbor";
import type { UserData } from "../data";
import { Modal, askConfirm } from "../overlays";
import { LANGUAGE_KEY, t } from "../i18n";

export const THEME_KEY = "appTheme";

/// 外観の反映。system は data-theme を外して prefers-color-scheme に任せる。
export function applyTheme(value: string | null) {
  const root = document.documentElement;
  if (value === "light" || value === "dark") {
    root.setAttribute("data-theme", value);
  } else {
    root.removeAttribute("data-theme");
  }
}

/// 設定。言語・外観・船・データ・アカウント。
export function SettingsDialog({
  data,
  onClose,
}: {
  data: UserData;
  onClose: () => void;
}) {
  const [language, setLanguage] = useState(localStorage.getItem(LANGUAGE_KEY) ?? "system");
  const [theme, setTheme] = useState(localStorage.getItem(THEME_KEY) ?? "system");
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const download = (content: string, filename: string, type: string) => {
    const url = URL.createObjectURL(new Blob([content], { type }));
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  };

  const exportJSON = () => {
    download(
      JSON.stringify(
        {
          items: data.items,
          sessions: data.sessions,
          days: data.days,
          destinations: data.destinations,
        },
        null,
        2,
      ),
      "landfall-export.json",
      "application/json",
    );
  };

  const exportCSV = () => {
    const itemById = new Map(data.items.map((i) => [i.id, i.name]));
    const esc = (v: string) => `"${v.replace(/"/g, '""')}"`;
    const rows = [...data.sessions]
      .sort((a, b) => a.date.getTime() - b.date.getTime())
      .map((s) =>
        [
          s.date.toISOString(),
          esc(s.itemUUID ? (itemById.get(s.itemUUID) ?? "") : ""),
          String(s.minutes),
          esc(s.note ?? ""),
        ].join(","),
      );
    download(
      ["date,item,minutes,note", ...rows].join("\n"),
      "landfall-sessions.csv",
      "text/csv",
    );
  };

  const pickLanguage = (value: string) => {
    setLanguage(value);
    if (value === "system") localStorage.removeItem(LANGUAGE_KEY);
    else localStorage.setItem(LANGUAGE_KEY, value);
    // 言語辞書はモジュール読み込み時に決まるので、再読込で反映する。
    window.location.reload();
  };

  const pickTheme = (value: string) => {
    setTheme(value);
    if (value === "system") localStorage.removeItem(THEME_KEY);
    else localStorage.setItem(THEME_KEY, value);
    applyTheme(value === "system" ? null : value);
  };

  const deleteAccount = async () => {
    if (deleting) return;
    const ok = await askConfirm({
      title: t("deleteAccount"),
      message: t("deleteAccountConfirm"),
      confirmLabel: t("deleteAccount"),
      danger: true,
    });
    if (!ok) return;
    setDeleting(true);
    setError(null);
    try {
      await deleteEverything();
      await auth.currentUser?.delete();
      onClose();
    } catch {
      setError(t("deleteFailed"));
      setDeleting(false);
    }
  };

  const pill = (selected: boolean, label: string, onClick: () => void) => (
    <button className={`chip${selected ? " selected" : ""}`} onClick={onClick}>
      {label}
    </button>
  );

  return (
    <Modal onClose={onClose}>
      <>
        <h2 className="dialog-title">{t("settings")}</h2>

        <p className="section-label">{t("language")}</p>
        <div className="chip-row">
          {pill(language === "system", t("system"), () => pickLanguage("system"))}
          {pill(language === "ja", "日本語", () => pickLanguage("ja"))}
          {pill(language === "en", "English", () => pickLanguage("en"))}
        </div>

        <p className="section-label">{t("appearance")}</p>
        <div className="chip-row">
          {pill(theme === "system", t("system"), () => pickTheme("system"))}
          {pill(theme === "light", t("light"), () => pickTheme("light"))}
          {pill(theme === "dark", t("dark"), () => pickTheme("dark"))}
        </div>

        <p className="section-label">{t("dataSection")}</p>
        <div className="chip-row">
          <button className="chip" onClick={exportJSON}>
            {t("exportJSON")}
          </button>
          <button className="chip" onClick={exportCSV}>
            {t("exportCSV")}
          </button>
        </div>

        <p className="section-label">{t("account")}</p>
        {auth.currentUser?.email && (
          <p className="page-sub" style={{ marginBottom: 10 }}>
            {auth.currentUser.email}
          </p>
        )}
        <div className="rows">
          <button
            className="row row-button"
            onClick={async () => {
              const ok = await askConfirm({
                title: t("signOut"),
                message: t("signOutConfirm"),
                confirmLabel: t("signOut"),
              });
              if (!ok) return;
              void signOut(auth);
              onClose();
            }}
          >
            <div className="row-main">
              <div className="row-title">{t("signOut")}</div>
            </div>
          </button>
          <button className="row row-button" onClick={deleteAccount} disabled={deleting}>
            <div className="row-main">
              <div className="row-title danger-text">{t("deleteAccount")}</div>
            </div>
          </button>
        </div>
        {error && <p className="harbor-error">{error}</p>}
      </>
    </Modal>
  );
}
