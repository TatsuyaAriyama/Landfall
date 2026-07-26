import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    // 旧Service WorkerとSPAフォールバックがHTMLを誤保存した /assets/ URLを
    // 全ファイルまとめて避ける。404ページ導入後の世代だけをこの名前空間で配る。
    assetsDir: 'assets/stable-v1',
  },
})
