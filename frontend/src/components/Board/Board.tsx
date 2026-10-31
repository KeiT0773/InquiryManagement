'use client';

// ボード（3 列の親）。雛形の段階では、API につながることを確かめるためにリストの名前だけを表示する。
// 列・カード・登録・詳細は画面の実装（フロントエンド設計書 4.・5.）で作る。
import { useEffect, useState } from 'react';
import { ApiError } from '@/api/client';
import { getLists } from '@/api/lists';
import type { BoardList } from '@/types/inquiry';
import styles from './Board.module.css';

export default function Board() {
  const [lists, setLists] = useState<BoardList[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getLists().then(setLists, (e: unknown) =>
      setError(e instanceof ApiError ? e.message : '読み込みに失敗しました'),
    );
  }, []);

  if (error) return <p className={styles.message}>{error}</p>;
  if (!lists) return <p className={styles.message}>読み込み中…</p>;

  return (
    <main className={styles.board}>
      {lists.map((list) => (
        <section key={list.id} className={styles.list}>
          <h2 className={styles.listName}>{list.name}</h2>
        </section>
      ))}
    </main>
  );
}
