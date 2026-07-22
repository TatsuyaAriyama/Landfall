import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./theme.css";
import App from "./App.tsx";
import { THEME_KEY, applyTheme } from "./views/SettingsDialog.tsx";

// 外観設定(システム/ライト/ダーク)を描画前に反映する。
applyTheme(localStorage.getItem(THEME_KEY));

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
