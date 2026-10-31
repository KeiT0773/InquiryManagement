import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, apiDelete, apiGet, apiPatch, apiPost } from './client';

function mockFetch(response: Response | Error) {
  const fetchMock = vi.fn(() =>
    response instanceof Error ? Promise.reject(response) : Promise.resolve(response),
  );
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function jsonResponse(status: number, body: unknown, contentType = 'application/json') {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': contentType } });
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('api/client', () => {
  it('成功したら本文の JSON を返す', async () => {
    const fetchMock = mockFetch(jsonResponse(200, [{ id: 'open' }]));

    await expect(apiGet('/api/lists')).resolves.toEqual([{ id: 'open' }]);
    expect(fetchMock).toHaveBeenCalledWith('/api/lists', { method: 'GET' });
  });

  it('body があれば JSON にして Content-Type を付ける', async () => {
    const fetchMock = mockFetch(jsonResponse(200, {}));

    await apiPatch('/api/inquiries/1', { assignee: null });
    expect(fetchMock).toHaveBeenCalledWith('/api/inquiries/1', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: '{"assignee":null}',
    });
  });

  it('apiPost は body が無ければ本文を付けない。204 は undefined を返す', async () => {
    const fetchMock = mockFetch(new Response(null, { status: 204 }));

    await expect(apiPost('/api/inquiries/sort')).resolves.toBeUndefined();
    expect(fetchMock).toHaveBeenCalledWith('/api/inquiries/sort', { method: 'POST' });
  });

  it('失敗の応答は Problem Details の detail を持つ ApiError にする', async () => {
    mockFetch(
      jsonResponse(
        422,
        { title: 'Unprocessable Content', status: 422, detail: '件名を入力してください' },
        'application/problem+json',
      ),
    );

    const error = await apiPost('/api/inquiries', {}).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 422, message: '件名を入力してください' });
  });

  it('detail が無ければ title、本文が読めなければ HTTP ステータスの文言を使う', async () => {
    mockFetch(jsonResponse(404, { title: 'Not Found' }));
    await expect(apiDelete('/api/inquiries/1')).rejects.toMatchObject({
      status: 404,
      message: 'Not Found',
    });

    mockFetch(new Response('<html>', { status: 502, statusText: 'Bad Gateway' }));
    await expect(apiGet('/api/lists')).rejects.toMatchObject({
      status: 502,
      message: 'Bad Gateway',
    });
  });

  it('サーバーに接続できなければ status が null の ApiError にする', async () => {
    mockFetch(new TypeError('Failed to fetch'));

    await expect(apiGet('/api/lists')).rejects.toMatchObject({
      status: null,
      message: 'サーバーに接続できません',
    });
  });
});
