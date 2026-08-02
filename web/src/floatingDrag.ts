import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
} from "react";
import { storage } from "./storage";

interface Position {
  left: number;
  top: number;
}

interface SavedPosition {
  xRatio: number;
  yRatio: number;
}

interface DragStart extends Position {
  pointerId: number;
  x: number;
  y: number;
  moved: boolean;
}

const EDGE_GAP = 8;
const MOVE_THRESHOLD = 5;

function readSaved(key: string): SavedPosition | null {
  try {
    const value = JSON.parse(storage.get(key) ?? "null") as Partial<SavedPosition> | null;
    if (
      value &&
      Number.isFinite(value.xRatio) &&
      Number.isFinite(value.yRatio)
    ) {
      return {
        xRatio: Math.min(1, Math.max(0, Number(value.xRatio))),
        yRatio: Math.min(1, Math.max(0, Number(value.yRatio))),
      };
    }
  } catch {
    // 壊れた古い値は既定位置へ戻す。
  }
  return null;
}

/// fixed 要素を画面内で自由に動かし、中心位置を画面比率で保存する。
/// 比率保存なので、スマホの回転や別サイズの画面でも画面外へ消えない。
export function useFloatingDrag(storageKey: string) {
  const elementRef = useRef<HTMLDivElement | null>(null);
  const startRef = useRef<DragStart | null>(null);
  const latestRef = useRef<Position | null>(null);
  const suppressClickRef = useRef(false);
  const [position, setPosition] = useState<Position | null>(null);
  const [dragging, setDragging] = useState(false);

  const clamp = useCallback((left: number, top: number): Position => {
    const rect = elementRef.current?.getBoundingClientRect();
    const width = rect?.width ?? 0;
    const height = rect?.height ?? 0;
    return {
      left: Math.min(
        Math.max(EDGE_GAP, left),
        Math.max(EDGE_GAP, window.innerWidth - width - EDGE_GAP),
      ),
      top: Math.min(
        Math.max(EDGE_GAP, top),
        Math.max(EDGE_GAP, window.innerHeight - height - EDGE_GAP),
      ),
    };
  }, []);

  const applyPosition = useCallback(
    (next: Position) => {
      const safe = clamp(next.left, next.top);
      latestRef.current = safe;
      setPosition(safe);
    },
    [clamp],
  );

  useLayoutEffect(() => {
    const saved = readSaved(storageKey);
    const rect = elementRef.current?.getBoundingClientRect();
    if (!saved || !rect) return;
    applyPosition({
      left: saved.xRatio * window.innerWidth - rect.width / 2,
      top: saved.yRatio * window.innerHeight - rect.height / 2,
    });
  }, [applyPosition, storageKey]);

  useEffect(() => {
    const keepOnScreen = () => {
      const current = latestRef.current;
      if (current) applyPosition(current);
    };
    window.addEventListener("resize", keepOnScreen);
    window.visualViewport?.addEventListener("resize", keepOnScreen);
    return () => {
      window.removeEventListener("resize", keepOnScreen);
      window.visualViewport?.removeEventListener("resize", keepOnScreen);
    };
  }, [applyPosition]);

  const onPointerDown = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    if ((event.target as HTMLElement).closest("[data-no-floating-drag]")) return;
    if (event.pointerType === "mouse" && event.button !== 0) return;
    const rect = event.currentTarget.getBoundingClientRect();
    startRef.current = {
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      left: rect.left,
      top: rect.top,
      moved: false,
    };
    try {
      event.currentTarget.setPointerCapture(event.pointerId);
    } catch {
      // Pointer Capture 非対応でも、要素内のドラッグはそのまま使える。
    }
  }, []);

  const onPointerMove = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      const start = startRef.current;
      if (!start || start.pointerId !== event.pointerId) return;
      const dx = event.clientX - start.x;
      const dy = event.clientY - start.y;
      if (!start.moved && Math.hypot(dx, dy) < MOVE_THRESHOLD) return;
      start.moved = true;
      setDragging(true);
      event.preventDefault();
      applyPosition({ left: start.left + dx, top: start.top + dy });
    },
    [applyPosition],
  );

  const finish = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    const start = startRef.current;
    if (!start || start.pointerId !== event.pointerId) return;
    startRef.current = null;
    setDragging(false);
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    if (!start.moved) return;
    suppressClickRef.current = true;
    window.setTimeout(() => {
      suppressClickRef.current = false;
    }, 400);
    const current = latestRef.current;
    const rect = elementRef.current?.getBoundingClientRect();
    if (!current || !rect) return;
    const saved: SavedPosition = {
      xRatio: (current.left + rect.width / 2) / window.innerWidth,
      yRatio: (current.top + rect.height / 2) / window.innerHeight,
    };
    storage.set(storageKey, JSON.stringify(saved));
  }, [storageKey]);

  const cancel = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    const start = startRef.current;
    if (!start || start.pointerId !== event.pointerId) return;
    startRef.current = null;
    suppressClickRef.current = false;
    setDragging(false);
  }, []);

  const consumeDraggedClick = useCallback(() => {
    if (!suppressClickRef.current) return false;
    suppressClickRef.current = false;
    return true;
  }, []);

  const style: CSSProperties | undefined = position
    ? {
        left: position.left,
        top: position.top,
        bottom: "auto",
        transform: "none",
      }
    : undefined;

  return {
    elementRef,
    dragging,
    style,
    consumeDraggedClick,
    pointerProps: {
      onPointerDown,
      onPointerMove,
      onPointerUp: finish,
      onPointerCancel: cancel,
    },
  };
}
