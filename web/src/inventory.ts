// 航海士のバッグと装備。items を増やせば、港で見つけた道具を同じ契約で追加できる。
// 共有学習記録ではなくプレイヤー個人のゲーム状態なので、アカウント別に端末へ保存する。
import { storage } from "./storage";

export const EQUIPMENT_IDS = ["fishingRod"] as const;
export type EquipmentId = (typeof EQUIPMENT_IDS)[number];

export interface NavigatorInventory {
  items: EquipmentId[];
  equipped: EquipmentId | null;
}

const EMPTY_INVENTORY: NavigatorInventory = {
  items: [],
  equipped: null,
};

function storageKey(uid: string): string {
  return `landfall.navigator.inventory.v1.${uid}`;
}

function isEquipmentId(value: unknown): value is EquipmentId {
  return typeof value === "string" && EQUIPMENT_IDS.includes(value as EquipmentId);
}

export function loadNavigatorInventory(uid: string): NavigatorInventory {
  if (typeof window === "undefined") return { ...EMPTY_INVENTORY };
  try {
    const raw = storage.get(storageKey(uid));
    if (!raw) return { ...EMPTY_INVENTORY };
    const parsed = JSON.parse(raw) as { items?: unknown; equipped?: unknown };
    const items = Array.isArray(parsed.items)
      ? Array.from(new Set(parsed.items.filter(isEquipmentId)))
      : [];
    const equipped =
      isEquipmentId(parsed.equipped) && items.includes(parsed.equipped)
        ? parsed.equipped
        : null;
    return { items, equipped };
  } catch {
    return { ...EMPTY_INVENTORY };
  }
}

export function saveNavigatorInventory(
  uid: string,
  inventory: NavigatorInventory,
): void {
  if (typeof window === "undefined") return;
  storage.set(storageKey(uid), JSON.stringify(inventory));
}
