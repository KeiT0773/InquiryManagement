// 日付の書式変換と期限超過の判定（フロントエンド設計書 8.2〜8.4）。
// 日付は API から受け取った 'YYYY-MM-DD' の文字列のまま扱い、Date 型には変換しない。
import type { Inquiry } from '@/types/inquiry';

/** 端末のローカル日付を 'YYYY-MM-DD' で返す。想定端末は日本国内にあるため日本時間と一致する */
export function todayString(now: Date = new Date()): string {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** 'YYYY-MM-DD' をカードに出す 'MM/DD' にする */
export function formatMonthDay(date: string): string {
  const [, m, d] = date.split('-');
  return `${m}/${d}`;
}

/** 'YYYY-MM-DD' を問い合わせ詳細の受付日に出す 'YYYY/MM/DD' にする */
export function formatFullDate(date: string): string {
  return date.replaceAll('-', '/');
}

/**
 * 期限超過かどうか（データ設計書 5.4）。期限があり、今日より前で、かつ「完了」以外にあるものを超過とする。
 * 期限当日は超過とみなさない。'YYYY-MM-DD' は文字列の大小と日付の前後が一致するため、文字列のまま比べる。
 */
export function isOverdue(
  inquiry: Pick<Inquiry, 'dueOn' | 'listId'>,
  today: string = todayString(),
): boolean {
  return inquiry.dueOn !== null && inquiry.dueOn < today && inquiry.listId !== 'closed';
}
