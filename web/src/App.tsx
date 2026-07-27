import { Component, lazy, Suspense, useEffect, useState } from "react";
import { useAuthUser, useUserData } from "./data";
import { SignInView } from "./views/SignInView";
import { TodayView } from "./views/TodayView";
import { BrandMark, TileSymbolSvg } from "./symbols";
import type { ReactNode } from "react";
import type { TileSymbolToken } from "./types";
import { OfflineWatcher, OverlayHost } from "./overlays";
import { t } from "./i18n";
import { demoData, isDemo } from "./demo";
import { useTimeOfDay } from "./timeOfDay";
import { whenIdle } from "./idle";

type Tab = "today" | "trace" | "logbook" | "boat" | "harbor";

const TABS: Tab[] = ["today", "trace", "logbook", "boat", "harbor"];

const TAB_ITEMS: { key: Tab; label: Parameters<typeof t>[0]; symbol: TileSymbolToken }[] = [
  { key: "today", label: "today", symbol: "wheel" },
  { key: "trace", label: "trace", symbol: "compass" },
  { key: "logbook", label: "logbook", symbol: "book" },
  { key: "boat", label: "boatTab", symbol: "attire" },
  { key: "harbor", label: "harbor", symbol: "sailboat" },
];

// ホーム以外は初期表示に含めない。動的 import 自体が同じ Promise を再利用するため、
// 指を置いた瞬間に先読みしても、クリック後の描画と二重取得にはならない。
const loadTraceView = () => import("./views/TraceView");
const loadLogbookView = () => import("./views/LogbookView");
const loadBoatStudio = () => import("./views/BoatStudio");
const loadHarborView = () => import("./views/HarborView");
const loadSettingsDialog = () => import("./views/SettingsDialog");

const TraceView = lazy(() =>
  loadTraceView().then(({ TraceView: view }) => ({ default: view })),
);
const LogbookView = lazy(() =>
  loadLogbookView().then(({ LogbookView: view }) => ({ default: view })),
);
const BoatStudio = lazy(loadBoatStudio);
const HarborView = lazy(() =>
  loadHarborView().then(({ HarborView: view }) => ({ default: view })),
);
const SettingsDialog = lazy(() =>
  loadSettingsDialog().then(({ SettingsDialog: view }) => ({ default: view })),
);

function preloadTab(tab: Tab) {
  const connection = (
    navigator as Navigator & {
      connection?: { saveData?: boolean; effectiveType?: string };
    }
  ).connection;
  if (
    connection?.saveData ||
    connection?.effectiveType === "slow-2g" ||
    connection?.effectiveType === "2g"
  ) {
    return;
  }
  if (tab === "trace") void loadTraceView();
  if (tab === "logbook") void loadLogbookView();
  if (tab === "boat") void loadBoatStudio();
  if (tab === "harbor") void loadHarborView();
}

function ViewLoading() {
  return (
    <div className="view-loading" role="status">
      <div aria-hidden="true">
        <span />
        <span />
        <span />
      </div>
      <p>{t("loadingSeaChart")}</p>
    </div>
  );
}

function DialogLoading() {
  return (
    <div className="overlay" role="status" aria-label={t("loading")}>
      <div className="dialog dialog-loading">
        <ViewLoading />
      </div>
    </div>
  );
}

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
      <div className="load-failed">
        <p className="empty-note">{t("render3dFailed")}</p>
        <button className="chip" onClick={() => this.setState({ failed: false })}>
          {t("retry3d")}
        </button>
      </div>
    ) : (
      this.props.children
    );
  }
}

// 不死鳥(航海士)の360度ビューア。#phoenix で直接開ける(サインイン不要)。
const PhoenixViewer = lazy(() => import("./three/PhoenixViewer"));

/// 再読込しても開いていたタブに戻れるよう、タブを URL ハッシュに控える。
function initialInviteCode(): string | undefined {
  const raw = new URLSearchParams(window.location.search).get("invite") ?? "";
  const code = raw.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, "").slice(0, 6);
  return code.length === 6 ? code : undefined;
}

