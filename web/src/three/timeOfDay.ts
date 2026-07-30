import { useEffect, useState } from "react";

export type TimeOfDay = "morning" | "day" | "evening" | "night";

export const TIME_OF_DAY = {
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
} as const;

export function currentTimeOfDay(date = new Date()): TimeOfDay {
  const hour = date.getHours();
  if (hour >= 5 && hour < 10) return "morning";
  if (hour >= 10 && hour < 17) return "day";
  if (hour >= 17 && hour < 20) return "evening";
  return "night";
}

/// ログイン画面を開いたまま時間帯をまたいでも、空と海を現在時刻へ追従させる。
export function useTimeOfDay(): TimeOfDay {
  const [timeOfDay, setTimeOfDay] = useState<TimeOfDay>(() => currentTimeOfDay());

  useEffect(() => {
    const refresh = () => setTimeOfDay(currentTimeOfDay());
    const timer = window.setInterval(refresh, 60_000);
    const onVisibility = () => {
      if (document.visibilityState === "visible") refresh();
    };

    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return timeOfDay;
}
