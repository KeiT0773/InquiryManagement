import { describe, expect, it } from 'vitest';
import { formatFullDate, formatMonthDay, isOverdue, todayString } from './date';

describe('utils/date', () => {
  it('todayString は端末のローカル日付を YYYY-MM-DD で返す', () => {
    expect(todayString(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05');
  });

  it('カードは MM/DD、詳細の受付日は YYYY/MM/DD で表示する', () => {
    expect(formatMonthDay('2026-11-01')).toBe('11/01');
    expect(formatFullDate('2026-11-01')).toBe('2026/11/01');
  });

  it('期限が今日より前で、完了以外にあるものだけを期限超過とする', () => {
    const today = '2026-11-01';
    expect(isOverdue({ dueOn: '2026-10-31', listId: 'open' }, today)).toBe(true);
    expect(isOverdue({ dueOn: '2026-10-31', listId: 'working' }, today)).toBe(true);
    // 期限当日は超過とみなさない
    expect(isOverdue({ dueOn: '2026-11-01', listId: 'open' }, today)).toBe(false);
    // 完了は強調しない
    expect(isOverdue({ dueOn: '2026-10-31', listId: 'closed' }, today)).toBe(false);
    expect(isOverdue({ dueOn: null, listId: 'open' }, today)).toBe(false);
  });
});
