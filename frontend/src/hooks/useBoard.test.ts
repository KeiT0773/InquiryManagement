import { act, renderHook, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  jsonResponse,
  makeInquiry,
  noContent,
  problemResponse,
  stubFetch,
  writes,
} from '@/test/fixtures';
import type { Inquiry, ListId } from '@/types/inquiry';
import { useBoard } from './useBoard';

// ドラッグ操作そのものは jsdom で再現しにくいため、ドロップ後の処理（moveInquiry）をフック単体で確かめる
// （フロントエンド設計書 11. 保留事項）

const initial = [
  makeInquiry(1, 'open', 0),
  makeInquiry(2, 'open', 1),
  makeInquiry(3, 'working', 0),
];

const idsIn = (inquiries: Inquiry[], listId: ListId) =>
  inquiries.filter((q) => q.listId === listId).map((q) => q.id);

async function renderBoard() {
  const hook = renderHook(() => useBoard());
  await waitFor(() => expect(hook.result.current.loading).toBe(false));
  return hook;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('useBoard', () => {
  it('リストと問い合わせを同時に取得する', async () => {
    stubFetch(initial);
    const { result } = await renderBoard();

    expect(result.current.lists.map((l) => l.id)).toEqual(['open', 'working', 'closed']);
    expect(result.current.inquiries).toEqual(initial);
    expect(result.current.error).toBeNull();
  });

  it('取得に失敗したら error に入れる', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.reject(new TypeError('Failed to fetch'))),
    );
    const { result } = await renderBoard();

    expect(result.current.error?.status).toBeNull();
  });

  it('登録したら「未対応」だけを取り直す', async () => {
    const created = makeInquiry(9, 'open', 0, { priority: 'high' });
    let server = initial;
    const fetchMock = stubFetch(initial, (path, init) => {
      if (path === '/api/inquiries' && init?.method === 'POST') {
        server = [created, ...initial];
        return jsonResponse(created, 201);
      }
      if (path === '/api/inquiries?listId=open') {
        return jsonResponse(server.filter((q) => q.listId === 'open'));
      }
    });
    const { result } = await renderBoard();

    await act(() =>
      result.current.addInquiry({
        title: '件名',
        customerName: '顧客',
        content: '内容',
        category: 'bug',
        priority: 'high',
      }),
    );

    expect(idsIn(result.current.inquiries, 'open')).toEqual([9, 1, 2]);
    expect(idsIn(result.current.inquiries, 'working')).toEqual([3]);
    expect(writes(fetchMock)).toEqual([
      [
        'POST',
        '/api/inquiries',
        { title: '件名', customerName: '顧客', content: '内容', category: 'bug', priority: 'high' },
      ],
    ]);
  });

  it('ドロップでは先に手元の並びを変え、成功したら移動元・移動先を取り直す', async () => {
    let resolveMove: (response: Response) => void = () => undefined;
    const after = [
      makeInquiry(2, 'open', 0),
      makeInquiry(1, 'working', 0),
      makeInquiry(3, 'working', 1),
    ];
    const fetchMock = stubFetch(initial, (path, init) => {
      if (init?.method === 'PUT') {
        return undefined; // 下の mockImplementationOnce で返す
      }
      const listId = /listId=(\w+)/.exec(path)?.[1];
      if (listId !== undefined) return jsonResponse(after.filter((q) => q.listId === listId));
    });
    const { result } = await renderBoard();
    fetchMock.mockImplementationOnce(
      () => new Promise<Response>((resolve) => (resolveMove = resolve)),
    );

    let moving: Promise<void> = Promise.resolve();
    act(() => {
      moving = result.current.moveInquiry(1, { listId: 'working', displayOrder: 0 });
    });
    // 応答を待たずに、ドロップした位置に見えている
    expect(idsIn(result.current.inquiries, 'working')).toEqual([1, 3]);

    await act(async () => {
      resolveMove(jsonResponse(makeInquiry(1, 'working', 0)));
      await moving;
    });
    expect(writes(fetchMock)).toEqual([
      ['PUT', '/api/inquiries/1/position', { listId: 'working', displayOrder: 0 }],
    ]);
    const paths = fetchMock.mock.calls.map(([path]) => path);
    expect(paths).toContain('/api/inquiries?listId=working');
    expect(paths).toContain('/api/inquiries?listId=open');
    expect(idsIn(result.current.inquiries, 'open')).toEqual([2]);
  });

  it('ドロップの保存に失敗したら全件を取り直して元に戻し、ApiError を投げる', async () => {
    stubFetch(initial, (_path, init) =>
      init?.method === 'PUT' ? problemResponse(500, 'boom') : undefined,
    );
    const { result } = await renderBoard();

    await act(async () => {
      await expect(
        result.current.moveInquiry(1, { listId: 'working', displayOrder: 0 }),
      ).rejects.toMatchObject({ status: 500 });
    });

    expect(idsIn(result.current.inquiries, 'open')).toEqual([1, 2]);
    expect(idsIn(result.current.inquiries, 'working')).toEqual([3]);
  });

  it('詳細からのステータス変更（displayOrder なし）は楽観更新しない', async () => {
    const fetchMock = stubFetch(initial, (_path, init) =>
      init?.method === 'PUT' ? problemResponse(500, 'boom') : undefined,
    );
    const { result } = await renderBoard();
    const before = result.current.inquiries;

    await act(async () => {
      await expect(result.current.moveInquiry(1, { listId: 'closed' })).rejects.toBeDefined();
    });

    expect(writes(fetchMock)).toEqual([['PUT', '/api/inquiries/1/position', { listId: 'closed' }]]);
    expect(result.current.inquiries).toBe(before);
  });

  it('404（ほかのメンバーが削除した）なら全件を取り直してから ApiError を投げる', async () => {
    let server = initial;
    stubFetch(initial, (path, init) => {
      if (init?.method === 'PATCH') {
        server = initial.filter((q) => q.id !== 1);
        return problemResponse(404, '問い合わせが見つかりません: id=1');
      }
      if (path === '/api/inquiries') return jsonResponse(server);
    });
    const { result } = await renderBoard();

    await act(async () => {
      await expect(result.current.updateInquiry(1, { assignee: '小林' })).rejects.toMatchObject({
        status: 404,
      });
    });

    expect(result.current.inquiries.map((q) => q.id)).toEqual([2, 3]);
  });

  it('編集したら、応答の問い合わせのリストを取り直す', async () => {
    const updated = makeInquiry(3, 'working', 0, { assignee: '小林' });
    const fetchMock = stubFetch(initial, (path, init) => {
      if (init?.method === 'PATCH') return jsonResponse(updated);
      if (path === '/api/inquiries?listId=working') return jsonResponse([updated]);
    });
    const { result } = await renderBoard();

    await act(() => result.current.updateInquiry(3, { assignee: '小林' }));

    expect(result.current.inquiries.find((q) => q.id === 3)?.assignee).toBe('小林');
    expect(writes(fetchMock)).toEqual([['PATCH', '/api/inquiries/3', { assignee: '小林' }]]);
  });

  it('詳細を開く前の取り直しは、その 1 件だけを置き換える', async () => {
    const latest = makeInquiry(2, 'open', 1, { memo: 'ほかのメンバーが書いたメモ' });
    stubFetch(initial, (path) => (path === '/api/inquiries/2' ? jsonResponse(latest) : undefined));
    const { result } = await renderBoard();

    await act(() => result.current.refreshInquiry(2));

    expect(result.current.inquiries.find((q) => q.id === 2)?.memo).toBe(
      'ほかのメンバーが書いたメモ',
    );
    expect(result.current.inquiries.map((q) => q.id)).toEqual([1, 2, 3]);
  });

  it('全リストの並べ替えのあとは全件を取り直す', async () => {
    const sorted = [
      makeInquiry(2, 'open', 0),
      makeInquiry(1, 'open', 1),
      makeInquiry(3, 'working', 0),
    ];
    let server = initial;
    const fetchMock = stubFetch(initial, (path) => {
      if (path === '/api/inquiries/sort') {
        server = sorted;
        return noContent();
      }
      if (path === '/api/inquiries') return jsonResponse(server);
    });
    const { result } = await renderBoard();

    await act(() => result.current.sortByPriority());

    expect(idsIn(result.current.inquiries, 'open')).toEqual([2, 1]);
    expect(writes(fetchMock)).toEqual([['POST', '/api/inquiries/sort', undefined]]);
  });

  it('削除したら、その問い合わせがあったリストを取り直す', async () => {
    const fetchMock = stubFetch(initial, (path, init) => {
      if (init?.method === 'DELETE') return noContent();
      if (path === '/api/inquiries?listId=open') return jsonResponse([makeInquiry(2, 'open', 0)]);
    });
    const { result } = await renderBoard();

    await act(() => result.current.deleteInquiry(1));

    expect(idsIn(result.current.inquiries, 'open')).toEqual([2]);
    expect(writes(fetchMock)).toEqual([['DELETE', '/api/inquiries/1', undefined]]);
  });
});
