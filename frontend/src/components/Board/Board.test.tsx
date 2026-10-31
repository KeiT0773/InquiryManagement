import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  jsonResponse,
  makeInquiry,
  noContent,
  problemResponse,
  stubFetch,
  writes,
} from '@/test/fixtures';
import { Board } from './Board';

const inquiries = [
  makeInquiry(1, 'open', 0, { title: 'ログインできない', priority: 'high' }),
  makeInquiry(2, 'open', 1, { title: '請求書の再発行' }),
  makeInquiry(3, 'working', 0, { title: 'プラン変更' }),
];

const column = (name: string) => screen.getByRole('region', { name });

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('Board', () => {
  it('3 列に振り分けて件数とともに表示する。登録フォームは「未対応」にだけある', async () => {
    stubFetch(inquiries);
    render(<Board />);
    expect(screen.getByText('読み込み中…')).toBeInTheDocument();

    expect(await screen.findByRole('region', { name: '未対応' })).toBeInTheDocument();
    expect(within(column('未対応')).getByText('2件')).toBeInTheDocument();
    expect(within(column('対応中')).getByText('プラン変更')).toBeInTheDocument();
    expect(within(column('完了')).getByText('0件')).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: '＋ 問い合わせを登録' })).toHaveLength(1);
    expect(
      within(column('未対応')).getByRole('button', { name: '＋ 問い合わせを登録' }),
    ).toBeInTheDocument();
  });

  it('取得に失敗したらボードの代わりに文言を出す', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.resolve(problemResponse(500, 'boom'))),
    );
    render(<Board />);

    expect(await screen.findByRole('alert')).toHaveTextContent('サーバーでエラーが発生しました。');
  });

  it('登録すると「未対応」を取り直し、サーバーが並べ直した順で表示する', async () => {
    const created = makeInquiry(9, 'open', 1, { title: '新しい問い合わせ', priority: 'high' });
    let server = inquiries;
    const fetchMock = stubFetch(inquiries, (path, init) => {
      if (path === '/api/inquiries' && init?.method === 'POST') {
        server = [inquiries[0], created, inquiries[1], inquiries[2]];
        return jsonResponse(created, 201);
      }
      if (path === '/api/inquiries?listId=open') {
        return jsonResponse(server.filter((q) => q.listId === 'open'));
      }
    });
    const user = userEvent.setup();
    render(<Board />);

    await user.click(await screen.findByRole('button', { name: '＋ 問い合わせを登録' }));
    await user.type(screen.getByLabelText('件名'), '新しい問い合わせ');
    await user.type(screen.getByLabelText('問い合わせ者'), '顧客');
    await user.type(screen.getByLabelText('問い合わせ内容'), '内容');
    await user.click(screen.getByRole('radio', { name: '高' }));
    await user.click(screen.getByRole('button', { name: '登録' }));

    await waitFor(() => expect(within(column('未対応')).getByText('3件')).toBeInTheDocument());
    // カード（ドラッグできる要素は role=button）の並びで、新しい問い合わせは 2 番目
    const cards = within(column('未対応'))
      .getAllByRole('button')
      .map((card) => card.textContent ?? '');
    expect(cards.findIndex((text) => text.includes('新しい問い合わせ'))).toBe(1);
    expect(writes(fetchMock)[0]).toEqual([
      'POST',
      '/api/inquiries',
      {
        title: '新しい問い合わせ',
        customerName: '顧客',
        content: '内容',
        category: 'question',
        priority: 'high',
      },
    ]);
  });

  it('カードを押すと最新の 1 件を取り直してから詳細を開く', async () => {
    const latest = { ...inquiries[1], memo: 'ほかのメンバーのメモ' };
    const fetchMock = stubFetch(inquiries, (path) =>
      path === '/api/inquiries/2' ? jsonResponse(latest) : undefined,
    );
    const user = userEvent.setup();
    render(<Board />);

    await user.click(await screen.findByText('請求書の再発行'));

    expect(await screen.findByRole('dialog', { name: '問い合わせ詳細' })).toBeInTheDocument();
    expect(screen.getByLabelText('対応メモ')).toHaveValue('ほかのメンバーのメモ');
    expect(fetchMock.mock.calls.map(([path]) => path)).toContain('/api/inquiries/2');
  });

  it('開こうとした問い合わせが削除されていたら（404）、上部に文言を出して一覧から消す', async () => {
    let server = inquiries;
    stubFetch(inquiries, (path) => {
      if (path === '/api/inquiries/2') {
        server = inquiries.filter((q) => q.id !== 2);
        return problemResponse(404, '問い合わせが見つかりません: id=2');
      }
      if (path === '/api/inquiries') return jsonResponse(server);
    });
    const user = userEvent.setup();
    render(<Board />);

    await user.click(await screen.findByText('請求書の再発行'));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      '問い合わせを開けませんでした。この問い合わせは、ほかのメンバーによって削除されています。',
    );
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.queryByText('請求書の再発行')).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: '閉じる' }));
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('詳細で編集すると、その問い合わせのリストを取り直してカードにも反映する', async () => {
    const updated = { ...inquiries[2], assignee: '中村' };
    stubFetch(inquiries, (path, init) => {
      if (path === '/api/inquiries/3' && init?.method === 'PATCH') return jsonResponse(updated);
      if (path === '/api/inquiries/3') return jsonResponse(inquiries[2]);
      if (path === '/api/inquiries?listId=working') return jsonResponse([updated]);
    });
    const user = userEvent.setup();
    render(<Board />);

    await user.click(await screen.findByText('プラン変更'));
    await user.type(await screen.findByLabelText('対応者'), '中村{Enter}');

    expect(await within(column('対応中')).findByText('対応者 中村')).toBeInTheDocument();
  });

  it('詳細から削除すると、そのリストを取り直して詳細を閉じる', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    stubFetch(inquiries, (path, init) => {
      if (path === '/api/inquiries/1' && init?.method === 'DELETE') return noContent();
      if (path === '/api/inquiries/1') return jsonResponse(inquiries[0]);
      if (path === '/api/inquiries?listId=open') return jsonResponse([inquiries[1]]);
    });
    const user = userEvent.setup();
    render(<Board />);

    await user.click(await screen.findByText('ログインできない'));
    await user.click(await screen.findByRole('button', { name: '問い合わせを削除' }));

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(screen.queryByText('ログインできない')).not.toBeInTheDocument();
    expect(within(column('未対応')).getByText('1件')).toBeInTheDocument();
  });

  it('「優先度順に並べ替え」に失敗したら上部に文言を出す', async () => {
    stubFetch(inquiries, (path) =>
      path === '/api/inquiries/sort' ? problemResponse(500, 'boom') : undefined,
    );
    const user = userEvent.setup();
    render(<Board />);

    await user.click(await screen.findByRole('button', { name: '優先度順に並べ替え' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      '並べ替えを保存できませんでした。サーバーでエラーが発生しました。',
    );
  });
});
