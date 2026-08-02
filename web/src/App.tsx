import { Component, lazy, Suspense, useState } from "react";
import { useAuthUser, useUserData } from "./data";
import { SignInView } from "./views/SignInView";
import { TodayView } from "./views/TodayView";
import { TraceView } from "./views/TraceView";
import { HarborView } from "./views/HarborView";
import { LogbookView } from "./views/LogbookView";
import { SettingsDialog } from "./views/SettingsDialog";
import { BrandMark, TileSymbolSvg } from "./symbols";
import type { ReactNode } from "react";
import { OfflineWatcher, OverlayHost } from "./overlays";
import { t } from "./i18n";
import { demoData, isDemo } from "./demo";

type Tab = "today" | "trace" | "logbook" | "boat" | "harbor";

const TABS: Tab[] = ["today", "trace", "logbook", "boat", "harbor"];

// three.js を含む船スタジオは重いので、タブを開いたときだけ読み込む。
const BoatStudio = lazy(() => import("./views/BoatStudio"));

/// タブ1枚ぶんの安全網。3Dの初期化に失敗しても、アプリ全体を落とさない。
/// (WebGLはiOSが背面で捨てることがあり、装いタブは Canvas を無条件に作っていた)
class TabErrorBoundary extends Component<
  { children?: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <p className="empty-note">{t("render3dFailed")}</p>
    ) : (
      this.props.children
    );
  }
}

// 不死鳥(航海士)の360度ビューア。#phoenix で直接開ける(サインイン不要)。
const PhoenixViewer = lazy(() => import("./three/PhoenixViewer"));
// 目的地の一本樹を背景なしで確認する360度ビューア。#tree で直接開ける。
const TreeViewer = lazy(() => import("./three/TreeViewer"));

/// 再読込しても開いていたタブに戻れるよう、タブを URL ハッシュに控える。
function initialTab(): Tab {
  const hash = window.location.hash.replace("#", "");
  return (TABS as string[]).includes(hash) ? (hash as Tab) : "today";
}

export default function App() {
  const { user, loading, redirectError } = useAuthUser();

  if (window.location.hash.startsWith("#tree")) {
    return (
      <Suspense fallback={null}>
        <TreeViewer />
      </Suspense>
    );
  }
  if (window.location.hash.startsWith("#phoenix")) {
    return (
      <Suspense fallback={null}>
        <PhoenixViewer />
      </Suspense>
    );
  }
  if (isDemo) return <Main uid="demo" />;
  // Google/Appleのリダイレクトから戻った直後もここを通る。以前は何も描かず
  // 真っ黒に見えたため、世界観と同じ地色だけでも先に出しておく。
  if (loading) return <div className="harbor-loading" />;
  if (!user) return <SignInView redirectError={redirectError} />;
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
            ["boat", t("boatTab"), <TileSymbolSvg symbol="attire" fg="currentColor" bg="var(--paper)" />],
            ["harbor", t("harbor"), <TileSymbolSvg symbol="sailboat" fg="currentColor" bg="var(--paper)" />],
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

      {data.failed ? (
        /* 繋がらないまま終わったときは、理由と次の一手を出す。
           「読み込み中…」のまま放置すると、直せるのに直せないと思われる。 */
        <div className="load-failed">
          <p className="empty-note">{t("loadFailed")}</p>
          <button className="chip" onClick={data.retry}>
            {t("retry")}
          </button>
        </div>
      ) : !data.ready ? (
        <p className="empty-note">{t("loading")}</p>
      ) : tab === "today" ? (
        <TodayView uid={uid} data={data} />
      ) : tab === "trace" ? (
        <TraceView uid={uid} data={data} />
      ) : tab === "logbook" ? (
        <LogbookView uid={uid} data={data} />
      ) : tab === "boat" ? (
        /* 装いは3Dが主役だが、失敗したときにアプリ全体を白紙にしてはいけない。
           他のタブ(ホーム・港)と同じく、描画不能なら案内へ落とす。 */
        <TabErrorBoundary>
          <Suspense fallback={<p className="empty-note">{t("loading")}</p>}>
            <BoatStudio data={data} />
          </Suspense>
        </TabErrorBoundary>
      ) : (
        <HarborView uid={uid} data={data} />
      )}

      {settingsOpen && <SettingsDialog data={data} onClose={() => setSettingsOpen(false)} />}
      <OfflineWatcher />
      <OverlayHost />
    </div>
  );
}
