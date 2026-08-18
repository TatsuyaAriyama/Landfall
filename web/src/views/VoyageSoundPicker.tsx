import { useEffect, useRef, useState } from "react";
import type { SoundMode } from "../audio";
import { t, type I18nKey } from "../i18n";

const SOUND_OPTIONS: ReadonlyArray<{
  value: SoundMode;
  label: I18nKey;
  subtitle: I18nKey;
  icon: string;
}> = [
  { value: "off", label: "soundOff", subtitle: "soundOffSubtitle", icon: "×" },
  { value: "waves", label: "soundWaves", subtitle: "soundWavesSubtitle", icon: "♪" },
  {
    value: "harbor_minuet_main_theme",
    label: "soundHarborMinuet",
    subtitle: "originalSoundtrack",
    icon: "♪",
  },
  {
    value: "beacon_rondo",
    label: "soundBeaconRondo",
    subtitle: "originalSoundtrack",
    icon: "♪",
  },
  {
    value: "celestial_navigation_nocturne",
    label: "soundCelestialNocturne",
    subtitle: "originalSoundtrack",
    icon: "♪",
  },
  {
    value: "approaching_evolution",
    label: "soundApproachingEvolution",
    subtitle: "originalSoundtrack",
    icon: "♪",
  },
];

export function VoyageSoundList({
  value,
  onChange,
  className = "",
}: {
  value: SoundMode;
  onChange: (value: SoundMode) => void;
  className?: string;
}) {
  return (
    <div
      className={`voyage-sound-picker ${className}`.trim()}
      role="listbox"
      aria-label={t("voyagePlaylist")}
    >
      <div className="voyage-sound-picker-heading">
        <span>{t("voyagePlaylist")}</span>
        <span>{t("selectTrack")}</span>
      </div>
      {SOUND_OPTIONS.map((option) => {
        const checked = option.value === value;
        return (
          <button
            type="button"
            className={`voyage-sound-option${checked ? " selected" : ""}`}
            key={option.value}
            role="option"
            aria-selected={checked}
            onClick={() => onChange(option.value)}
          >
            <span className="voyage-sound-icon" aria-hidden="true">{option.icon}</span>
            <span className="voyage-sound-copy">
              <span>{t(option.label)}</span>
              <small>{t(option.subtitle)}</small>
            </span>
            {checked && <span className="voyage-sound-check" aria-hidden="true">✓</span>}
          </button>
        );
      })}
    </div>
  );
}

export function VoyageSoundPicker({
  value,
  onChange,
  placement = "up",
  buttonClassName = "",
}: {
  value: SoundMode;
  onChange: (value: SoundMode) => void;
  placement?: "up" | "down";
  buttonClassName?: string;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const selected = SOUND_OPTIONS.find((option) => option.value === value)
    ?? SOUND_OPTIONS[0];

  useEffect(() => {
    if (!open) return;
    const closeOutside = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    window.addEventListener("pointerdown", closeOutside);
    window.addEventListener("keydown", closeOnEscape);
    return () => {
      window.removeEventListener("pointerdown", closeOutside);
      window.removeEventListener("keydown", closeOnEscape);
    };
  }, [open]);

  return (
    <div
      ref={rootRef}
      className={`voyage-sound-control placement-${placement}`}
      data-no-floating-drag
    >
      <button
        type="button"
        className={`voyage-sound-trigger ${buttonClassName}`.trim()}
        onClick={() => setOpen((shown) => !shown)}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={`${t("bgm")}: ${t(selected.label)}`}
      >
        <span aria-hidden="true">♪</span>
        <span>{t("bgm")}</span>
        <span className="voyage-sound-current">{t(selected.label)}</span>
      </button>

      {open && (
        <VoyageSoundList
          value={value}
          onChange={(next) => {
            onChange(next);
            setOpen(false);
          }}
        />
      )}
    </div>
  );
}
