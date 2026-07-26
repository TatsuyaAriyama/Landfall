import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import type {
  CSSProperties,
  MouseEvent as ReactMouseEvent,
  PointerEvent as ReactPointerEvent,
} from "react";

// タイルのドラッグ並び替え。
//
// HTML5 の drag & drop(draggable + dragstart/drop)はタッチ端末でイベントが
// 発火しないため、iPad・スマホでは並び替えが一切できなかった。マウスでも指でも
// 同じように動くよう Pointer Events で組み直す。
//
// 持ち上がるまでの触り分け:
// - マウス/ペン: 少し動かしたら持ち上がる(ただのクリックはそのまま通す)
// - タッチ: 長押しで持ち上がる。押してすぐ滑らせた場合はページのスクロールに譲る
//   (グリッドは画面の大半を占めるので、指を置いた場所で必ずスクロールできること)

/// タッチで持ち上がるまでの長押し時間。
const LIFT_HOLD_MS = 250;
/// マウス/ペンで持ち上がるまでの移動量。
const LIFT_MOVE_PX = 6;
/// 長押しが成立する前にこれだけ滑ったら、スクロールとみなして諦める。
const SCROLL_CANCEL_PX = 10;

interface Pending {
  id: string;
  pointerId: number;
  element: HTMLElement;
  startX: number;
  startY: number;
  touch: boolean;
  holdTimer: number | null;
}

interface Lifted {
  id: string;
  /// いまの升目からのずれ。指/カーソルの真下に来るよう毎回測り直す。
  dx: number;
  dy: number;
  /// 掴んだ位置(タイルの左上からの距離)。掴んだ場所を保ったまま動かすために持つ。
  grabX: number;
  grabY: number;
}

export interface DragReorder {
  /// 描画に使う並び。ドラッグ中は入れ替え途中の並びを返す。
  order: string[];
  /// 持ち上がっているタイルの id。
  liftedId: string | null;
  /// タイルに渡すハンドラ。
  tileProps: (id: string) => {
    onPointerDown: (e: ReactPointerEvent) => void;
    onContextMenu: (e: ReactMouseEvent) => void;
    style: CSSProperties | undefined;
    "data-reorder-id": string;
  };
}

function sameOrder(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((id, i) => id === b[i]);
}

function sameSet(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((id) => b.includes(id));
}

/// タイルの DOM 要素。
function tileElement(id: string): HTMLElement | null {
  return document.querySelector<HTMLElement>(`[data-reorder-id="${CSS.escape(id)}"]`);
}

/// 指/カーソルの真下にタイルを置くための、いまの升目からのずれ。
/// ドラッグ中は升目自体が入れ替わるので、掴んだ時点からの差分では足りない
/// (差分だけだとタイルが指から離れていってしまう)。毎回いまの升目を測り直す。
function offsetToPointer(held: Lifted, x: number, y: number): { dx: number; dy: number } | null {
  const el = tileElement(held.id);
  if (!el) return null;
  const rect = el.getBoundingClientRect();
  // rect には今あてている transform が乗っているので、外して升目の位置に戻す
  // (transform-origin は左上なので、拡大は左上をずらさない)。
  const slotLeft = rect.left - held.dx;
  const slotTop = rect.top - held.dy;
  return { dx: x - held.grabX - slotLeft, dy: y - held.grabY - slotTop };
}

/// ドラッグ直後の click を1回だけ飲む。
/// 指を離した位置のタイルが「押された」ことになって開いてしまうのを防ぐ
/// (離した先が別のタイルのこともあるので、要素単位ではなく window で受ける)。
function swallowNextClick() {
  const onClick = (e: MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();
  };
  window.addEventListener("click", onClick, { capture: true, once: true });
  // click が来ないまま終わることもある(タッチでは発火しない場合がある)ので、
  // 置きっぱなしにせず必ず外す。
  window.setTimeout(() => window.removeEventListener("click", onClick, true), 400);
}

/**
 * 並び替え。`ids` は現在の並び、`commit` は確定した並びを保存する処理。
 * 保存の往復を待つ間も手元の並びを保つので、指を離した瞬間に元の位置へ戻らない。
 */
