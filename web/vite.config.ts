import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    // Vite/Rolldownでは、動的import先だけが変わっても親チャンクのファイル名が
    // 据え置かれる場合がある。immutable配信された旧親チャンクとの混在を避けるため、
    // 手続き生成航海士へ戻す公開世代でも、Blender版のimmutableチャンクと
    // 混在しないよう名前空間ごと更新する。
    assetsDir: 'assets/stable-v3',
  },
})
