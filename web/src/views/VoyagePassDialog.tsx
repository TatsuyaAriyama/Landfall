import { useState } from "react";
import { useVoyagePass, openVoyagePassPortal, startVoyagePassCheckout } from "../billing";
import { t } from "../i18n";
import { DialogHeader, Modal } from "../overlays";
import { TileSymbolSvg } from "../symbols";

export function VoyagePassDialog({ onClose }: { onClose: () => void }) {
  const pass = useVoyagePass();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

  const openBilling = async () => {
    if (busy || pass.loading) return;
    setBusy(true);
    setError(false);
    try {
      await (pass.active ? openVoyagePassPortal() : startVoyagePassCheckout());
    } catch {
      setBusy(false);
      setError(true);
    }
  };

  return (
    <Modal onClose={onClose}>
      <>
        <DialogHeader title={t("voyagePass")} onBack={onClose} />
        <div className="voyage-pass-intro">
          <div className="voyage-pass-emblem" aria-hidden="true">
            <TileSymbolSvg symbol="compass" fg="#ffd84d" bg="#2c2a28" />
          </div>
          {!pass.active && (
            <ul>
              <li>{t("voyagePassBenefitMultiplayer")}</li>
              <li>{t("voyagePassBenefitSeas")}</li>
              <li>{t("voyagePassBenefitNavigator")}</li>
            </ul>
          )}
        </div>
        <div className="voyage-pass-card">
          <div className="voyage-pass-copy">
            <div className="voyage-pass-heading">
              <span>{t("voyagePass")}</span>
              <span className="voyage-pass-price">
                {pass.loading ? "…" : pass.active ? t("voyagePassActive") : t("voyagePassPrice")}
              </span>
            </div>
            {pass.active && <p>{t("voyagePassActiveDescription")}</p>}
            {pass.cancelAtPeriodEnd && <p className="voyage-pass-note">{t("voyagePassEnding")}</p>}
            <button className="chip voyage-pass-action" disabled={pass.loading || busy} onClick={() => void openBilling()}>
              {busy ? t("voyagePassOpening") : pass.active ? t("voyagePassManage") : t("voyagePassGet")}
            </button>
          </div>
        </div>
        {!pass.active && (
          <p className="voyage-pass-reassurance">
            <span aria-hidden="true">✓</span>
            {t("voyagePassReassurance")}
          </p>
        )}
        {error && <p className="harbor-error">{t("voyagePassError")}</p>}
      </>
    </Modal>
  );
}
