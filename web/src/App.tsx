import { Component, lazy, Suspense, useEffect, useRef, useState } from "react";
import { useAuthUser, useUserData } from "./data";
import { SignInView } from "./views/SignInView";
import { TodayView } from "./views/TodayView";
import { TileSymbolSvg } from "./symbols";
import type { ReactNode } from "react";
import type { TileSymbolToken } from "./types";
import { OfflineWatcher, OverlayHost } from "./overlays";
import { t } from "./i18n";
import { demoData, isDemo } from "./demo";
import { PlayerProfile } from "./profile";
import { useBodyScrollLock } from "./scrollLock";
import { useTimeOfDay } from "./timeOfDay";
import {
  HOME_MUSIC_PREF_EVENT,
  HOME_WAVES_PREF_EVENT,
  homeMusicEnabled,
  homeWavesEnabled,
  startBackgroundMusic,
  startWaveAmbience,
  stopBackgroundMusic,
  stopWaveAmbience,
} from "./audio";
import { readTimer, TIMER_STATE_EVENT } from "./timer";

type Tab = "today" | "logbook" | "boat" | "harbor";
type MenuDestination = "island" | Exclude<Tab, "today">;

const TABS: Tab[] = ["today", "logbook", "boat", "harbor"];

const TAB_ITEMS: { key: Tab; label: Parameters<typeof t>[0]; symbol: TileSymbolToken }[] = [
  { key: "today", label: "today", symbol: "wheel" },
  { key: "logbook", label: "logbook", symbol: "book" },
  { key: "boat", label: "boatTab", symbol: "sailboat" },
  { key: "harbor", label: "harbor", symbol: "lighthouse" },
];

const MENU_ITEMS: Array<{
  key: MenuDestination;
  label?: Parameters<typeof t>[0];
  subtitle: Parameters<typeof t>[0];
  symbol: TileSymbolToken;
}> = [
  { key: "island", subtitle: "islandMenuSubtitle", symbol: "island" },
  { key: "harbor", label: "harbor", subtitle: "harborMenuSubtitle", symbol: "lighthouse" },
  { key: "logbook", label: "logbook", subtitle: "logbookMenuSubtitle", symbol: "book" },
  { key: "boat", label: "boatTab", subtitle: "styleMenuSubtitle", symbol: "sailboat" },
];

// ホーム以外は初期表示に含めない。動的 import 自体が同じ Promise を再利用するため、
// 指を置いた瞬間に先読みしても、クリック後の描画と二重取得にはならない。
const loadLogbookView = () => import("./views/LogbookView");
const loadBoatStudio = () => import("./views/BoatStudio");
const loadHarborView = () => import("./views/HarborView");
const loadSettingsDialog = () => import("./views/SettingsDialog");
const loadHelpDialog = () => import("./views/HelpDialog");
const loadVoyagePassDialog = () => import("./views/VoyagePassDialog");

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
const HelpDialog = lazy(() =>
  loadHelpDialog().then(({ HelpDialog: view }) => ({ default: view })),
);
const VoyagePassDialog = lazy(() =>
  loadVoyagePassDialog().then(({ VoyagePassDialog: view }) => ({ default: view })),
);

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

function preloadMenuDestination(destination: MenuDestination) {
  if (destination === "island") void import("./three/VoyageWorld");
  if (destination === "harbor") void loadHarborView();
  if (destination === "logbook") void loadLogbookView();
  if (destination === "boat") void loadBoatStudio();
}

