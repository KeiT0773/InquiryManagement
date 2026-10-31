// Vitest の全テストで共通の設定。vitest.config.mts の test.setupFiles から読み込まれる。
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';
// toBeInTheDocument() などの DOM 向けマッチャーを expect に追加する。
import '@testing-library/jest-dom/vitest';

// 各テストの後に描画した DOM を片付ける。
// Testing Library の自動クリーンアップは globals: true が前提のため、明示的に行う。
afterEach(() => {
  cleanup();
});
