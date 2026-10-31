import { describe, expect, it } from 'vitest';
import { ApiError } from '@/api/client';
import { errorMessage } from './errorMessage';

describe('errorMessage', () => {
  it('エラーの種類ごとに決まった文言にする（フロントエンド設計書 6.3）', () => {
    expect(errorMessage(new ApiError(null, 'x'))).toBe(
      'サーバーに接続できません。バックエンドが起動しているか確認してください。',
    );
    expect(errorMessage(new ApiError(404, 'x'))).toBe(
      'この問い合わせは、ほかのメンバーによって削除されています。',
    );
    expect(errorMessage(new ApiError(500, 'x'))).toBe('サーバーでエラーが発生しました。');
  });

  it('それ以外は API が返した detail をそのまま出す', () => {
    expect(errorMessage(new ApiError(422, '件名を入力してください'))).toBe(
      '件名を入力してください',
    );
  });
});
