import { storage } from "./storage";

export interface HarborControlSettings {
  /** Joystick center as a percentage of the harbor viewport. */
  x: number;
  y: number;
  /** Diameter in CSS pixels. */
  size: number;
}

export const HARBOR_CONTROL_SETTINGS_KEY = "landfall.harborControlSettings.v1";
export const HARBOR_CONTROL_SETTINGS_EVENT = "landfall:harbor-control-settings";
export const HARBOR_CONTROL_SIZE_MIN = 104;
export const HARBOR_CONTROL_SIZE_MAX = 184;
export const DEFAULT_HARBOR_CONTROL_SETTINGS: HarborControlSettings = {
  x: 82,
  y: 68,
  size: 142,
};

const finite = (value: unknown, fallback: number) =>
  typeof value === "number" && Number.isFinite(value) ? value : fallback;

export function normalizeHarborControlSettings(
  value: Partial<HarborControlSettings> | null | undefined,
): HarborControlSettings {
  return {
    x: Math.min(95, Math.max(5, finite(value?.x, DEFAULT_HARBOR_CONTROL_SETTINGS.x))),
    y: Math.min(92, Math.max(8, finite(value?.y, DEFAULT_HARBOR_CONTROL_SETTINGS.y))),
    size: Math.round(
      Math.min(
        HARBOR_CONTROL_SIZE_MAX,
        Math.max(
          HARBOR_CONTROL_SIZE_MIN,
          finite(value?.size, DEFAULT_HARBOR_CONTROL_SETTINGS.size),
        ),
      ),
    ),
  };
}

export function loadHarborControlSettings(): HarborControlSettings {
  const saved = storage.get(HARBOR_CONTROL_SETTINGS_KEY);
  if (!saved) return DEFAULT_HARBOR_CONTROL_SETTINGS;
  try {
    return normalizeHarborControlSettings(
      JSON.parse(saved) as Partial<HarborControlSettings>,
    );
  } catch {
    return DEFAULT_HARBOR_CONTROL_SETTINGS;
  }
}

export function saveHarborControlSettings(
  value: HarborControlSettings,
): HarborControlSettings {
  const next = normalizeHarborControlSettings(value);
  storage.set(HARBOR_CONTROL_SETTINGS_KEY, JSON.stringify(next));
  window.dispatchEvent(
    new CustomEvent<HarborControlSettings>(HARBOR_CONTROL_SETTINGS_EVENT, {
      detail: next,
    }),
  );
  return next;
}
