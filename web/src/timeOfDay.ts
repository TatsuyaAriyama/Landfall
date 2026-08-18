import { useEffect, useState } from "react";

export type TimeOfDay = "morning" | "day" | "evening" | "night";

export interface SeaLightPalette {
  sky: string;
  fog: string;
  sea: string;
  seaDeep: string;
  reflection: string;
  ambient: string;
  keyLight: string;
  fillLight: string;
  stars: number;
  celestial: "sun" | "moon";
}

export const SEA_LIGHT: Record<TimeOfDay, SeaLightPalette> = {
  morning: {
    sky: "#E8B789",
    fog: "#A7C7B9",
    sea: "#5C9F98",
    seaDeep: "#386F70",
    reflection: "#FFE1AE",
    ambient: "#FFE0BD",
    keyLight: "#FFD19B",
    fillLight: "#B9E4D8",
    stars: 0,
    celestial: "sun",
  },
  day: {
    sky: "#77C6D7",
    fog: "#8FC9CC",
    sea: "#3B9299",
    seaDeep: "#246C78",
    reflection: "#FFF0B8",
    ambient: "#E1F7F3",
    keyLight: "#FFF2C2",
    fillLight: "#9DE0D7",
    stars: 0,
    celestial: "sun",
  },
  evening: {
    sky: "#B85F58",
    fog: "#795F5B",
    sea: "#3E7272",
    seaDeep: "#274D55",
    reflection: "#FFC07E",
    ambient: "#F3B79B",
    keyLight: "#FFBD7B",
    fillLight: "#79AFA6",
    stars: 70,
    celestial: "sun",
  },
  night: {
    sky: "#123830",
    fog: "#123830",
    sea: "#1E5348",
    seaDeep: "#123830",
    reflection: "#BFD6C6",
    ambient: "#FFE9C8",
    keyLight: "#EADEBD",
    fillLight: "#5DCAA5",
    stars: 380,
    celestial: "moon",
  },
};

export function timeOfDayAt(date: Date): TimeOfDay {
  const hour = date.getHours();
  if (hour >= 5 && hour < 11) return "morning";
  if (hour >= 11 && hour < 17) return "day";
  if (hour >= 17 && hour < 20) return "evening";
  return "night";
}

function demoOverride(): TimeOfDay | null {
  if (typeof window === "undefined" || window.location.hash !== "#demo") return null;
  const value = new URLSearchParams(window.location.search).get("tod");
  return value === "morning" || value === "day" || value === "evening" || value === "night"
    ? value
    : null;
}

export function useTimeOfDay(): TimeOfDay {
  const read = () => demoOverride() ?? timeOfDayAt(new Date());
  const [value, setValue] = useState<TimeOfDay>(read);

  useEffect(() => {
    const update = () => setValue(read());
    const id = window.setInterval(update, 60_000);
    window.addEventListener("focus", update);
    document.addEventListener("visibilitychange", update);
    return () => {
      window.clearInterval(id);
      window.removeEventListener("focus", update);
      document.removeEventListener("visibilitychange", update);
    };
  }, []);

  return value;
}
