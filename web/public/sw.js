// 旧HTMLが /sw.js を更新確認している端末にも終了処理を届ける互換入口。
// URLと本文をv2へ更新し、v1の終了Workerで止まっている端末にも再度installを起こす。
importScripts("/sw-retire.js?v=2");