function HomeCommandMenu({
  onClose,
  onDestination,
  onHelp,
  onSettings,
}: {
  onClose: () => void;
  onDestination: (destination: MenuDestination) => void;
  onHelp: () => void;
  onSettings: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useBodyScrollLock();

  useEffect(() => {
    const previouslyFocused = document.activeElement as HTMLElement | null;
    const selector = 'button:not([disabled]), [href], [tabindex]:not([tabindex="-1"])';
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        closeRef.current();
        return;
      }
      if (event.key !== "Tab" || !dialogRef.current) return;
      const focusable = [...dialogRef.current.querySelectorAll<HTMLElement>(selector)];
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    requestAnimationFrame(() => dialogRef.current?.querySelector<HTMLElement>(selector)?.focus());
    return () => {
      window.removeEventListener("keydown", onKey);
      previouslyFocused?.focus();
    };
  }, []);

  return (
    <div className="home-command-layer">
      <button
        type="button"
        className="home-command-backdrop"
        onClick={onClose}
        aria-label={t("close")}
      />
      <div
        ref={dialogRef}
        className="home-command-menu"
        role="dialog"
        aria-modal="true"
        aria-label={t("mainNavigation")}
      >
        <span className="home-command-corner top" aria-hidden="true" />
        <span className="home-command-corner bottom" aria-hidden="true" />
        <nav className="home-command-grid" aria-label={t("mainNavigation")}>
          {MENU_ITEMS.map(({ key, label, subtitle, symbol }) => {
            const title = key === "island" ? PlayerProfile.islandName : t(label!);
            return (
              <button
                key={key}
                className="home-command-card"
                onPointerEnter={() => preloadMenuDestination(key)}
                onFocus={() => preloadMenuDestination(key)}
                onClick={() => onDestination(key)}
                aria-label={`${title} · ${t(subtitle)}`}
              >
                <span className="home-command-card-head">
                  <span className="home-command-card-icon" aria-hidden="true">
                    <TileSymbolSvg symbol={symbol} fg="currentColor" bg="transparent" />
                  </span>
                  <span className="home-command-arrow" aria-hidden="true">↗</span>
                </span>
                <strong>{title}</strong>
                <small>{t(subtitle)}</small>
              </button>
            );
          })}
        </nav>
        <div className="home-command-actions">
          <button
            className="home-command-action"
            onPointerEnter={() => void loadHelpDialog()}
            onFocus={() => void loadHelpDialog()}
            onClick={onHelp}
          >
            <span className="home-command-action-icon help" aria-hidden="true">?</span>
            <span>{t("help")}</span>
            <span className="home-command-chevron" aria-hidden="true">›</span>
          </button>
          <button
            className="home-command-action"
            onPointerEnter={() => void loadSettingsDialog()}
            onFocus={() => void loadSettingsDialog()}
            onClick={onSettings}
          >
            <span className="home-command-action-icon settings" aria-hidden="true"><i /><i /><i /></span>
            <span>{t("settings")}</span>
            <span className="home-command-chevron" aria-hidden="true">›</span>
          </button>
        </div>
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
  const [helpOpen, setHelpOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [openDestinationToken, setOpenDestinationToken] = useState(0);
  const [backgroundMusicOn, setBackgroundMusicOn] = useState(homeMusicEnabled);
  const [waveAmbienceOn, setWaveAmbienceOn] = useState(homeWavesEnabled);
  const [timerRunning, setTimerRunning] = useState(() => readTimer() !== null);
  const [voyagePassOpen, setVoyagePassOpen] = useState(() =>
    new URLSearchParams(window.location.search).has("voyage-pass"),
  );
  const timeOfDay = useTimeOfDay();
  const live = useUserData(uid, !isDemo);
  const data = isDemo ? demoData() : live;

  useEffect(() => {
    const syncMusicPreference = () => setBackgroundMusicOn(homeMusicEnabled());
    const syncWavesPreference = () => setWaveAmbienceOn(homeWavesEnabled());
    const syncTimer = () => setTimerRunning(readTimer() !== null);
    const syncStorage = () => {
      syncMusicPreference();
      syncWavesPreference();
      syncTimer();
    };
    window.addEventListener(HOME_MUSIC_PREF_EVENT, syncMusicPreference);
    window.addEventListener(HOME_WAVES_PREF_EVENT, syncWavesPreference);
    window.addEventListener(TIMER_STATE_EVENT, syncTimer);
    window.addEventListener("storage", syncStorage);
    return () => {
      window.removeEventListener(HOME_MUSIC_PREF_EVENT, syncMusicPreference);
      window.removeEventListener(HOME_WAVES_PREF_EVENT, syncWavesPreference);
      window.removeEventListener(TIMER_STATE_EVENT, syncTimer);
      window.removeEventListener("storage", syncStorage);
    };
  }, []);

  useEffect(() => {
    const syncWaves = () => {
      if (waveAmbienceOn && !timerRunning && !document.hidden) startWaveAmbience();
      else stopWaveAmbience();
    };
    syncWaves();
    document.addEventListener("visibilitychange", syncWaves);
    window.addEventListener("pointerdown", syncWaves, { capture: true });
    window.addEventListener("keydown", syncWaves, { capture: true });
    return () => {
      document.removeEventListener("visibilitychange", syncWaves);
      window.removeEventListener("pointerdown", syncWaves, { capture: true });
      window.removeEventListener("keydown", syncWaves, { capture: true });
      stopWaveAmbience();
    };
  }, [waveAmbienceOn, timerRunning]);

  useEffect(() => {
    const syncPlayback = () => {
      if (backgroundMusicOn && !timerRunning && !document.hidden) {
        startBackgroundMusic();
      } else {
        stopBackgroundMusic();
      }
    };
    // 自動再生できる環境ではそのまま開始。拒否されたブラウザでは、最初の操作を
    // 同じ関数へ渡してユーザー操作のコンテキスト内で再試行する。
    syncPlayback();
    document.addEventListener("visibilitychange", syncPlayback);
    window.addEventListener("pointerdown", syncPlayback, { capture: true });
    window.addEventListener("keydown", syncPlayback, { capture: true });
    return () => {
      document.removeEventListener("visibilitychange", syncPlayback);
      window.removeEventListener("pointerdown", syncPlayback, { capture: true });
      window.removeEventListener("keydown", syncPlayback, { capture: true });
      stopBackgroundMusic();
    };
  }, [backgroundMusicOn, timerRunning]);

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
    setMenuOpen(false);
    setTabState(next);
    if (!isDemo) history.replaceState(null, "", `#${next}`);
    window.requestAnimationFrame(() => {
      window.scrollTo({
        top: 0,
        behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
      });
    });
  };

  const openMenuDestination = (destination: MenuDestination) => {
    if (destination === "island") {
      setMenuOpen(false);
      setTabState("today");
      setOpenDestinationToken((token) => token + 1);
      if (!isDemo) history.replaceState(null, "", "#today");
      return;
    }
    setTab(destination);
  };

  const closeVoyagePass = () => {
    setVoyagePassOpen(false);
    const url = new URL(window.location.href);
    if (!url.searchParams.has("voyage-pass")) return;
    url.searchParams.delete("voyage-pass");
    history.replaceState(null, "", `${url.pathname}${url.search}${url.hash}`);
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
      <header className={`topbar${tab === "harbor" || tab === "boat" ? " route-left" : ""}`}>
        {tab === "today" ? (
          <button
            className="home-menu-trigger"
            onClick={() => setMenuOpen((open) => !open)}
            aria-haspopup="menu"
            aria-expanded={menuOpen}
          >
            <span>{t("today")}</span>
            <span className="home-menu-trigger-chevron" aria-hidden="true">
              {menuOpen ? "⌃" : "⌄"}
            </span>
          </button>
        ) : tab === "boat" ? (
          <button className="route-back-button" onClick={() => setTab("today")}>
            <span aria-hidden="true">‹</span>
            {t("back")}
          </button>
        ) : (
          <button
            className="route-close-button"
            onClick={() => setTab("today")}
            aria-label={t("close")}
          >
            ×
          </button>
        )}
      </header>

      {menuOpen && (
        <HomeCommandMenu
          onClose={() => setMenuOpen(false)}
          onDestination={openMenuDestination}
          onHelp={() => {
            setMenuOpen(false);
            setHelpOpen(true);
          }}
          onSettings={() => {
            setMenuOpen(false);
            setSettingsOpen(true);
          }}
        />
      )}

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
          <TodayView
            uid={uid}
            data={data}
            timeOfDay={timeOfDay}
            navigationOpen={menuOpen}
            openDestinationToken={openDestinationToken}
          />
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
          <SettingsDialog
            uid={uid}
            data={data}
            onClose={() => setSettingsOpen(false)}
            onVoyagePass={() => {
              setSettingsOpen(false);
              setVoyagePassOpen(true);
            }}
          />
        </Suspense>
      )}
      {helpOpen && (
        <Suspense fallback={<DialogLoading />}>
          <HelpDialog onClose={() => setHelpOpen(false)} />
        </Suspense>
      )}
      {voyagePassOpen && (
        <Suspense fallback={<DialogLoading />}>
          <VoyagePassDialog onClose={closeVoyagePass} />
        </Suspense>
      )}
      <OfflineWatcher />
      <OverlayHost />
    </div>
  );
}
