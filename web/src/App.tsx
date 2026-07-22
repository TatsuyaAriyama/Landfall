import { useState } from "react";
import { useAuthUser, useUserData } from "./data";
import { SignInView } from "./views/SignInView";
import { TodayView } from "./views/TodayView";
import { TraceView } from "./views/TraceView";
import { HarborView } from "./views/HarborView";
import { LogbookView } from "./views/LogbookView";
import { SettingsDialog } from "./views/SettingsDialog";
import { BrandMark } from "./symbols";
import { OfflineWatcher, OverlayHost } from "./overlays";
import { t } from "./i18n";
import { demoData, isDemo } from "./demo";

type Tab = "today" | "trace" | "logbook" | "harbor";

const TABS: Tab[] = ["today", "trace", "logbook", "harbor"];

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

      <nav className="tabs">
        <button
          className={`tab${tab === "today" ? " selected" : ""}`}
          onClick={() => setTab("today")}
        >
          {t("today")}
        </button>
        <button
          className={`tab${tab === "trace" ? " selected" : ""}`}
          onClick={() => setTab("trace")}
        >
          {t("trace")}
        </button>
        <button
          className={`tab${tab === "logbook" ? " selected" : ""}`}
          onClick={() => setTab("logbook")}
        >
          {t("logbook")}
        </button>
        <button
          className={`tab${tab === "harbor" ? " selected" : ""}`}
          onClick={() => setTab("harbor")}
        >
          {t("harbor")}
        </button>
      </nav>

      {!data.ready ? (
        <p className="empty-note">{t("loading")}</p>
      ) : tab === "today" ? (
        <TodayView uid={uid} data={data} />
      ) : tab === "trace" ? (
        <TraceView uid={uid} data={data} />
      ) : tab === "logbook" ? (
        <LogbookView data={data} />
      ) : (
        <HarborView uid={uid} data={data} />
      )}

      {settingsOpen && <SettingsDialog data={data} onClose={() => setSettingsOpen(false)} />}
      <OfflineWatcher />
      <OverlayHost />
    </div>
  );
}
