import { useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
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
  freeColor,
  freeColorStyle,
  freeColorToken,
  nearestPccs,
  parseFreeColorToken,
  parsePccsToken,
  pccsToFreeColor,
  type FreeColorSelection,
} from "../pccs";
import { deleteItemPreservingHistory, saveItem, type UserData } from "../data";
import { publishCurrentMonth } from "../harbor";
import { TileSymbolSvg } from "../symbols";
import { DialogHeader, Modal, askConfirm, showToast } from "../overlays";
import { lang, t } from "../i18n";

const LEGACY_SEA_POSITIONS: Record<string, FreeColorSelection> = {
  midnight: { hue: 258, saturation: 0.65, value: 0.19 },
  coral: { hue: 12, saturation: 0.48, value: 0.94 },
  ink: { hue: 220, saturation: 0.05, value: 0.16 },
  seaGreen: { hue: 160, saturation: 0.54, value: 0.79 },
  violet: { hue: 244, saturation: 0.62, value: 0.72 },
  sunYellow: { hue: 48, saturation: 0.70, value: 1 },
};

function seaPositionFromToken(token: string): FreeColorSelection {
  const free = parseFreeColorToken(token);
  if (free) return free;
  const pccs = parsePccsToken(token);
  if (pccs) return pccsToFreeColor(pccs);
  return LEGACY_SEA_POSITIONS[token] ?? LEGACY_SEA_POSITIONS.midnight;
}

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
  const [styleToken, setStyleToken] = useState(initialStyleToken);
  const [seaColor, setSeaColor] = useState<FreeColorSelection>(
    seaPositionFromToken(initialStyleToken),
  );
  const activeColorPointer = useRef<number | null>(null);
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
  const customSelection = parseFreeColorToken(styleToken);
  const pccsGuide = nearestPccs(seaColor);
  const markerAngle = ((seaColor.hue - 90) * Math.PI) / 180;
  const markerLeft = 50 + Math.cos(markerAngle) * seaColor.saturation * 43;
  const markerTop = 50 + Math.sin(markerAngle) * seaColor.saturation * 43;

  const applySeaColor = (next: FreeColorSelection) => {
    const normalized = {
      hue: ((next.hue % 360) + 360) % 360,
      saturation: Math.min(1, Math.max(0, next.saturation)),
      value: Math.min(1, Math.max(0.18, next.value)),
    };
    setSeaColor(normalized);
    setStyleToken(freeColorToken(normalized));
  };

  const moveOnSeaChart = (
    event: ReactPointerEvent<HTMLDivElement>,
    allowIdle = false,
  ) => {
    if (!allowIdle && activeColorPointer.current !== event.pointerId) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const radius = Math.min(rect.width, rect.height) / 2;
    const x = event.clientX - (rect.left + rect.width / 2);
    const y = event.clientY - (rect.top + rect.height / 2);
    const distance = Math.min(radius, Math.hypot(x, y));
    const hue = ((Math.atan2(y, x) * 180) / Math.PI + 90 + 360) % 360;
    applySeaColor({ ...seaColor, hue, saturation: distance / radius });
  };

  const releaseColorPointer = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (activeColorPointer.current !== event.pointerId) return;
    activeColorPointer.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
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
                {customSelection
                  ? lang === "ja"
                    ? "彩りの海図"
                    : "Color sea chart"
                  : lang === "ja"
                    ? "Aftide 基本色"
                    : "Aftide preset"}
              </strong>
              <small>
                {customSelection
                  ? `${lang === "ja" ? "PCCS目安" : "PCCS guide"} ${pccsGuide.tone}${pccsGuide.hue}`
                  : lang === "ja"
                    ? "これまでの配色もそのまま使えます"
                    : "Existing colors remain available"}
              </small>
            </span>
          </div>

          <div className="color-sea-heading">
            <span>{lang === "ja" ? "小舟を動かして色を探す" : "Move the boat to find a color"}</span>
            <small>{lang === "ja" ? "中央ほど穏やか、外ほど鮮やか" : "Calm at the center, vivid at the edge"}</small>
          </div>

          <div
            className="color-sea-chart"
            role="slider"
            tabIndex={0}
            aria-label={lang === "ja" ? "彩りの海図" : "Color sea chart"}
            aria-valuetext={`${Math.round(seaColor.hue)}°, ${Math.round(seaColor.saturation * 100)}%`}
            onPointerDown={(event) => {
              event.preventDefault();
              activeColorPointer.current = event.pointerId;
              event.currentTarget.setPointerCapture(event.pointerId);
              moveOnSeaChart(event, true);
            }}
            onPointerMove={(event) => moveOnSeaChart(event)}
            onPointerUp={releaseColorPointer}
            onPointerCancel={releaseColorPointer}
            onKeyDown={(event) => {
              const hueStep = event.shiftKey ? 15 : 3;
              if (event.key === "ArrowLeft") {
                event.preventDefault();
                applySeaColor({ ...seaColor, hue: seaColor.hue - hueStep });
              } else if (event.key === "ArrowRight") {
                event.preventDefault();
                applySeaColor({ ...seaColor, hue: seaColor.hue + hueStep });
              } else if (event.key === "ArrowUp") {
                event.preventDefault();
                applySeaColor({ ...seaColor, saturation: seaColor.saturation + 0.04 });
              } else if (event.key === "ArrowDown") {
                event.preventDefault();
                applySeaColor({ ...seaColor, saturation: seaColor.saturation - 0.04 });
              }
            }}
          >
            <span className="color-sea-ring ring-one" />
            <span className="color-sea-ring ring-two" />
            <span className="color-sea-cross horizontal" />
            <span className="color-sea-cross vertical" />
            <span className="color-sea-compass north">N</span>
            <span className="color-sea-compass east">E</span>
            <span className="color-sea-compass south">S</span>
            <span className="color-sea-compass west">W</span>
            <span
              className="color-sea-boat"
              style={{
                left: `${markerLeft}%`,
                top: `${markerTop}%`,
                color: freeColorStyle(seaColor).fg,
                background: freeColor(seaColor),
              }}
            >
              <span aria-hidden="true">▲</span>
            </span>
          </div>

          <div className="color-light-control">
            <div>
              <span>{lang === "ja" ? "深海" : "Deep sea"}</span>
              <strong>{lang === "ja" ? "海の光" : "Sea light"}</strong>
              <span>{lang === "ja" ? "朝光" : "Morning light"}</span>
            </div>
            <input
              type="range"
              min="18"
              max="100"
              value={Math.round(seaColor.value * 100)}
              style={{
                background: `linear-gradient(90deg, ${freeColor({ ...seaColor, value: 0.18 })}, ${freeColor({ ...seaColor, value: 1 })})`,
              }}
              onChange={(event) =>
                applySeaColor({ ...seaColor, value: Number(event.target.value) / 100 })
              }
              aria-label={lang === "ja" ? "海の光" : "Sea light"}
            />
          </div>

          <div className="item-color-subsection">
            <span>{lang === "ja" ? "港の定番色" : "Harbor colors"}</span>
            <small>{lang === "ja" ? "迷った時はこちら" : "A quick safe choice"}</small>
          </div>
          <div className="item-color-presets" role="group" aria-label={lang === "ja" ? "港の定番色" : "Harbor colors"}>
            {TILE_STYLES.map((token) => {
              const colors = itemStyleColors(token);
              return (
                <button
                  key={token}
                  className={`swatch${styleToken === token ? " selected" : ""}`}
                  style={{ background: colors.bg }}
                  onClick={() => {
                    setStyleToken(token);
                    setSeaColor(seaPositionFromToken(token));
                  }}
                  aria-label={token}
                  aria-pressed={styleToken === token}
                />
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
