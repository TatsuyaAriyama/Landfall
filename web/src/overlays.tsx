import { useEffect, useRef, useState, type ReactNode } from "react";
import { t } from "./i18n";
import { useBackToClose } from "./backClose";
import { lockBodyScroll } from "./scrollLock";

// ダイアログとトーストの共通基盤。
// - Modal: Esc で閉じる+表示中は背景スクロールを固定
// - askConfirm: ブラウザ素の confirm() の代わり(世界観を壊さない)
// - showToast: 保存・参加・失敗などの静かなフィードバック

export function Modal({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;
  // Androidの戻る・ブラウザの戻るは、アプリを離れるのではなく最前面の
  // ダイアログを一つだけ閉じる。確認ダイアログが重なっていてもスタック順に戻る。
  useBackToClose(true, onClose);

  useEffect(() => {
    const previouslyFocused = document.activeElement as HTMLElement | null;
    const focusableSelector =
      'button:not([disabled]), [href], input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCloseRef.current();
      if (e.key !== "Tab" || !dialogRef.current) return;
      const focusable = [...dialogRef.current.querySelectorAll<HTMLElement>(focusableSelector)];
      if (focusable.length === 0) {
        e.preventDefault();
        dialogRef.current.focus();
        return;
      }
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    const unlockScroll = lockBodyScroll();
    requestAnimationFrame(() => {
      const autofocus = dialogRef.current?.querySelector<HTMLElement>("[autofocus]");
      const first = dialogRef.current?.querySelector<HTMLElement>(focusableSelector);
      (autofocus ?? first ?? dialogRef.current)?.focus();
    });
    return () => {
      window.removeEventListener("keydown", onKey);
      unlockScroll();
      previouslyFocused?.focus();
    };
  }, []);

  return (
    <div className="overlay" onClick={onClose}>
      <div
        ref={dialogRef}
        className="dialog"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        tabIndex={-1}
      >
        {children}
      </div>
    </div>
  );
}

/// 長いダイアログでも常に見える「一つ前へ戻る」ための見出し。
/// ×や背景タップだけに頼らず、戻り先を言葉で明示する。
export function DialogHeader({ title, onBack }: { title: string; onBack: () => void }) {
  return (
    <div className="dialog-nav">
      <button className="dialog-back" onClick={onBack} aria-label={t("back")}>
        <span aria-hidden="true">‹</span>
        {t("back")}
      </button>
      <h2 className="dialog-title">{title}</h2>
      <span className="dialog-nav-balance" aria-hidden="true" />
    </div>
  );
}

// ---- 確認ダイアログ ----

interface ConfirmOptions {
  title: string;
  message?: string;
  confirmLabel?: string;
  danger?: boolean;
}

type ConfirmRequest = ConfirmOptions & { resolve: (ok: boolean) => void };

let requestConfirm: ((req: ConfirmRequest) => void) | null = null;

export function askConfirm(options: ConfirmOptions): Promise<boolean> {
  return new Promise((resolve) => {
    if (requestConfirm) requestConfirm({ ...options, resolve });
    else resolve(false);
  });
}

// ---- トースト ----

let pushToast: ((message: string) => void) | null = null;

export function showToast(message: string) {
  pushToast?.(message);
}

// ---- オフライン監視(バナー+復帰トースト) ----

export function OfflineWatcher() {
  const [offline, setOffline] = useState(
    typeof navigator !== "undefined" && !navigator.onLine,
  );

  useEffect(() => {
    const goOffline = () => {
      setOffline(true);
      showToast(t("offlineToast"));
    };
    const goOnline = () => {
      setOffline(false);
      showToast(t("onlineToast"));
    };
    window.addEventListener("offline", goOffline);
    window.addEventListener("online", goOnline);
    return () => {
      window.removeEventListener("offline", goOffline);
      window.removeEventListener("online", goOnline);
    };
  }, []);

  if (!offline) return null;
  return (
    <div className="offline-banner" role="status" aria-live="polite">
      {t("offlineToast")}
    </div>
  );
}

// ---- ホスト(App 直下に1つ置く) ----

export function OverlayHost() {
  const [confirm, setConfirm] = useState<ConfirmRequest | null>(null);
  const [toasts, setToasts] = useState<{ id: number; message: string }[]>([]);

  useEffect(() => {
    requestConfirm = (req) =>
      setConfirm((current) => {
        current?.resolve(false);
        return req;
      });
    let nextId = 1;
    pushToast = (message) => {
      const id = nextId++;
      setToasts((list) => [...list.slice(-2), { id, message }]);
      setTimeout(() => {
        setToasts((list) => list.filter((toast) => toast.id !== id));
      }, 2600);
    };
    return () => {
      requestConfirm = null;
      pushToast = null;
    };
  }, []);

  const finish = (ok: boolean) => {
    confirm?.resolve(ok);
    setConfirm(null);
  };

  return (
    <>
      {confirm && (
        <Modal onClose={() => finish(false)}>
          <h2 className="dialog-title">{confirm.title}</h2>
          {confirm.message && <p className="confirm-message">{confirm.message}</p>}
          <div className="confirm-actions">
            <button className="chip" onClick={() => finish(false)}>
              {t("cancel")}
            </button>
            <button
              className={`chip confirm-primary${confirm.danger ? " danger" : ""}`}
              onClick={() => finish(true)}
              autoFocus
            >
              {confirm.confirmLabel ?? "OK"}
            </button>
          </div>
        </Modal>
      )}
      <div className="toast-stack" aria-live="polite">
        {toasts.map((toast) => (
          <div key={toast.id} className="toast" role="status">
            <span>{toast.message}</span>
            <button
              className="toast-dismiss"
              onClick={() => setToasts((list) => list.filter((item) => item.id !== toast.id))}
              aria-label={t("close")}
            >
              ×
            </button>
          </div>
        ))}
      </div>
    </>
  );
}
