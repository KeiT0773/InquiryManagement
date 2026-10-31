'use client';

import { DragDropContext, type DropResult } from '@hello-pangea/dnd';
import { useCallback, useState } from 'react';
import { ApiError } from '@/api/client';
import { useBoard } from '@/hooks/useBoard';
import type { InquiryUpdateInput, ListId } from '@/types/inquiry';
import { dragEndToMove } from '@/utils/board';
import { errorMessage } from '@/utils/errorMessage';
import { BoardList } from '../BoardList/BoardList';
import { BoardToolbar } from '../BoardToolbar/BoardToolbar';
import { InquiryDetail } from '../InquiryDetail/InquiryDetail';
import styles from './Board.module.css';

/** 問い合わせを登録できるリスト（要件定義書 決定事項 No.10） */
const REGISTER_LIST_ID: ListId = 'open';

/**
 * ボード（SC-01）。リストと問い合わせを取得し、読み込み中・エラー・3 列のいずれかを描画する。
 * 3 列を DragDropContext で包み、ドロップ時に移動を保存する（FR-04、FR-05）。
 * 選択中の問い合わせがあれば、その手前に問い合わせ詳細（SC-02）を重ねる。
 * ここから下の部品はすべてクライアントで動く（ドラッグ&ドロップと、今日の日付による期限超過の判定のため）。
 */
export function Board() {
  const {
    lists,
    inquiries,
    loading,
    error,
    addInquiry,
    refreshInquiry,
    updateInquiry,
    moveInquiry,
    sortByPriority,
    deleteInquiry,
  } = useBoard();
  const [selectedId, setSelectedId] = useState<number | null>(null);
  // 移動・並べ替え・詳細を開く操作に失敗したときの文言。入力欄が無い操作なので、ボードの上部に出す（方針 7）
  const [actionError, setActionError] = useState<{ prefix: string; error: ApiError } | null>(null);
  const closeDetail = useCallback(() => setSelectedId(null), []);

  /** ボード全体に対する操作を実行し、成否を actionError に反映する */
  const runAction = useCallback(async (prefix: string, run: () => Promise<void>) => {
    try {
      await run();
      setActionError(null);
    } catch (e: unknown) {
      setActionError({ prefix, error: e instanceof ApiError ? e : new ApiError(null, String(e)) });
    }
  }, []);

  const handleDragEnd = useCallback(
    (result: DropResult) => {
      const move = dragEndToMove(result);
      if (move === null) return;
      void runAction('移動を保存できませんでした。', () =>
        moveInquiry(move.id, { listId: move.listId, displayOrder: move.displayOrder }),
      );
    },
    [moveInquiry, runAction],
  );

  const handleSort = useCallback(
    () => runAction('並べ替えを保存できませんでした。', sortByPriority),
    [runAction, sortByPriority],
  );

  // 最新の 1 件を取り直してから開く。失敗したら（404 を含む）上部に文言を出し、開かない（5.4）
  const openDetail = useCallback(
    (id: number) =>
      void runAction('問い合わせを開けませんでした。', async () => {
        await refreshInquiry(id);
        setSelectedId(id);
      }),
    [refreshInquiry, runAction],
  );

  // 登録・編集・移動（詳細から）・削除の失敗は、それぞれの部品が入力欄のそばに出すので投げ直す。
  // 成功したときは上部の文言を消す（8.8「次の操作が成功したときにも消える」）
  const succeed = useCallback(
    <T extends unknown[]>(operation: (...args: T) => Promise<void>) =>
      async (...args: T) => {
        await operation(...args);
        setActionError(null);
      },
    [],
  );

  if (loading) {
    return <p className={styles.message}>読み込み中…</p>;
  }

  if (error !== null) {
    return (
      <p className={styles.message} role="alert">
        {errorMessage(error)}
      </p>
    );
  }

  // 選択中の問い合わせは一覧から探す。無くなっていれば（削除後・ほかのメンバーの削除後）詳細は描画しない
  const selected = inquiries.find((q) => q.id === selectedId) ?? null;

  return (
    <>
      <BoardToolbar onSort={handleSort} />
      {actionError !== null && (
        <div className={styles.notice} role="alert">
          <span>
            {actionError.prefix}
            {errorMessage(actionError.error)}
          </span>
          <button type="button" className={styles.noticeClose} onClick={() => setActionError(null)}>
            閉じる
          </button>
        </div>
      )}
      <DragDropContext onDragEnd={handleDragEnd}>
        <main className={styles.board}>
          {lists.map((list) => (
            <BoardList
              key={list.id}
              list={list}
              inquiries={inquiries.filter((q) => q.listId === list.id)}
              onAdd={list.id === REGISTER_LIST_ID ? succeed(addInquiry) : undefined}
              onCardClick={openDetail}
            />
          ))}
        </main>
      </DragDropContext>
      {selected !== null && (
        // key を付け、別の問い合わせを開いたときは下書きを持った部品を作り直す
        <InquiryDetail
          key={selected.id}
          inquiry={selected}
          lists={lists}
          onSave={(input: InquiryUpdateInput) => succeed(updateInquiry)(selected.id, input)}
          onMove={(listId: ListId) => succeed(moveInquiry)(selected.id, { listId })}
          onDelete={async () => {
            await succeed(deleteInquiry)(selected.id);
            closeDetail();
          }}
          onClose={closeDetail}
        />
      )}
    </>
  );
}