function initialTab(): Tab {
  // 招待URLは、サインイン後もコード入力画面へ直接戻す。
  if (initialInviteCode()) return "harbor";
  const hash = window.location.hash.replace("#", "");
  return (TABS as string[]).includes(hash) ? (hash as Tab) : "today";
}

export default function App() {
  const { user, loading, redirectError } = useAuthUser();

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
  const [inviteCode] = useState(() => initialInviteCode());
  const [settingsOpen, setSettingsOpen] = useState(false);
  const timeOfDay = useTimeOfDay();
  const live = useUserData(uid, !isDemo);
  const data = isDemo ? demoData() : live;

  // よく使う軽い2画面だけ、初期描画後の空き時間に準備する。
  // 3Dを含む装い・港は、ユーザーが触れるまでネットワークを使わない。
  useEffect(
    () =>
      whenIdle(() => {
        void loadTraceView();
        void loadLogbookView();
      }),
    [],
  );

  useEffect(() => {
    const colors = {
      morning: "#d9e8dd",
      day: "#a9deeb",
      evening: "#a85552",
      night: "#0b2927",
    };
    let meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    if (!meta) {
      meta = document.createElement("meta");
      meta.name = "theme-color";
      document.head.append(meta);
    }
    meta.content = colors[timeOfDay];
  }, [timeOfDay]);

  const setTab = (next: Tab) => {
    preloadTab(next);
    setTabState(next);
    if (!isDemo) history.replaceState(null, "", `#${next}`);
    window.requestAnimationFrame(() => {
      window.scrollTo({
        top: 0,
        behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
      });
    });
  };

  return (
    <div
      className={`shell home-ocean time-${timeOfDay}`}
      data-time-of-day={timeOfDay}
      data-tab={tab}
    >
      <a className="skip-link" href="#main-content">
        {t("skipToContent")}
      </a>
      <header className="topbar">
        <span className="brand">
          <BrandMark size={28} />
          {t("appName")}
        </span>
        <button
          className="quiet-button"
          onPointerEnter={() => void loadSettingsDialog()}
          onFocus={() => void loadSettingsDialog()}
          onTouchStart={() => void loadSettingsDialog()}
          onClick={() => setSettingsOpen(true)}
          aria-haspopup="dialog"
          aria-expanded={settingsOpen}
        >
          {t("settings")}
        </button>
      </header>

      {/* タブ。航海の語彙のアイコン+水平線のような選択インジケータ。
          モバイルでは画面下のタブバー(アイコン+小ラベルの縦積み)になる。 */}
      <nav className="tabs" aria-label={t("mainNavigation")}>
        {TAB_ITEMS.map(({ key, label, symbol }) => (
          <button
            key={key}
            className={`tab${tab === key ? " selected" : ""}`}
            onPointerEnter={() => preloadTab(key)}
            onFocus={() => preloadTab(key)}
            onTouchStart={() => preloadTab(key)}
            onClick={() => setTab(key)}
            aria-current={tab === key ? "page" : undefined}
          >
            <span className="tab-icon" aria-hidden="true">
              <TileSymbolSvg symbol={symbol} fg="currentColor" bg="var(--paper)" />
            </span>
            <span className="tab-label">{t(label)}</span>
          </button>
        ))}
      </nav>

      <span className="sr-only" role="status" aria-live="polite">
        {t("tabChanged").replace("{tab}", t(TAB_ITEMS.find((item) => item.key === tab)!.label))}
      </span>

      <main id="main-content" tabIndex={-1}>
        <Suspense fallback={<ViewLoading />}>
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
          <ViewLoading />
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
            <BoatStudio data={data} />
          </TabErrorBoundary>
        ) : (
          <HarborView uid={uid} data={data} inviteCode={inviteCode} />
          )}
        </Suspense>
      </main>

      {settingsOpen && (
        <Suspense fallback={<DialogLoading />}>
          <SettingsDialog uid={uid} data={data} onClose={() => setSettingsOpen(false)} />
        </Suspense>
      )}
      <OfflineWatcher />
      <OverlayHost />
    </div>
  );
}
