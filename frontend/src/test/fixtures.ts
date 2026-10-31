// テストで共通に使うデータと、fetch の差し替え
import { vi } from 'vitest';
import type { BoardList, Inquiry, ListId } from '@/types/inquiry';

export const lists: BoardList[] = [
  { id: 'open', name: '未対応', displayOrder: 0 },
  { id: 'working', name: '対応中', displayOrder: 1 },
  { id: 'closed', name: '完了', displayOrder: 2 },
];

/** 問い合わせを 1 件作る。指定しない項目は無難な値で埋める */
export function makeInquiry(
  id: number,
  listId: ListId,
  displayOrder: number,
  overrides: Partial<Inquiry> = {},
): Inquiry {
  return {
    id,
    title: `問い合わせ${id}`,
    customerName: `顧客${id}`,
    contact: null,
    category: 'question',
    content: `内容${id}`,
    memo: null,
    assignee: null,
    receivedOn: '2026-10-30',
    dueOn: null,
    priority: 'medium',
    listId,
    displayOrder,
    createdAt: '2026-10-30T01:00:00.000Z',
    updatedAt: '2026-10-30T01:00:00.000Z',
    ...overrides,
  };
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export function problemResponse(status: number, detail: string): Response {
  return new Response(JSON.stringify({ title: 'Error', status, detail }), {
    status,
    headers: { 'Content-Type': 'application/problem+json' },
  });
}

export function noContent(): Response {
  return new Response(null, { status: 204 });
}

type Handler = (path: string, init: RequestInit | undefined) => Response | undefined;

/**
 * fetch を差し替える。handler が undefined を返した要求は、一覧の取得として lists・inquiries を返す。
 * 呼ばれ方は戻り値の mock.calls で確かめる
 */
export function stubFetch(inquiries: Inquiry[], handler: Handler = () => undefined) {
  const fetchMock = vi.fn((path: string, init?: RequestInit) => {
    const handled = handler(path, init);
    if (handled !== undefined) return Promise.resolve(handled);
    if (path === '/api/lists') return Promise.resolve(jsonResponse(lists));
    const listId = /^\/api\/inquiries\?listId=(\w+)$/.exec(path)?.[1];
    if (listId !== undefined) {
      return Promise.resolve(jsonResponse(inquiries.filter((q) => q.listId === listId)));
    }
    if (path === '/api/inquiries') return Promise.resolve(jsonResponse(inquiries));
    return Promise.reject(new Error(`想定していない要求: ${init?.method ?? 'GET'} ${path}`));
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

/** fetch の呼ばれ方のうち、書き込み（GET 以外）だけを [メソッド, パス, body] で返す */
export function writes(fetchMock: ReturnType<typeof stubFetch>) {
  return fetchMock.mock.calls
    .filter(([, init]) => init?.method !== undefined && init.method !== 'GET')
    .map(([path, init]) => [
      init?.method,
      path,
      init?.body === undefined ? undefined : JSON.parse(String(init.body)),
    ]);
}
