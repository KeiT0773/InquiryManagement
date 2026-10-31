import { useState } from 'react';
import styles from './BoardToolbar.module.css';

type Props = {
  /** 「優先度順に並べ替え」を押したとき。失敗の通知は Board が行う */
  onSort: () => Promise<void>;
};

/**
 * ヘッダーとボードの間のツールバー（画面要件書 3.、フロントエンド設計書 8.8）。
 * 「優先度順に並べ替え」ボタンだけを持つ（FR-10）。確認は求めない。
 * 押している間はボタンを無効にして二重送信を防ぐ。
 */
export function BoardToolbar({ onSort }: Props) {
  const [running, setRunning] = useState(false);

  async function handleClick() {
    setRunning(true);
    try {
      await onSort();
    } catch {
      // 失敗の通知は Board が行う。ここではボタンを戻すだけ
    } finally {
      setRunning(false);
    }
  }

  return (
    <div className={styles.toolbar}>
      <button type="button" className={styles.sort} onClick={handleClick} disabled={running}>
        {running ? '並べ替え中…' : '優先度順に並べ替え'}
      </button>
    </div>
  );
}
