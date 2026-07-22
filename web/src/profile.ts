import { t } from "./i18n";
import { trimAll } from "./types";

// プレイヤープロフィール。iOS と同じくローカル先行(localStorage)。
// 港に入っているときだけメンバー情報として共有される。

const NAME_KEY = "player.name";
const STYLE_KEY = "player.style";
const SYMBOL_KEY = "player.symbol";
const RESOLVE_KEY = "player.resolve";

export const PlayerProfile = {
  get name(): string {
    return trimAll(localStorage.getItem(NAME_KEY) ?? "");
  },
  get styleToken(): string {
    return localStorage.getItem(STYLE_KEY) ?? "midnight";
  },
  get symbolToken(): string {
    return localStorage.getItem(SYMBOL_KEY) ?? "phoenix";
  },
  get resolve(): string {
    return trimAll(localStorage.getItem(RESOLVE_KEY) ?? "");
  },

  /// 表示名。未設定なら「船乗り」。
  get displayName(): string {
    return this.name || t("sailor");
  },

  save(data: { name: string; styleToken: string; symbolToken: string; resolve: string }) {
    localStorage.setItem(NAME_KEY, trimAll(data.name));
    localStorage.setItem(STYLE_KEY, data.styleToken);
    localStorage.setItem(SYMBOL_KEY, data.symbolToken);
    localStorage.setItem(RESOLVE_KEY, trimAll(data.resolve));
  },

  /// 港(プライベート/パブリック共通)のメンバードキュメントに書くプロフィール一式。
  /// 長さは Firestore ルールの上限に合わせて切り詰める(iOS の harborProfileData と同じ)。
  harborProfileData(): Record<string, string> {
    return {
      displayName: this.displayName.slice(0, 60),
      styleToken: this.styleToken.slice(0, 24),
      symbolToken: this.symbolToken.slice(0, 24),
      resolve: this.resolve.slice(0, 80),
    };
  },
};
