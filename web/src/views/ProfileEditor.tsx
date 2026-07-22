import { useState } from "react";
import { PlayerProfile } from "../profile";
import { pushProfileEverywhere } from "../harbor";
import { STYLE_COLORS, TILE_STYLES, TILE_SYMBOLS, normalizeStyle, normalizeSymbol } from "../types";
import { PlayerAvatar, TileSymbolSvg } from "../symbols";
import { Modal, showToast } from "../overlays";
import { t } from "../i18n";

/// プレイヤーカードの編集。保存でローカルに書き、参加中の全ての港へも反映する。
export function ProfileEditor({ onClose }: { onClose: () => void }) {
  const [name, setName] = useState(PlayerProfile.name);
  const [styleToken, setStyleToken] = useState(normalizeStyle(PlayerProfile.styleToken));
  const [symbolToken, setSymbolToken] = useState(normalizeSymbol(PlayerProfile.symbolToken));
  const [resolve, setResolve] = useState(PlayerProfile.resolve);
  const [working, setWorking] = useState(false);

  const save = async () => {
    if (working) return;
    setWorking(true);
    PlayerProfile.save({ name, styleToken, symbolToken, resolve });
    await pushProfileEverywhere().catch(() => {});
    showToast(t("savedToast"));
    onClose();
  };

  const style = STYLE_COLORS[styleToken];

  return (
    <Modal onClose={onClose}>
      <>
        <h2 className="dialog-title">{t("playerCard")}</h2>

        {/* プレビュー: 入力がそのままカードになる。 */}
        <div
          className="player-card"
          style={{ background: style.bg, color: style.fg }}
        >
          <PlayerAvatar styleToken={styleToken} symbolToken={symbolToken} size={56} />
          <div className="player-card-texts">
            <div className="player-card-name">{name.trim() || t("sailor")}</div>
            {resolve.trim() && <div className="player-card-resolve">{resolve}</div>}
          </div>
        </div>

        <p className="section-label">{t("playerName")}</p>
        <input
          className="field"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={t("playerName")}
          maxLength={60}
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

        <p className="section-label">{t("resolve")}</p>
        <input
          className="field"
          value={resolve}
          onChange={(e) => setResolve(e.target.value)}
          placeholder={t("resolvePlaceholder")}
          maxLength={60}
        />

        <div style={{ height: 28 }} />
        <button className="primary-button" onClick={save} disabled={working}>
          {t("saveCard")}
        </button>
      </>
    </Modal>
  );
}
