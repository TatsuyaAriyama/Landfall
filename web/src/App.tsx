import { lazy, Suspense, useState } from "react";
import { useAuthUser, useUserData } from "./data";
import { SignInView } from "./views/SignInView";
import { TodayView } from "./views/TodayView";
import { TraceView } from "./views/TraceView";
import { HarborView } from "./views/HarborView";
import { LogbookView } from "./views/LogbookView";
import { SettingsDialog } from "./views/SettingsDialog";
import { BoatSvg, BrandMark, TileSymbolSvg } from "./symbols";
import type { ReactNode } from "react";
import { OfflineWatcher, OverlayHost } from "./overlays";
import { t } from "./i18n";
import { demoData, isDemo } from "./demo";

type Tab = "today" | "trace" | "logbook" | "boat" | "harbor";

const TABS: Tab[] = ["today", "trace", "logbook", "boat", "harbor"];

// three.js を含む船スタジオは重いので、タブを開いたときだけ読み込む。
const BoatStudio = lazy(() => import("./views/BoatStudio"));

/// 再読込しても開いていたタブに戻れるよう、タブを URL ハッシュに控える。
function initialTab(): Tab {
  const hash = window.location.hash.replace("#", "");
  return (TABS as string[]).includes(hash) ? (hash as Tab) : "today";
}

export default function App() {
  const { user, loading } = useAuthUser();

  if (isDemo) return <Main uid="demo" />;
  if (loading) return null;
  if (!user) return <SignInView />;
  return <Main uid={user.uid} />;
}

function Main({ uid }: { uid: string }) {
  const [tab, setTabState] = useState<Tab>(() => initialTab());
  const [settingsOpen, setSettingsOpen] = useState(false);
  const live = useUserData(uid, !isDemo);
  const data = isDemo ? demoData() : live;

  const setTab = (next: Tab) => {
    setTabState(next);
    if (!isDemo) history.replaceState(null, "", `#${next}`);
  };

  return (
    <div className="shell">
      <header className="topbar">
        <span className="brand">
          <BrandMark size={28} />
          {t("appName")}
        </span>
        <button className="quiet-button" onClick={() => setSettingsOpen(true)}>
          {t("settings")}
        </button>
      </header>

      {/* タブ。航海の語彙のアイコン+水平線のような選択インジケータ。
          モバイルでは画面下のタブバー(アイコン+小ラベルの縦積み)になる。 */}
      <nav className="tabs">
        {(
          [
            ["today", t("today"), <TileSymbolSvg symbol="wheel" fg="currentColor" bg="var(--paper)" />],
            ["trace", t("trace"), <TileSymbolSvg symbol="compass" fg="currentColor" bg="var(--paper)" />],
            ["logbook", t("logbook"), <TileSymbolSvg symbol="book" fg="currentColor" bg="var(--paper)" />],
            ["boat", t("boatTab"), <BoatSvg sail="currentColor" hull="currentColor" />],
            ["harbor", t("harbor"), <TileSymbolSvg symbol="lighthouse" fg="currentColor" bg="var(--paper)" />],
          ] as [Tab, string, ReactNode][]
        ).map(([key, label, icon]) => (
          <button
            key={key}
            className={`tab${tab === key ? " selected" : ""}`}
            onClick={() => setTab(key)}
            aria-current={tab === key ? "page" : undefined}
          >
            <span className="tab-icon" aria-hidden="true">
              {icon}
            </span>
            <span className="tab-label">{label}</span>
          </button>
        ))}
      </nav>

      {!data.ready ? (
        <p className="empty-note">{t("loading")}</p>
      ) : tab === "today" ? (
        <TodayView uid={uid} data={data} />
      ) : tab === "trace" ? (
        <TraceView uid={uid} data={data} />
      ) : tab === "logbook" ? (
        <LogbookView data={data} />
      ) : tab === "boat" ? (
        <Suspense fallback={<p className="empty-note">{t("loading")}</p>}>
          <BoatStudio data={data} />
        </Suspense>
      ) : (
        <HarborView uid={uid} data={data} />
      )}

      {settingsOpen && <SettingsDialog data={data} onClose={() => setSettingsOpen(false)} />}
      <OfflineWatcher />
      <OverlayHost />
    </div>
  );
}
