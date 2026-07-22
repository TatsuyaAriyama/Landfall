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

  const save = async () => {
    const trimmed = name.trim().slice(0, 60);
    if (!trimmed || working) return;
    setWorking(true);
    await saveItem(uid, {
      id: item?.id,
      name: trimmed,
      styleToken,
      symbolToken,
      sortOrder: item?.sortOrder ?? nextSortOrder,
      createdAt: item?.createdAt,
    });
    onClose();
  };

  const remove = async () => {
    if (!item || working) return;
    if (!confirm(t("deleteItemConfirm"))) return;
    setWorking(true);
    await deleteItemDeep(uid, item.id, data);
    onClose();
  };

  return (
    <div className="overlay" onClick={onClose}>
      <div className="dialog" onClick={(e) => e.stopPropagation()}>
        <h2 className="dialog-title">{item ? t("editItem") : t("newItem")}</h2>

        <p className="section-label">{t("name")}</p>
        <input
          className="field"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={t("namePlaceholder")}
          maxLength={60}
          autoFocus
        />

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

        <div style={{ height: 28 }} />
        <button className="primary-button" onClick={save} disabled={!name.trim() || working}>
          {t("save")}
        </button>
        {item && (
          <button className="danger-button" onClick={remove} disabled={working}>
            {t("deleteItem")}
          </button>
        )}
      </div>
    </div>
  );
}
