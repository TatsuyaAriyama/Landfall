import { useState } from "react";
import { useVoyagePass, openVoyagePassPortal, startVoyagePassCheckout } from "../billing";
import { t } from "../i18n";
import { DialogHeader, Modal } from "../overlays";

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
          <span className="voyage-pass-kicker">{t("voyagePassKicker")}</span>
          <h2>{pass.active ? t("voyagePassWelcomeBack") : t("voyagePassIntro")}</h2>
          {!pass.active && (
            <ul>
              <li>{t("voyagePassBenefitSeas")}</li>
              <li>{t("voyagePassBenefitNavigator")}</li>
              <li>{t("voyagePassBenefitReport")}</li>
            </ul>
          )}
        </div>
        <div className="voyage-pass-card">
          <div className="voyage-pass-mark" aria-hidden="true">◇</div>
          <div className="voyage-pass-copy">
            <div className="voyage-pass-heading">
              <span>{t("voyagePass")}</span>
              <span className="badge">
                {pass.loading ? "…" : pass.active ? t("voyagePassActive") : t("voyagePassPrice")}
              </span>
            </div>
            <p>{pass.active ? t("voyagePassActiveDescription") : t("voyagePassDescription")}</p>
            {pass.cancelAtPeriodEnd && <p className="voyage-pass-note">{t("voyagePassEnding")}</p>}
            <button className="chip voyage-pass-action" disabled={pass.loading || busy} onClick={() => void openBilling()}>
              {busy ? t("voyagePassOpening") : pass.active ? t("voyagePassManage") : t("voyagePassGet")}
            </button>
          </div>
        </div>
        {!pass.active && <p className="voyage-pass-reassurance">{t("voyagePassReassurance")}</p>}
        {error && <p className="harbor-error">{t("voyagePassError")}</p>}
      </>
    </Modal>
  );
}
