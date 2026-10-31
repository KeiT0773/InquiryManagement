import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// テストの設定（技術スタック 4.）。Next.js の公式の手順（Vitest + React Testing Library + jsdom）に従う
export default defineConfig({
  plugins: [react()],
  resolve: {
    // tsconfig.json の paths（@/* → src/*）と同じ
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
});
