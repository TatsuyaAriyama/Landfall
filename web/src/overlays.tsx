import { useEffect, useState, type ReactNode } from "react";
import { t } from "./i18n";

// ダイアログとトーストの共通基盤。
// - Modal: Esc で閉じる+表示中は背景スクロールを固定
// - askConfirm: ブラウザ素の confirm() の代わり(世界観を壊さない)
// - showToast: 保存・参加・失敗などの静かなフィードバック

export function Modal({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose]);

  return (
    <div className="overlay" onClick={onClose}>
      <div className="dialog" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        {children}
      </div>
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

// ---- ホスト(App 直下に1つ置く) ----

export function OverlayHost() {
  const [confirm, setConfirm] = useState<ConfirmRequest | null>(null);
  const [toasts, setToasts] = useState<{ id: number; message: string }[]>([]);

  useEffect(() => {
    requestConfirm = (req) => setConfirm(req);
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
          <div key={toast.id} className="toast">
            {toast.message}
          </div>
        ))}
      </div>
    </>
  );
}
