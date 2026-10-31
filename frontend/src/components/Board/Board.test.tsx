import { render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import Board from './Board';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('Board', () => {
  it('API から取得したリストの名前を表示する', async () => {
    const lists = [
      { id: 'open', name: '未対応', displayOrder: 0 },
      { id: 'working', name: '対応中', displayOrder: 1 },
      { id: 'closed', name: '完了', displayOrder: 2 },
    ];
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.resolve(Response.json(lists))),
    );

    render(<Board />);

    expect(screen.getByText('読み込み中…')).toBeInTheDocument();
    expect((await screen.findAllByRole('heading', { level: 2 })).map((h) => h.textContent)).toEqual(
      ['未対応', '対応中', '完了'],
    );
  });

  it('API に接続できなければその旨を表示する', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.reject(new TypeError('Failed to fetch'))),
    );

    render(<Board />);

    expect(await screen.findByText('サーバーに接続できません')).toBeInTheDocument();
  });
});
