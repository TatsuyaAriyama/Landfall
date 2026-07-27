import { boatShareData } from "./boat";
import { t } from "./i18n";
import { dayId, trimAll } from "./types";
import { storage } from "./storage";

// プレイヤープロフィール。iOS と同じくローカル先行(localStorage)。
// 港に入っているときだけメンバー情報として共有される。

const NAME_KEY = "player.name";
const STYLE_KEY = "player.style";
const SYMBOL_KEY = "player.symbol";
const RESOLVE_KEY = "player.resolve";

export const PlayerProfile = {
  get name(): string {
    return trimAll(storage.get(NAME_KEY) ?? "");
  },
  get styleToken(): string {
    return storage.get(STYLE_KEY) ?? "midnight";
  },
  get symbolToken(): string {
    return storage.get(SYMBOL_KEY) ?? "phoenix";
  },
  get resolve(): string {
    return trimAll(storage.get(RESOLVE_KEY) ?? "");
  },

  /// 表示名。未設定なら「船乗り」。
  get displayName(): string {
    return this.name || t("sailor");
  },

  save(data: { name: string; styleToken: string; symbolToken: string; resolve: string }) {
    storage.set(NAME_KEY, trimAll(data.name));
    storage.set(STYLE_KEY, data.styleToken);
    storage.set(SYMBOL_KEY, data.symbolToken);
    storage.set(RESOLVE_KEY, trimAll(data.resolve));
  },

  /// 港(プライベート/パブリック共通)のメンバードキュメントに書くプロフィール一式。
  /// 長さは Firestore ルールの上限に合わせて切り詰める(iOS の harborProfileData と同じ)。
  /// 船の見た目(部位id)も一緒に載せ、港の「みんなの海」に自分の船で並ぶ。
  /// sinceDay は「このサービスを使い始めた日」(since.ts の serviceStartDay)。
  /// 港のメンバーにも見えるので、相手のカードに「◯年◯月◯日から航海中」と出せる。
  harborProfileData(sinceDay?: Date | null): Record<string, string> {
    const boat = Object.fromEntries(
      Object.entries(boatShareData()).map(([key, id]) => [key, id.slice(0, 24)]),
    );
    return {
      displayName: this.displayName.slice(0, 60),
      styleToken: this.styleToken.slice(0, 24),
      symbolToken: this.symbolToken.slice(0, 24),
      resolve: this.resolve.slice(0, 80),
      ...(sinceDay ? { sinceDay: dayId(sinceDay) } : {}),
      ...boat,
    };
  },
};
