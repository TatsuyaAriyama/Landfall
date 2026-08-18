import { DialogHeader, Modal } from "../overlays";
import { t } from "../i18n";
import { TileSymbolSvg } from "../symbols";
import type { TileSymbolToken } from "../types";

const HELP_CHAPTERS: Array<{
  title: Parameters<typeof t>[0];
  body: Parameters<typeof t>[0];
  symbol: TileSymbolToken;
}> = [
  { title: "items", body: "helpItemsBody", symbol: "wheel" },
  { title: "destinations", body: "helpDestinationsBody", symbol: "island" },
  { title: "logbook", body: "helpLogbookBody", symbol: "book" },
  { title: "harbor", body: "helpHarborBody", symbol: "lighthouse" },
];

export function HelpDialog({ onClose }: { onClose: () => void }) {
  return (
    <Modal onClose={onClose}>
      <DialogHeader title={t("help")} onBack={onClose} />
      <p className="help-dialog-intro">{t("helpIntro")}</p>
      <div className="help-dialog-grid">
        {HELP_CHAPTERS.map((chapter) => (
          <section className="help-dialog-card" key={chapter.title}>
            <span className="help-dialog-icon" aria-hidden="true">
              <TileSymbolSvg symbol={chapter.symbol} fg="currentColor" bg="transparent" />
            </span>
            <div>
              <h3>{t(chapter.title)}</h3>
              <p>{t(chapter.body)}</p>
            </div>
          </section>
        ))}
      </div>
    </Modal>
  );
}
