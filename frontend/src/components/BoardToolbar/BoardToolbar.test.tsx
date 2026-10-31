import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { BoardToolbar } from './BoardToolbar';

describe('BoardToolbar', () => {
  it('押すと確認なしに onSort を呼び、終わるまで「並べ替え中…」で押せなくする', async () => {
    const user = userEvent.setup();
    let finish: () => void = () => undefined;
    const onSort = vi.fn(() => new Promise<void>((resolve) => (finish = resolve)));
    render(<BoardToolbar onSort={onSort} />);

    await user.click(screen.getByRole('button', { name: '優先度順に並べ替え' }));

    expect(onSort).toHaveBeenCalledTimes(1);
    expect(screen.getByRole('button', { name: '並べ替え中…' })).toBeDisabled();
    finish();
    expect(await screen.findByRole('button', { name: '優先度順に並べ替え' })).toBeEnabled();
  });

  it('失敗してもボタンは元に戻る（文言は Board が出す）', async () => {
    const user = userEvent.setup();
    render(<BoardToolbar onSort={() => Promise.reject(new Error('x'))} />);

    await user.click(screen.getByRole('button', { name: '優先度順に並べ替え' }));

    expect(await screen.findByRole('button', { name: '優先度順に並べ替え' })).toBeEnabled();
  });
});
