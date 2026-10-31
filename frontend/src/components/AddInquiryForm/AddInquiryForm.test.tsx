import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ApiError } from '@/api/client';
import { AddInquiryForm } from './AddInquiryForm';

async function openForm(onSubmit = vi.fn(() => Promise.resolve())) {
  const user = userEvent.setup();
  render(<AddInquiryForm onSubmit={onSubmit} />);
  await user.click(screen.getByRole('button', { name: '＋ 問い合わせを登録' }));
  return { user, onSubmit };
}

describe('AddInquiryForm', () => {
  it('開くと件名にフォーカスが当たり、種別は質問・優先度は中が選ばれている', async () => {
    await openForm();

    expect(screen.getByLabelText('件名')).toHaveFocus();
    expect(screen.getByLabelText('種別')).toHaveValue('question');
    expect(screen.getByRole('radio', { name: '中' })).toBeChecked();
  });

  it('前後の空白を除いた 5 項目を送り、成功したら空にして開いたままにする', async () => {
    const { user, onSubmit } = await openForm();

    await user.type(screen.getByLabelText('件名'), '　ログインできない ');
    await user.type(screen.getByLabelText('問い合わせ者'), '山田 太郎');
    await user.type(screen.getByLabelText('問い合わせ内容'), '再設定しても戻される');
    await user.selectOptions(screen.getByLabelText('種別'), 'bug');
    await user.click(screen.getByRole('radio', { name: '高' }));
    await user.click(screen.getByRole('button', { name: '登録' }));

    expect(onSubmit).toHaveBeenCalledWith({
      title: 'ログインできない',
      customerName: '山田 太郎',
      content: '再設定しても戻される',
      category: 'bug',
      priority: 'high',
    });
    expect(screen.getByLabelText('件名')).toHaveValue('');
    expect(screen.getByLabelText('種別')).toHaveValue('question');
    expect(screen.getByLabelText('件名')).toHaveFocus();
  });

  it('必須の項目が空（空白だけを含む）なら送らず、赤枠と項目名の文言を出し、最初の空の欄へ移る', async () => {
    const { user, onSubmit } = await openForm();

    await user.type(screen.getByLabelText('問い合わせ者'), '　');
    await user.type(screen.getByLabelText('問い合わせ内容'), '内容');
    await user.click(screen.getByRole('button', { name: '登録' }));

    expect(onSubmit).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toHaveTextContent('件名・問い合わせ者を入力してください');
    expect(screen.getByLabelText('件名')).toHaveAttribute('aria-invalid', 'true');
    expect(screen.getByLabelText('問い合わせ内容')).toHaveAttribute('aria-invalid', 'false');
    expect(screen.getByLabelText('件名')).toHaveFocus();

    // 入力し直した欄は赤枠が消える
    await user.type(screen.getByLabelText('件名'), '件名');
    expect(screen.getByLabelText('件名')).toHaveAttribute('aria-invalid', 'false');
    expect(screen.getByRole('alert')).toHaveTextContent('問い合わせ者を入力してください');
  });

  it('件名の欄で Enter を押しても登録する。問い合わせ内容の Enter は改行', async () => {
    const { user, onSubmit } = await openForm();

    await user.type(screen.getByLabelText('問い合わせ者'), '顧客');
    await user.type(screen.getByLabelText('問い合わせ内容'), '1 行目{Enter}2 行目');
    expect(onSubmit).not.toHaveBeenCalled();
    await user.type(screen.getByLabelText('件名'), '件名{Enter}');

    expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({ content: '1 行目\n2 行目' }));
  });

  it('送信に失敗したら文言を出し、入力内容は残す', async () => {
    const { user } = await openForm(
      vi.fn(() => Promise.reject(new ApiError(null, 'サーバーに接続できません'))),
    );

    await user.type(screen.getByLabelText('件名'), '件名');
    await user.type(screen.getByLabelText('問い合わせ者'), '顧客');
    await user.type(screen.getByLabelText('問い合わせ内容'), '内容');
    await user.click(screen.getByRole('button', { name: '登録' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('サーバーに接続できません。');
    expect(screen.getByLabelText('件名')).toHaveValue('件名');
  });

  it('キャンセルまたは Escape で閉じ、入力内容を捨てる', async () => {
    const { user } = await openForm();

    await user.type(screen.getByLabelText('件名'), '件名');
    await user.click(screen.getByRole('button', { name: 'キャンセル' }));
    expect(screen.queryByLabelText('件名')).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: '＋ 問い合わせを登録' }));
    expect(screen.getByLabelText('件名')).toHaveValue('');
    await user.keyboard('{Escape}');
    expect(screen.getByRole('button', { name: '＋ 問い合わせを登録' })).toBeInTheDocument();
  });
});
