import type { ApiError } from '@/api/client';

/**
 * エラーの種類に応じた表示文言（フロントエンド設計書 6.3）。
 * すべての失敗の表示から使い、同じ種類のエラーは画面のどこで起きても同じ文言にする。
 */
export function errorMessage(error: ApiError): string {
  if (error.status === null) {
    return 'サーバーに接続できません。バックエンドが起動しているか確認してください。';
  }
  if (error.status === 404) {
    return 'この問い合わせは、ほかのメンバーによって削除されています。';
  }
  if (error.status === 500) {
    return 'サーバーでエラーが発生しました。';
  }
  // 422 などは API が返した日本語の detail をそのまま出す（例：件名を入力してください）
  return error.message;
}
