import {
  useCallback,
  useRef,
  type PointerEvent as ReactPointerEvent,
} from "react";

/**
 * 指では大きな操作面全体をドラッグ領域にしない。
 * 背景を触った最初の一点は反映するが、その後の縦移動はページスクロールへ譲る。
 * マウス/ペン、または明示した取っ手から始めた指だけを連続ドラッグとして捕捉する。
 */
export function shouldCapturePointer(pointerType: string, startedOnHandle: boolean): boolean {
  return pointerType !== "touch" || startedOnHandle;
}

export function useScrollFriendlyPointerDrag<T extends HTMLElement>({
  handleSelector,
  onChange,
}: {
  handleSelector: string;
  onChange: (event: ReactPointerEvent<T>) => void;
}) {
  const activePointer = useRef<number | null>(null);

  const release = useCallback((event: ReactPointerEvent<T>) => {
    if (activePointer.current !== event.pointerId) return;
    activePointer.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  }, []);

  const onPointerDown = useCallback(
    (event: ReactPointerEvent<T>) => {
      activePointer.current = null;
      onChange(event);

      const target = event.target;
      const startedOnHandle =
        target instanceof Element && target.closest(handleSelector) !== null;
      if (!shouldCapturePointer(event.pointerType, startedOnHandle)) return;

      event.preventDefault();
      activePointer.current = event.pointerId;
      event.currentTarget.setPointerCapture(event.pointerId);
    },
    [handleSelector, onChange],
  );

  const onPointerMove = useCallback(
    (event: ReactPointerEvent<T>) => {
      if (activePointer.current !== event.pointerId) return;
      event.preventDefault();
      onChange(event);
    },
    [onChange],
  );

  const onLostPointerCapture = useCallback((event: ReactPointerEvent<T>) => {
    if (activePointer.current === event.pointerId) activePointer.current = null;
  }, []);

  return {
    onPointerDown,
    onPointerMove,
    onPointerUp: release,
    onPointerCancel: release,
    onLostPointerCapture,
  };
}
