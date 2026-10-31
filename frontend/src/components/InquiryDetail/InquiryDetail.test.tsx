import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '@/api/client';
import { lists, makeInquiry } from '@/test/fixtures';
import type { Inquiry } from '@/types/inquiry';
import { InquiryDetail } from './InquiryDetail';

const inquiry = makeInquiry(1, 'open', 0, {
  title: 'ログインできない',
  customerName: '山田 太郎',
  contact: 'yamada@example.com',
  category: 'bug',
  content: '戻される',
  assignee: '小林',
  dueOn: '2026-11-01',
  priority: 'high',
  receivedOn: '2026-10-30',
});

function renderDetail(
  overrides: Partial<{
    inquiry: Inquiry;
    onSave: () => Promise<void>;
    onMove: () => Promise<void>;
    onDelete: () => Promise<void>;
  }> = {},
) {
  const props = {
    inquiry,
    onSave: vi.fn(() => Promise.resolve()),
    onMove: vi.fn(() => Promise.resolve()),
    onDelete: vi.fn(() => Promise.resolve()),
    onClose: vi.fn(),
    ...overrides,
  };
  render(<InquiryDetail {...props} lists={lists} />);
  return { user: userEvent.setup(), ...props };
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe('InquiryDetail', () => {
  it('全項目を表示し、件名にフォーカスを当てる', () => {
    renderDetail();

    expect(screen.getByRole('dialog', { name: '問い合わせ詳細' })).toBeInTheDocument();
    expect(screen.getByLabelText('件名')).toHaveValue('ログインできない');
    expect(screen.getByLabelText('件名')).toHaveFocus();
    expect(screen.getByLabelText('問い合わせ者')).toHaveValue('山田 太郎');
    expect(screen.getByLabelText('連絡先')).toHaveValue('yamada@example.com');
    expect(screen.getByLabelText('種別')).toHaveValue('bug');
    expect(screen.getByLabelText('ステータス')).toHaveValue('open');
    expect(screen.getByLabelText('対応期限')).toHaveValue('2026-11-01');
    expect(screen.getByLabelText('問い合わせ内容')).toHaveValue('戻される');
    expect(screen.getByLabelText('対応メモ')).toHaveValue('');
    expect(screen.getByLabelText('対応者')).toHaveValue('小林');
    expect(screen.getByRole('radio', { name: '高' })).toBeChecked();
    expect(screen.getByText('受付日 2026/10/30')).toBeInTheDocument();
  });

  it('確定した項目だけを送る（blur・Enter）。変えていなければ送らない', async () => {
    const { user, onSave } = renderDetail();

    await user.click(screen.getByLabelText('連絡先')); // 件名から離れるが、変えていない
    expect(onSave).not.toHaveBeenCalled();

    await user.clear(screen.getByLabelText('件名'));
    await user.type(screen.getByLabelText('件名'), ' 再発 {Enter}');
    expect(onSave).toHaveBeenLastCalledWith({ title: '再発' });
    await waitFor(() => expect(screen.getByLabelText('件名')).toHaveValue('再発'));

    await user.type(screen.getByLabelText('対応メモ'), '確認中');
    await user.click(screen.getByLabelText('対応者'));
    expect(onSave).toHaveBeenLastCalledWith({ memo: '確認中' });
    expect(onSave).toHaveBeenCalledTimes(2);
  });

  it('任意項目を空（空白だけを含む）にしたら null を送る', async () => {
    const { user, onSave } = renderDetail();

    await user.clear(screen.getByLabelText('対応者'));
    await user.type(screen.getByLabelText('対応者'), '　{Enter}');
    expect(onSave).toHaveBeenLastCalledWith({ assignee: null });

    await user.clear(screen.getByLabelText('対応期限'));
    expect(onSave).toHaveBeenLastCalledWith({ dueOn: null });
  });

  it('必須項目を空にしたら送らず、元の値に戻す', async () => {
    const { user, onSave } = renderDetail();

    await user.clear(screen.getByLabelText('問い合わせ者'));
    await user.tab();

    expect(onSave).not.toHaveBeenCalled();
    expect(screen.getByLabelText('問い合わせ者')).toHaveValue('山田 太郎');
  });

  it('種別・優先度は選んだときに送る', async () => {
    const { user, onSave } = renderDetail();

    await user.selectOptions(screen.getByLabelText('種別'), 'request');
    expect(onSave).toHaveBeenLastCalledWith({ category: 'request' });
    await user.click(screen.getByRole('radio', { name: '低' }));
    await waitFor(() => expect(onSave).toHaveBeenLastCalledWith({ priority: 'low' }));
  });

  it('保存に失敗したら、その項目の下に文言を出し、下書きは残す', async () => {
    const { user } = renderDetail({
      onSave: vi.fn(() => Promise.reject(new ApiError(422, '件名は100文字以内で入力してください'))),
    });

    await user.clear(screen.getByLabelText('件名'));
    await user.type(screen.getByLabelText('件名'), '新しい件名{Enter}');

    expect(await screen.findByRole('alert')).toHaveTextContent(
      '件名は100文字以内で入力してください',
    );
    expect(screen.getByLabelText('件名')).toHaveValue('新しい件名');
  });

  it('ステータスを選び直したら onMove を呼ぶ。失敗したら文言を出して選択を戻す', async () => {
    const onMove = vi.fn(() => Promise.reject(new ApiError(500, 'x')));
    const { user, onSave } = renderDetail({ onMove });

    await user.selectOptions(screen.getByLabelText('ステータス'), 'closed');

    expect(onMove).toHaveBeenCalledWith('closed');
    expect(onSave).not.toHaveBeenCalled();
    expect(await screen.findByRole('alert')).toHaveTextContent('サーバーでエラーが発生しました。');
    expect(screen.getByLabelText('ステータス')).toHaveValue('open');
  });

  it('削除は確認ダイアログで OK のときだけ行う', async () => {
    const confirm = vi
      .spyOn(window, 'confirm')
      .mockReturnValueOnce(false)
      .mockReturnValueOnce(true);
    const { user, onDelete } = renderDetail();

    await user.click(screen.getByRole('button', { name: '問い合わせを削除' }));
    expect(confirm).toHaveBeenCalledWith(
      '問い合わせ「ログインできない」を削除しますか？\nこの操作は取り消せません。',
    );
    expect(onDelete).not.toHaveBeenCalled();

    await user.click(screen.getByRole('button', { name: '問い合わせを削除' }));
    expect(onDelete).toHaveBeenCalledTimes(1);
  });

  it('削除に失敗したらフッターに文言を出し、開いたままにする', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    const { user } = renderDetail({
      onDelete: vi.fn(() => Promise.reject(new ApiError(null, 'x'))),
    });

    await user.click(screen.getByRole('button', { name: '問い合わせを削除' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      '削除できませんでした。サーバーに接続できません。',
    );
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });

  it('「閉じる」・背景のクリック・Escape で閉じる', async () => {
    const { user, onClose } = renderDetail();

    await user.click(screen.getByRole('button', { name: '閉じる' }));
    await user.click(screen.getByTestId('detail-overlay'));
    await user.keyboard('{Escape}');
    // ダイアログの中のクリックでは閉じない
    await user.click(screen.getByText('受付日 2026/10/30'));

    expect(onClose).toHaveBeenCalledTimes(3);
  });
});
