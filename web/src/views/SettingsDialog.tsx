import { useState } from "react";
import { signOut } from "firebase/auth";
import { auth } from "../firebase";
import { deleteEverything } from "../harbor";
import type { UserData } from "../data";
import { DialogHeader, Modal, askConfirm } from "../overlays";
import { LANGUAGE_KEY, t, tf } from "../i18n";
import { STYLE_COLORS, normalizeStyle, normalizeSymbol } from "../types";
import { TileSymbolSvg } from "../symbols";
import { ItemEditor } from "./ItemEditor";

/// 設定。言語・データ・アカウント。
export function SettingsDialog({
  uid,
  data,
  onClose,
}: {
  uid: string;
  data: UserData;
  onClose: () => void;
}) {
  const [language, setLanguage] = useState(localStorage.getItem(LANGUAGE_KEY) ?? "system");
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState<"main" | "items">("main");
  // undefined=一覧、null=新規、string=その項目を編集。
  const [editingItemId, setEditingItemId] = useState<string | null | undefined>();

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
          schemaVersion: 2,
          exportedAt: new Date().toISOString(),
          items: data.items,
          sessions: data.sessions,
          days: data.days,
          voyageLogs: data.voyageLogs,
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
          esc(s.itemUUID ? (itemById.get(s.itemUUID) ?? s.itemName ?? "") : (s.itemName ?? "")),
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

  const exportVoyageLogsCSV = () => {
    const esc = (value: string) => `"${value.replace(/"/g, '""')}"`;
    const rows = [...data.voyageLogs]
      .sort((a, b) => a.date.getTime() - b.date.getTime())
      .map((log) => [log.id, esc(log.body), log.updatedAt.toISOString()].join(","));
    download(
      ["date,body,updatedAt", ...rows].join("\n"),
      "landfall-voyage-logs.csv",
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

  if (editingItemId !== undefined) {
    const item =
      editingItemId === null
        ? null
        : data.items.find((candidate) => candidate.id === editingItemId) ?? null;
    return (
      <ItemEditor
        uid={uid}
        item={item}
        nextSortOrder={
          data.items.length === 0
            ? 0
            : Math.max(...data.items.map((candidate) => candidate.sortOrder)) + 1
        }
        data={data}
        onClose={() => setEditingItemId(undefined)}
      />
    );
  }

  if (page === "items") {
    const orderedItems = [...data.items].sort(
      (a, b) => a.sortOrder - b.sortOrder || a.createdAt.getTime() - b.createdAt.getTime(),
    );
    return (
      <Modal onClose={() => setPage("main")}>
        <>
          <DialogHeader title={t("workItemsSettings")} onBack={() => setPage("main")} />
          <p className="settings-items-hint">{t("workItemsSettingsHint")}</p>
          {orderedItems.length === 0 ? (
            <p className="empty-note">{t("emptyToday")}</p>
          ) : (
            <div className="rows settings-item-rows">
              {orderedItems.map((item) => {
                const style = STYLE_COLORS[normalizeStyle(item.styleToken)];
                return (
                  <button
                    key={item.id}
                    type="button"
                    className="row row-button settings-item-row"
                    onClick={() => setEditingItemId(item.id)}
                    aria-label={tf(t("editNamedItem"), { name: item.name })}
                  >
                    <span className="row-tile" style={{ background: style.bg }}>
                      <TileSymbolSvg
                        symbol={normalizeSymbol(item.symbolToken)}
                        fg={style.fg}
                        bg={style.bg}
                      />
                    </span>
                    <span className="row-main">
                      <span className="row-title">{item.name}</span>
                    </span>
                    <span className="settings-row-chevron" aria-hidden="true">›</span>
                  </button>
                );
              })}
            </div>
          )}
          <div style={{ height: 20 }} />
          <button
            type="button"
            className="primary-button"
            onClick={() => setEditingItemId(null)}
          >
            {t("newItem")}
          </button>
        </>
      </Modal>
    );
  }

  return (
    <Modal onClose={onClose}>
      <>
        <DialogHeader title={t("settings")} onBack={onClose} />

        <p className="section-label">{t("language")}</p>
        <div className="chip-row">
          {pill(language === "system", t("system"), () => pickLanguage("system"))}
          {pill(language === "ja", "日本語", () => pickLanguage("ja"))}
          {pill(language === "en", "English", () => pickLanguage("en"))}
        </div>

        <p className="section-label">{t("workItemsSettings")}</p>
        <div className="rows">
          <button
            type="button"
            className="row row-button settings-section-row"
            onClick={() => setPage("items")}
          >
            <div className="row-main">
              <div className="row-title">{t("workItemsSettings")}</div>
              <div className="row-sub">
                {tf(t("workItemsCount"), { count: data.items.length })}
              </div>
            </div>
            <span className="settings-row-chevron" aria-hidden="true">›</span>
          </button>
        </div>

        <p className="section-label">{t("dataSection")}</p>
        <div className="chip-row">
          <button className="chip" onClick={exportJSON}>
            {t("exportJSON")}
          </button>
          <button className="chip" onClick={exportCSV}>
            {t("exportCSV")}
          </button>
          <button className="chip" onClick={exportVoyageLogsCSV}>
            {t("exportVoyageLogsCSV")}
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
