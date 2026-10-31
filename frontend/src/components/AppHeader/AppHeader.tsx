import styles from './AppHeader.module.css';

/** 画面上部の青い帯。アプリ名を表示する（SC-01） */
export function AppHeader() {
  return (
    <header className={styles.header}>
      <h1 className={styles.title}>問い合わせ管理ボード</h1>
    </header>
  );
}