export function useDragReorder(
  ids: string[],
  commit: (ordered: string[]) => void | Promise<void>,
): DragReorder {
  const [order, setOrder] = useState<string[]>(ids);
  const [lifted, setLifted] = useState<Lifted | null>(null);

  const orderRef = useRef(order);
  orderRef.current = order;
  const idsRef = useRef(ids);
  idsRef.current = ids;
  const liftedRef = useRef<Lifted | null>(lifted);
  liftedRef.current = lifted;
  const pendingRef = useRef<Pending | null>(null);
  // 自分が書いた並びが Firestore から返ってくるまでの間、外からの並びで上書きしない。
  const awaitingRef = useRef(false);

  // 外で並びが変わったら追従する。
  useEffect(() => {
    if (liftedRef.current) return; // ドラッグ中は手元の並びが正。
    if (!sameSet(ids, orderRef.current)) {
      // 項目の追加・削除は、確定待ちより優先して反映する。
      awaitingRef.current = false;
      setOrder(ids);
      return;
    }
    if (sameOrder(ids, orderRef.current)) {
      awaitingRef.current = false; // 自分の書き込みが返ってきた。
      return;
    }
    if (awaitingRef.current) return;
    setOrder(ids);
  }, [ids]);

  const clearPending = useCallback(() => {
    const pending = pendingRef.current;
    if (pending?.holdTimer !== null && pending?.holdTimer !== undefined) {
      window.clearTimeout(pending.holdTimer);
    }
    pendingRef.current = null;
  }, []);

  /// いま押している座標。升目が入れ替わった直後の置き直しにも使う。
  const pointerRef = useRef({ x: 0, y: 0 });

  /// 掴んだ位置を保ったまま持ち上げる。
  const lift = useCallback((id: string, x: number, y: number) => {
    const el = tileElement(id);
    if (!el) return;
    const rect = el.getBoundingClientRect();
    pointerRef.current = { x, y };
    setLifted({ id, dx: 0, dy: 0, grabX: x - rect.left, grabY: y - rect.top });
  }, []);

  /// 指/カーソルの下にあるタイルを探して、そこへ差し込む。
  const moveTo = useCallback((x: number, y: number) => {
    const held = liftedRef.current;
    if (!held) return;
    // 持ち上げ中のタイルは pointer-events: none なので、下のタイルが取れる。
    const el = document.elementFromPoint(x, y)?.closest("[data-reorder-id]");
    const targetId = el?.getAttribute("data-reorder-id");
    if (!targetId || targetId === held.id) return;
    const current = orderRef.current;
    const from = current.indexOf(held.id);
    const to = current.indexOf(targetId);
    if (from < 0 || to < 0) return;
    const next = [...current];
    next.splice(to, 0, ...next.splice(from, 1));
    setOrder(next);
  }, []);

  // 差し込みで升目が入れ替わった直後、描画される前に置き直す。
  // ここで直さないと、入れ替わるたびにタイルが1フレーム分だけ飛んで見える。
  useLayoutEffect(() => {
    const held = liftedRef.current;
    if (!held) return;
    const { x, y } = pointerRef.current;
    const next = offsetToPointer(held, x, y);
    if (next && (next.dx !== held.dx || next.dy !== held.dy)) setLifted({ ...held, ...next });
  }, [order]);

  // ドラッグ中はページを動かさない。touchmove は passive 既定だと preventDefault が
  // 効かないので、非 passive で自前に張る。
  useEffect(() => {
    if (!lifted) return;
    const block = (e: TouchEvent) => e.preventDefault();
    document.addEventListener("touchmove", block, { passive: false });
    return () => document.removeEventListener("touchmove", block);
  }, [lifted]);

  // 押している間だけ window で追う(タイルの外に出ても離しても取りこぼさない)。
  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      const pending = pendingRef.current;
      const held = liftedRef.current;

      if (held) {
        if (!pending || e.pointerId !== pending.pointerId) return;
        pointerRef.current = { x: e.clientX, y: e.clientY };
        // 画面端へ運んだときは少しずつページも送る。項目が1画面を超えても
        // 上下の離れた位置へ並べ替えられるようにする。
        const edge = 72;
        if (e.clientY < edge) {
          window.scrollBy(0, -Math.ceil((edge - e.clientY) / 5));
        } else if (e.clientY > window.innerHeight - edge) {
          window.scrollBy(0, Math.ceil((e.clientY - (window.innerHeight - edge)) / 5));
        }
        const next = offsetToPointer(held, e.clientX, e.clientY);
        if (next) setLifted({ ...held, ...next });
        moveTo(e.clientX, e.clientY);
        return;
      }

      if (!pending || e.pointerId !== pending.pointerId) return;
      const dist = Math.hypot(e.clientX - pending.startX, e.clientY - pending.startY);
      if (pending.touch) {
        // 長押しが決まる前に滑ったなら、それはスクロール。
        if (dist > SCROLL_CANCEL_PX) clearPending();
      } else if (dist > LIFT_MOVE_PX) {
        lift(pending.id, e.clientX, e.clientY);
      }
    };

    const onUp = (e: PointerEvent) => {
      const pending = pendingRef.current;
      if (pending && e.pointerId !== pending.pointerId) return;
      const held = liftedRef.current;
      clearPending();
      if (!held) return;
      setLifted(null);
      swallowNextClick();
      if (!sameOrder(orderRef.current, ids)) {
        awaitingRef.current = true;
        // 保存できなかったら手元の並びを戻す。並んだように見えて実は戻っている、
        // という嘘をつかないため(オフラインの書き込みは Firestore が抱えるので
        // ここには落ちてこない)。
        void Promise.resolve(commit(orderRef.current)).catch(() => {
          awaitingRef.current = false;
          setOrder(idsRef.current);
        });
      }
    };

    const onCancel = () => {
      clearPending();
      if (liftedRef.current) {
        setLifted(null);
        // 中断されたら手元の並びは捨てて、保存済みの並びに戻す。
        setOrder(ids);
      }
    };

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onCancel);
    return () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onCancel);
    };
  }, [ids, commit, moveTo, clearPending, lift]);

  // 画面から消えるときに長押しタイマーを残さない。
  useEffect(() => clearPending, [clearPending]);

  const onPointerDown = useCallback(
    (id: string, e: ReactPointerEvent) => {
      if (e.button !== 0 && e.pointerType === "mouse") return; // 右クリックは無視。
      clearPending();
      const touch = e.pointerType === "touch";
      const pending: Pending = {
        id,
        pointerId: e.pointerId,
        element: e.currentTarget as HTMLElement,
        startX: e.clientX,
        startY: e.clientY,
        touch,
        holdTimer: null,
      };
      if (touch) {
        pending.holdTimer = window.setTimeout(() => {
          if (pendingRef.current !== pending) return;
          pending.holdTimer = null;
          // 長押し成立後はブラウザーのパン判定へ渡さず、指がタイルの外へ
          // 出ても pointermove/up を受け続ける。特にiOS/Androidで重要。
          try {
            pending.element.setPointerCapture?.(pending.pointerId);
          } catch {
            // 指が既に離れていれば何もしない。
          }
          navigator.vibrate?.(10);
          lift(id, pending.startX, pending.startY);
        }, LIFT_HOLD_MS);
      }
      pendingRef.current = pending;
    },
    [clearPending, lift],
  );

  const tileProps = useCallback(
    (id: string) => ({
      onPointerDown: (e: ReactPointerEvent) => onPointerDown(id, e),
      onContextMenu: (e: ReactMouseEvent) => e.preventDefault(),
      style:
        lifted?.id === id
          ? ({
              transform: `translate(${lifted.dx}px, ${lifted.dy}px) scale(1.06)`,
              // 左上を動かさない拡大にする(位置の計算が transform に汚されない)。
              transformOrigin: "top left",
              // 下のタイルを elementFromPoint で拾えるように、当たり判定を外す。
              pointerEvents: "none",
              position: "relative",
              zIndex: 5,
              transition: "none",
            } as CSSProperties)
          : undefined,
      "data-reorder-id": id,
    }),
    [lifted, onPointerDown],
  );

  return { order, liftedId: lifted?.id ?? null, tileProps };
}
