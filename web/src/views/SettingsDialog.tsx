import { useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { signOut } from "firebase/auth";
import { auth } from "../firebase";
import { deleteEverything } from "../harbor";
import type { UserData } from "../data";
import { DialogHeader, Modal, askConfirm } from "../overlays";
import { LANGUAGE_KEY, t, tf } from "../i18n";
import { STYLE_COLORS, normalizeStyle, normalizeSymbol } from "../types";
import { TileSymbolSvg } from "../symbols";
import { ItemEditor } from "./ItemEditor";
import { storage } from "../storage";
import {
  DEFAULT_HARBOR_CONTROL_SETTINGS,
  HARBOR_CONTROL_SIZE_MAX,
  HARBOR_CONTROL_SIZE_MIN,
  loadHarborControlSettings,
  saveHarborControlSettings,
  type HarborControlSettings,
} from "../harborControls";

function HarborControlEditor({ onBack }: { onBack: () => void }) {
  const [settings, setSettings] = useState(loadHarborControlSettings);
  const activePointer = useRef<number | null>(null);

  const update = (next: HarborControlSettings) => {
    const saved = saveHarborControlSettings(next);
    setSettings(saved);
  };

  const moveControl = (event: ReactPointerEvent<HTMLDivElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    update({
      ...settings,
      x: ((event.clientX - rect.left) / rect.width) * 100,
      y: ((event.clientY - rect.top) / rect.height) * 100,
    });
  };

  const release = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (activePointer.current !== event.pointerId) return;
    activePointer.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  const previewSize = 34 + ((settings.size - HARBOR_CONTROL_SIZE_MIN) / (
    HARBOR_CONTROL_SIZE_MAX - HARBOR_CONTROL_SIZE_MIN
  )) * 20;

  return (
    <Modal onClose={onBack}>
      <>
        <DialogHeader title={t("harborControlsSettings")} onBack={onBack} />
        <p className="settings-items-hint">{t("harborControlsSettingsHint")}</p>
        <div
          className="harbor-control-editor-preview"
          role="application"
          aria-label={t("harborControlsPlacement")}
          onPointerDown={(event) => {
            event.preventDefault();
            activePointer.current = event.pointerId;
            event.currentTarget.setPointerCapture(event.pointerId);
            moveControl(event);
          }}
          onPointerMove={(event) => {
            if (activePointer.current !== event.pointerId) return;
            event.preventDefault();
            moveControl(event);
          }}
          onPointerUp={release}
          onPointerCancel={release}
        >
          <div className="harbor-control-editor-horizon" aria-hidden="true" />
          <div
            className="harbor-control-editor-stick"
            aria-hidden="true"
            style={{
              left: `${settings.x}%`,
              top: `${settings.y}%`,
              width: previewSize,
              height: previewSize,
            }}
          >
            <span />
          </div>
          <span className="harbor-control-editor-drag-hint">
            {t("harborControlsDrag")}
          </span>
        </div>

        <label className="harbor-control-size-field">
          <span>
            <strong>{t("harborControlsSize")}</strong>
            <output>{settings.size}px</output>
          </span>
          <input
            type="range"
            min={HARBOR_CONTROL_SIZE_MIN}
            max={HARBOR_CONTROL_SIZE_MAX}
            step={2}
            value={settings.size}
            onChange={(event) =>
              update({ ...settings, size: Number(event.currentTarget.value) })
            }
          />
          <span className="harbor-control-size-labels" aria-hidden="true">
            <span>{t("small")}</span>
            <span>{t("large")}</span>
          </span>
        </label>

        <button
          type="button"
          className="quiet-button harbor-control-reset"
          onClick={() => update(DEFAULT_HARBOR_CONTROL_SETTINGS)}
        >
          {t("restoreDefault")}
        </button>
      </>
    </Modal>
  );
}

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
  const [language, setLanguage] = useState(storage.get(LANGUAGE_KEY) ?? "system");
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState<"main" | "items" | "harborControls">("main");
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
      `aftide-${new Date().toISOString().slice(0, 10)}.json`,
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
      `\ufeff${["date,item,minutes,note", ...rows].join("\n")}`,
      `aftide-sessions-${new Date().toISOString().slice(0, 10)}.csv`,
      "text/csv;charset=utf-8",
    );
  };

  const exportVoyageLogsCSV = () => {
    const esc = (value: string) => `"${value.replace(/"/g, '""')}"`;
    const rows = [...data.voyageLogs]
      .sort((a, b) => a.date.getTime() - b.date.getTime())
      .map((log) => [log.id, esc(log.body), log.updatedAt.toISOString()].join(","));
    download(
      `\ufeff${["date,body,updatedAt", ...rows].join("\n")}`,
      `aftide-voyage-logs-${new Date().toISOString().slice(0, 10)}.csv`,
      "text/csv;charset=utf-8",
    );
  };

  const pickLanguage = (value: string) => {
    setLanguage(value);
    if (value === "system") storage.remove(LANGUAGE_KEY);
    else storage.set(LANGUAGE_KEY, value);
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

  if (page === "harborControls") {
    return <HarborControlEditor onBack={() => setPage("main")} />;
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

        <p className="section-label">{t("harborSection")}</p>
        <div className="rows">
          <button
            type="button"
            className="row row-button settings-section-row"
            onClick={() => setPage("harborControls")}
          >
            <div className="row-main">
              <div className="row-title">{t("harborControlsSettings")}</div>
              <div className="row-sub">{t("harborControlsSettingsSummary")}</div>
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
