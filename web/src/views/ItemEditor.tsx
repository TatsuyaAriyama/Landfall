import { useState } from "react";
import {
  STYLE_COLORS,
  TILE_STYLES,
  TILE_SYMBOLS,
  normalizeStyle,
  normalizeSymbol,
  type StudyItem,
} from "../types";
import { deleteItemDeep, saveItem, type UserData } from "../data";
import { TileSymbolSvg } from "../symbols";
import { Modal, askConfirm, showToast } from "../overlays";
import { t } from "../i18n";

export function ItemEditor({
  uid,
  item,
  nextSortOrder,
  data,
  onClose,
}: {
  uid: string;
  item: StudyItem | null;
  nextSortOrder: number;
  data: UserData;
  onClose: () => void;
}) {
  const [name, setName] = useState(item?.name ?? "");
  const [styleToken, setStyleToken] = useState(normalizeStyle(item?.styleToken ?? "midnight"));
  const [symbolToken, setSymbolToken] = useState(normalizeSymbol(item?.symbolToken ?? "compass"));
  const [working, setWorking] = useState(false);

  const trimmedName = name.trim();
  // 他の項目(自分自身は除く)と大小文字・前後空白を無視して同名かどうか(iOSと同じ判定)。
  const isDuplicateName =
    trimmedName.length > 0 &&
    data.items.some(
      (other) =>
        other.id !== item?.id &&
        other.name.trim().toLowerCase() === trimmedName.toLowerCase(),
    );
  const saveDisabled = !trimmedName || isDuplicateName || working;

  const save = async () => {
    const trimmed = trimmedName.slice(0, 60);
    if (!trimmed || isDuplicateName || working) return;
    setWorking(true);
    await saveItem(uid, {
      id: item?.id,
      name: trimmed,
      styleToken,
      symbolToken,
      sortOrder: item?.sortOrder ?? nextSortOrder,
      createdAt: item?.createdAt,
    });
    showToast(t("savedToast"));
    onClose();
  };

  const remove = async () => {
    if (!item || working) return;
    if (
      !(await askConfirm({
        title: t("deleteItemConfirm"),
        confirmLabel: t("delete"),
        danger: true,
      }))
    ) {
      return;
    }
    setWorking(true);
    await deleteItemDeep(uid, item.id, data);
    onClose();
  };

  /// グリッドの並び替え。隣の項目と sortOrder を入れ替える。
  const move = async (dir: -1 | 1) => {
    if (!item || working) return;
    const idx = data.items.findIndex((i) => i.id === item.id);
    const target = data.items[idx + dir];
    if (!target) return;
    setWorking(true);
    await saveItem(uid, { ...item, id: item.id, sortOrder: target.sortOrder });
    await saveItem(uid, { ...target, id: target.id, sortOrder: item.sortOrder });
    onClose();
  };

  return (
    <Modal onClose={onClose}>
      <>
        <h2 className="dialog-title">{item ? t("editItem") : t("newItem")}</h2>

        <p className="section-label">{t("name")}</p>
        <input
          className={`field${isDuplicateName ? " field-error" : ""}`}
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={t("namePlaceholder")}
          maxLength={60}
          autoFocus
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing && !saveDisabled) void save();
          }}
        />
        {isDuplicateName && <p className="field-error-text">{t("duplicateItemName")}</p>}

        <p className="section-label">{t("color")}</p>
        <div className="chip-row">
          {TILE_STYLES.map((token) => (
            <button
              key={token}
              className={`swatch${styleToken === token ? " selected" : ""}`}
              style={{ background: STYLE_COLORS[token].bg }}
              onClick={() => setStyleToken(token)}
              aria-label={token}
            />
          ))}
        </div>

        <p className="section-label">{t("symbol")}</p>
        <div className="chip-row">
          {TILE_SYMBOLS.map((token) => (
            <button
              key={token}
              className={`symbol-pick${symbolToken === token ? " selected" : ""}`}
              onClick={() => setSymbolToken(token)}
              aria-label={token}
            >
              <TileSymbolSvg symbol={token} fg="var(--ink)" bg="var(--paper)" />
            </button>
          ))}
        </div>

        {item && (
          <div className="chip-row" style={{ marginTop: 24 }}>
            <button className="chip" onClick={() => move(-1)} disabled={working}>
              ← {t("moveEarlier")}
            </button>
            <button className="chip" onClick={() => move(1)} disabled={working}>
              {t("moveLater")} →
            </button>
          </div>
        )}

        <div style={{ height: 28 }} />
        <button className="primary-button" onClick={save} disabled={saveDisabled}>
          {t("save")}
        </button>
        {item && (
          <button className="danger-button" onClick={remove} disabled={working}>
            {t("deleteItem")}
          </button>
        )}
      </>
    </Modal>
  );
}
