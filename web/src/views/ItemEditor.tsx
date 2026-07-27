import { useState } from "react";
import {
  TILE_STYLES,
  TILE_SYMBOLS,
  itemStyleColors,
  normalizeItemStyle,
  normalizeSymbol,
  trimAll,
  type StudyItem,
} from "../types";
import {
  PCCS_HUES,
  PCCS_TONES,
  parsePccsToken,
  pccsColor,
  pccsToken,
  type PccsToneId,
} from "../pccs";
import { deleteItemPreservingHistory, saveItem, type UserData } from "../data";
import { publishCurrentMonth } from "../harbor";
import { TileSymbolSvg } from "../symbols";
import { DialogHeader, Modal, askConfirm, showToast } from "../overlays";
import { lang, t } from "../i18n";

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
  const initialStyleToken = normalizeItemStyle(item?.styleToken ?? "midnight");
  const initialPccs = parsePccsToken(initialStyleToken);
  const [styleToken, setStyleToken] = useState(initialStyleToken);
  const [pccsTone, setPccsTone] = useState<PccsToneId>(initialPccs?.tone ?? "v");
  const [pccsHue, setPccsHue] = useState(initialPccs?.hue ?? 2);
  const [symbolToken, setSymbolToken] = useState(normalizeSymbol(item?.symbolToken ?? "compass"));
  const [working, setWorking] = useState(false);
  const orderedItems = [...data.items].sort(
    (a, b) => a.sortOrder - b.sortOrder || a.createdAt.getTime() - b.createdAt.getTime(),
  );
  const itemIndex = item
    ? orderedItems.findIndex((candidate) => candidate.id === item.id)
    : -1;

  const trimmedName = trimAll(name);
  // 他の項目(自分自身は除く)と大小文字・前後空白(全角含む)を無視して同名かどうか。
  const isDuplicateName =
    trimmedName.length > 0 &&
    data.items.some(
      (other) =>
        other.id !== item?.id &&
        trimAll(other.name).toLowerCase() === trimmedName.toLowerCase(),
    );
  const saveDisabled = !trimmedName || isDuplicateName || working;

  const save = async () => {
    const trimmed = trimmedName.slice(0, 60);
    if (!trimmed || isDuplicateName || working) return;
    setWorking(true);
    try {
      await saveItem(uid, {
        id: item?.id,
        name: trimmed,
        styleToken,
        symbolToken,
        sortOrder: item?.sortOrder ?? nextSortOrder,
        createdAt: item?.createdAt,
      });
      // 既存項目の名前・見た目の変更は、港へ共有済みの月間記録(非正規化された
      // itemName/styleToken/symbolToken)にも必ず反映する。
      if (item) {
        await publishCurrentMonth({
          items: data.items.map((i) =>
            i.id === item.id ? { ...i, name: trimmed, styleToken, symbolToken } : i,
          ),
          sessions: data.sessions,
          days: data.days,
        }).catch(() => {});
      }
      showToast(t("savedToast"));
      onClose();
    } catch {
      showToast(t("errGeneric"));
      setWorking(false);
    }
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
    try {
      await deleteItemPreservingHistory(uid, item.id, data);
      onClose();
    } catch {
      showToast(t("errGeneric"));
      setWorking(false);
    }
  };

  /// グリッドの並び替え。隣の項目と sortOrder を入れ替える。
  const move = async (dir: -1 | 1) => {
    if (!item || working) return;
    const target = orderedItems[itemIndex + dir];
    if (!target) return;
    setWorking(true);
    try {
      await saveItem(uid, { ...item, id: item.id, sortOrder: target.sortOrder });
      await saveItem(uid, { ...target, id: target.id, sortOrder: item.sortOrder });
      onClose();
    } catch {
      showToast(t("errGeneric"));
      setWorking(false);
    }
  };

  const previewStyle = itemStyleColors(styleToken);
  const selectedPccs = parsePccsToken(styleToken);
  const selectedTone = PCCS_TONES.find((tone) => tone.id === pccsTone) ?? PCCS_TONES[0];

  const choosePccsTone = (tone: PccsToneId) => {
    setPccsTone(tone);
    setStyleToken(pccsToken(tone, pccsHue));
  };

  const choosePccsHue = (hue: number) => {
    setPccsHue(hue);
    setStyleToken(pccsToken(pccsTone, hue));
  };

  return (
    <Modal onClose={onClose}>
      <>
        <DialogHeader title={item ? t("editItem") : t("newItem")} onBack={onClose} />

        {/* プレビュー: 選んだ色×シンボルが、そのまま今日の画面のタイルになる。 */}
        <div style={{ display: "flex", alignItems: "center", gap: 14, marginTop: 4 }}>
          <div
            className="tile-art"
            style={{ background: previewStyle.bg, width: 52, aspectRatio: "1" }}
          >
            <TileSymbolSvg symbol={symbolToken} fg={previewStyle.fg} bg={previewStyle.bg} />
          </div>
          <div className="tile-name-text" style={{ fontSize: 17 }}>
            {trimmedName || t("namePlaceholder")}
          </div>
        </div>

        <p className="section-label">{t("name")}</p>
        <input
          className={`field${isDuplicateName ? " field-error" : ""}`}
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={t("namePlaceholder")}
          maxLength={60}
          // 既存項目を開いた瞬間にスマホのキーボードで色・シンボルが隠れないよう、
          // 自動フォーカスは名前入力が主目的の新規作成だけにする。
          autoFocus={!item}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing && !saveDisabled) void save();
          }}
        />
        {isDuplicateName && <p className="field-error-text">{t("duplicateItemName")}</p>}

        <p className="section-label">{t("color")}</p>
        <div className="item-color-picker">
          <div className="item-color-current" aria-live="polite">
            <span className="item-color-current-swatch" style={{ background: previewStyle.bg }} />
            <span>
              <strong>
                {selectedPccs
                  ? `PCCS ${selectedPccs.tone}${selectedPccs.hue}`
                  : lang === "ja"
                    ? "Aftide 基本色"
                    : "Aftide preset"}
              </strong>
              <small>
                {selectedPccs
                  ? `${lang === "ja" ? selectedTone.nameJa : selectedTone.nameEn} · H${selectedPccs.hue}`
                  : lang === "ja"
                    ? "これまでの配色もそのまま使えます"
                    : "Existing colors remain available"}
              </small>
            </span>
          </div>

          <div className="item-color-subsection">
            <span>{lang === "ja" ? "基本色" : "Presets"}</span>
          </div>
          <div className="item-color-presets" role="group" aria-label={lang === "ja" ? "基本色" : "Presets"}>
            {TILE_STYLES.map((token) => {
              const colors = itemStyleColors(token);
              return (
                <button
                  key={token}
                  className={`swatch${styleToken === token ? " selected" : ""}`}
                  style={{ background: colors.bg }}
                  onClick={() => setStyleToken(token)}
                  aria-label={token}
                  aria-pressed={styleToken === token}
                />
              );
            })}
          </div>

          <div className="item-color-subsection">
            <span>PCCS {lang === "ja" ? "トーン" : "tone"}</span>
            <small>{lang === "ja" ? "雰囲気を選ぶ" : "Choose a mood"}</small>
          </div>
          <div className="pccs-tone-strip" role="group" aria-label="PCCS tone">
            {PCCS_TONES.map((tone) => (
              <button
                key={tone.id}
                className={pccsTone === tone.id ? "selected" : ""}
                onClick={() => choosePccsTone(tone.id)}
                aria-pressed={pccsTone === tone.id}
              >
                <span
                  className="pccs-tone-dot"
                  style={{ background: pccsColor({ tone: tone.id, hue: pccsHue }) }}
                />
                <span>
                  <strong>{tone.id}</strong>
                  <small>{lang === "ja" ? tone.nameJa : tone.nameEn}</small>
                </span>
              </button>
            ))}
          </div>

          <div className="item-color-subsection">
            <span>{lang === "ja" ? "24色相" : "24 hues"}</span>
            <small>{lang === "ja" ? "色を選ぶ" : "Choose a hue"}</small>
          </div>
          <div className="pccs-hue-grid" role="group" aria-label="PCCS 24 hues">
            {PCCS_HUES.map((hue) => {
              const selected =
                selectedPccs?.tone === pccsTone && selectedPccs.hue === hue.number;
              const background = pccsColor({ tone: pccsTone, hue: hue.number });
              return (
                <button
                  key={hue.number}
                  className={selected ? "selected" : ""}
                  style={{ background }}
                  onClick={() => choosePccsHue(hue.number)}
                  aria-label={`PCCS ${pccsTone}${hue.number}`}
                  aria-pressed={selected}
                >
                  <span style={{ color: itemStyleColors(pccsToken(pccsTone, hue.number)).fg }}>
                    {hue.number}
                  </span>
                </button>
              );
            })}
          </div>
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
            <button
              className="chip"
              onClick={() => move(-1)}
              disabled={working || itemIndex <= 0}
            >
              ← {t("moveEarlier")}
            </button>
            <button
              className="chip"
              onClick={() => move(1)}
              disabled={working || itemIndex < 0 || itemIndex >= orderedItems.length - 1}
            >
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
