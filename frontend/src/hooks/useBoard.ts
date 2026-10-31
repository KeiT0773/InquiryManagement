import { useCallback, useEffect, useRef, useState } from 'react';
import { ApiError } from '@/api/client';
import {
  createInquiry,
  deleteInquiry as deleteInquiryApi,
  getInquiries,
  getInquiry,
  moveInquiry as moveInquiryApi,
  sortInquiries,
  updateInquiry as updateInquiryApi,
} from '@/api/inquiries';
import { getLists } from '@/api/lists';
import type {
  BoardList,
  Inquiry,
  InquiryCreateInput,
  InquiryMoveInput,
  InquiryUpdateInput,
  ListId,
} from '@/types/inquiry';
import { applyMove } from '@/utils/board';

export type BoardState = {
  lists: BoardList[];
  inquiries: Inquiry[];
  loading: boolean;
  /** 取得に失敗した場合のエラー（ボードを表示できない状態） */
  error: ApiError | null;
  /** 登録する（5.3）。失敗したときは ApiError を投げる */
  addInquiry: (input: InquiryCreateInput) => Promise<void>;
  /** 最新の 1 件を取り直す（詳細を開くとき。5.4）。失敗したときは ApiError を投げる */
  refreshInquiry: (id: number) => Promise<void>;
  /** 送った項目だけを編集する（5.5）。失敗したときは ApiError を投げる */
  updateInquiry: (id: number, input: InquiryUpdateInput) => Promise<void>;
  /** 移動・並べ替え（5.6）。displayOrder があれば楽観更新し、失敗したら元に戻して ApiError を投げる */
  moveInquiry: (id: number, to: InquiryMoveInput) => Promise<void>;
  /** 全リストを優先度順に並べ直す（5.7）。失敗したときは ApiError を投げる */
  sortByPriority: () => Promise<void>;
  /** 削除する（5.8）。失敗したときは ApiError を投げる */
  deleteInquiry: (id: number) => Promise<void>;
};

function toApiError(e: unknown): ApiError {
  return e instanceof ApiError ? e : new ApiError(null, String(e));
}

/**
 * ボードの表示に必要なリストと問い合わせを取得して保持し、登録・編集・移動・並べ替え・削除も受け持つ
 * （フロントエンド設計書 5.）。一覧を持っているのはこのフックだけで、部品は渡された関数を呼ぶだけにする。
 */
export function useBoard(): BoardState {
  const [lists, setLists] = useState<BoardList[]>([]);
  const [inquiries, setInquiries] = useState<Inquiry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<ApiError | null>(null);
  // 非同期処理の途中で最新の一覧を参照するための ref（移動元・削除した問い合わせのリストを引く）
  const inquiriesRef = useRef<Inquiry[]>(inquiries);
  useEffect(() => {
    inquiriesRef.current = inquiries;
  }, [inquiries]);

  useEffect(() => {
    // 部品が消えた後に応答が返っても状態を更新しないためのフラグ。
    // React の開発モードでは useEffect が 2 回実行されるため、これが無いと二重に更新される
    let cancelled = false;

    Promise.all([getLists(), getInquiries()])
      .then(([fetchedLists, fetchedInquiries]) => {
        if (cancelled) return;
        setLists(fetchedLists);
        setInquiries(fetchedInquiries);
        setError(null);
      })
      .catch((e: unknown) => {
        if (!cancelled) setError(toApiError(e));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const reloadAll = useCallback(async () => {
    setInquiries(await getInquiries());
  }, []);

  /**
   * 1 つのリストを取り直し、一覧のうちそのリストの分だけを置き換える。
   * 直前の状態を引数に取る形にし、ほかの操作で変わった内容を上書きしないようにする
   */
  const reloadList = useCallback(async (listId: ListId) => {
    const fetched = await getInquiries(listId);
    setInquiries((prev) => [...prev.filter((q) => q.listId !== listId), ...fetched]);
  }, []);

  /**
   * 操作を実行し、404（ほかのメンバーが削除した）なら全件を取り直してから投げ直す（5.2）。
   * 取り直しによって、画面からその問い合わせが消える
   */
  const run = useCallback(
    async (operation: () => Promise<void>) => {
      try {
        await operation();
      } catch (e: unknown) {
        const apiError = toApiError(e);
        if (apiError.status === 404) {
          await reloadAll().catch(() => undefined);
        }
        throw apiError;
      }
    },
    [reloadAll],
  );

  // 登録後はサーバーが「未対応」を並べ直すため、応答の 1 件を差し込まずにリストを取り直す（方針 8）
  const addInquiry = useCallback(
    (input: InquiryCreateInput) =>
      run(async () => {
        const created = await createInquiry(input);
        await reloadList(created.listId);
      }),
    [run, reloadList],
  );

  // 詳細を開く前に、ほかのメンバーの変更を反映した最新の 1 件を取り直す（方針 10）
  const refreshInquiry = useCallback(
    (id: number) =>
      run(async () => {
        const fetched = await getInquiry(id);
        const current = inquiriesRef.current.find((q) => q.id === id);
        if (current === undefined || current.listId !== fetched.listId) {
          // ほかのメンバーが別のリストへ動かしていた。位置が変わるので全件を取り直す
          await reloadAll();
        } else {
          setInquiries((prev) => prev.map((q) => (q.id === id ? fetched : q)));
        }
      }),
    [run, reloadAll],
  );

  // 優先度を変えたときはサーバーが並べ直すため、どの項目の編集でもそのリストを取り直す（方針 8）
  const updateInquiry = useCallback(
    (id: number, input: InquiryUpdateInput) =>
      run(async () => {
        const updated = await updateInquiryApi(id, input);
        await reloadList(updated.listId);
      }),
    [run, reloadList],
  );

  // ドラッグ&ドロップ（displayOrder あり）だけは楽観更新する（方針 9）。
  // 詳細でのステータスの選択（displayOrder なし）は楽観更新しない（5.6）
  const moveInquiry = useCallback(
    (id: number, to: InquiryMoveInput) =>
      run(async () => {
        const fromListId = inquiriesRef.current.find((q) => q.id === id)?.listId ?? null;
        const optimistic = to.displayOrder !== undefined;
        if (optimistic) {
          setInquiries((prev) => applyMove(prev, id, to.listId, to.displayOrder ?? 0));
        }

        try {
          await moveInquiryApi(id, to);
        } catch (e: unknown) {
          // サーバーの状態（＝元の位置）に戻す。404 は run が全件を取り直すので、ここでは取り直さない
          if (optimistic && toApiError(e).status !== 404) {
            await reloadAll().catch(() => undefined);
          }
          throw e;
        }

        await reloadList(to.listId);
        if (fromListId !== null && fromListId !== to.listId) {
          await reloadList(fromListId);
        }
      }),
    [run, reloadAll, reloadList],
  );

  // 3 リストすべての displayOrder が変わりうるので、全件を取り直す。楽観更新はしない（5.7）
  const sortByPriority = useCallback(
    () =>
      run(async () => {
        await sortInquiries();
        await reloadAll();
      }),
    [run, reloadAll],
  );

  // 応答に本文が無いので、要求の前にリストを控えておき、成功後にそのリストを取り直す（5.8）
  const deleteInquiry = useCallback(
    (id: number) =>
      run(async () => {
        const listId = inquiriesRef.current.find((q) => q.id === id)?.listId ?? null;
        await deleteInquiryApi(id);
        if (listId === null) {
          await reloadAll();
        } else {
          await reloadList(listId);
        }
      }),
    [run, reloadAll, reloadList],
  );

  return {
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
  };
}
