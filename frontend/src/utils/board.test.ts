import type { DropResult } from '@hello-pangea/dnd';
import { describe, expect, it } from 'vitest';
import { makeInquiry } from '@/test/fixtures';
import type { Inquiry, ListId } from '@/types/inquiry';
import { applyMove, dragEndToMove } from './board';

const initial = [
  makeInquiry(1, 'open', 0),
  makeInquiry(2, 'open', 1),
  makeInquiry(3, 'open', 2),
  makeInquiry(4, 'working', 0),
];

const idsIn = (inquiries: Inquiry[], listId: ListId) =>
  inquiries.filter((q) => q.listId === listId).map((q) => q.id);

describe('applyMove', () => {
  it('別のリストの指定した位置に差し込み、listId を書き換える', () => {
    const moved = applyMove(initial, 2, 'working', 0);

    expect(idsIn(moved, 'open')).toEqual([1, 3]);
    expect(idsIn(moved, 'working')).toEqual([2, 4]);
    expect(moved.find((q) => q.id === 2)?.listId).toBe('working');
  });

  it('同じリスト内では、自分を除いた並びの何番目かに入る', () => {
    expect(idsIn(applyMove(initial, 1, 'open', 2), 'open')).toEqual([2, 3, 1]);
    expect(idsIn(applyMove(initial, 3, 'open', 0), 'open')).toEqual([3, 1, 2]);
  });

  it('位置が件数を超えたら末尾に置く。元の配列は変えない', () => {
    const moved = applyMove(initial, 1, 'closed', 10);

    expect(idsIn(moved, 'closed')).toEqual([1]);
    expect(idsIn(initial, 'open')).toEqual([1, 2, 3]);
  });

  it('無い問い合わせなら何もしない', () => {
    expect(applyMove(initial, 99, 'open', 0)).toBe(initial);
  });
});

describe('dragEndToMove', () => {
  function result(
    source: { droppableId: string; index: number },
    destination: { droppableId: string; index: number } | null,
  ): DropResult {
    return {
      draggableId: '2',
      type: 'DEFAULT',
      source,
      destination,
      reason: 'DROP',
      mode: 'FLUID',
      combine: null,
    };
  }

  it('ドロップ先を移動 API の要求にする', () => {
    expect(
      dragEndToMove(
        result({ droppableId: 'open', index: 1 }, { droppableId: 'working', index: 0 }),
      ),
    ).toEqual({ id: 2, listId: 'working', displayOrder: 0 });
  });

  it('列の外で離した、または元と同じ位置なら null', () => {
    expect(dragEndToMove(result({ droppableId: 'open', index: 1 }, null))).toBeNull();
    expect(
      dragEndToMove(result({ droppableId: 'open', index: 1 }, { droppableId: 'open', index: 1 })),
    ).toBeNull();
  });
});
