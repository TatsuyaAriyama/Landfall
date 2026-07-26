// 旧HTMLが /sw.js を更新確認している端末にも終了処理を届ける互換入口。
// 実体は新しい固有URLに置き、CDNに残った旧sw.jsを迂回できるようにする。
importScripts("/sw-retire.js?v=1");
