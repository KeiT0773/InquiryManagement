// fetch の共通処理（フロントエンド設計書 6.1・6.2）。
// 個々の API（lists.ts、inquiries.ts）はこれを呼ぶだけの薄い関数にする。

// 開発時は http://localhost:3001、本番は空文字（同じドメインの /api）。ビルド時に値が埋め込まれる
const BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? '';

// API の失敗はこの 1 種類にそろえる。status が null なら、サーバーに到達できなかった
export class ApiError extends Error {
  constructor(
    readonly status: number | null,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const init: RequestInit = { method };
  if (body !== undefined) {
    init.headers = { 'Content-Type': 'application/json' };
    init.body = JSON.stringify(body);
  }

  let response: Response;
  try {
    response = await fetch(BASE_URL + path, init);
  } catch {
    // サーバー停止、ネットワーク未接続、CORS の拒否など
    throw new ApiError(null, 'サーバーに接続できません');
  }

  if (!response.ok) {
    throw new ApiError(response.status, await problemDetail(response));
  }
  if (response.status === 204) {
    return undefined as T;
  }
  return (await response.json()) as T;
}

// 失敗の応答（Problem Details。API 設計書 2.1）から表示用の説明を取り出す。
// 本文が読めなければ title、それも無ければ HTTP ステータスの文言を使う
async function problemDetail(response: Response): Promise<string> {
  try {
    const problem = (await response.json()) as { detail?: unknown; title?: unknown };
    if (typeof problem.detail === 'string' && problem.detail !== '') return problem.detail;
    if (typeof problem.title === 'string' && problem.title !== '') return problem.title;
  } catch {
    // 本文が JSON でない
  }
  return response.statusText || `HTTP ${response.status}`;
}

export function apiGet<T>(path: string): Promise<T> {
  return request<T>('GET', path);
}

// body が undefined のときは本文を付けない（POST /api/inquiries/sort のため）
export function apiPost<TBody, T>(path: string, body?: TBody): Promise<T> {
  return request<T>('POST', path, body);
}

export function apiPatch<TBody, T>(path: string, body: TBody): Promise<T> {
  return request<T>('PATCH', path, body);
}

export function apiPut<TBody, T>(path: string, body: TBody): Promise<T> {
  return request<T>('PUT', path, body);
}

export function apiDelete<T>(path: string): Promise<T> {
  return request<T>('DELETE', path);
}
