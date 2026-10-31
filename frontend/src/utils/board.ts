import type { DropResult } from '@hello-pangea/dnd';
import type { Inquiry, InquiryMoveInput, ListId } from '@/types/inquiry';

/**
 * ドロップの結果を一覧に反映した新しい配列を返す（フロントエンド設計書 5.6、方針 9）。
 * その問い合わせを取り除き、listId を書き換えて、移動先のリストの toIndex 番目に差し込む。
 * displayOrder は書き換えない（画面は配列の順番で描画しており、正しい値は取り直したときに入る）。
 * 優先度順の並べ替えは行わない（FR-04、FR-05）。
 */
export function applyMove(
  inquiries: Inquiry[],
  id: number,
  toListId: ListId,
  toIndex: number,
): Inquiry[] {
  const inquiry = inquiries.find((q) => q.id === id);
  if (inquiry === undefined) return inquiries;

  const rest = inquiries.filter((q) => q.id !== id);
  const target = rest.filter((q) => q.listId === toListId);
  const others = rest.filter((q) => q.listId !== toListId);

  const index = Math.min(Math.max(toIndex, 0), target.length);
  target.splice(index, 0, { ...inquiry, listId: toListId });

  return [...others, ...target];
}

/** dragEndToMove の戻り値。どの問い合わせをどこへ動かすか */
export type MoveRequest = Required<InquiryMoveInput> & { id: number };

/**
 * @hello-pangea/dnd の onDragEnd が受け取る結果を、移動 API の要求に変換する（フロントエンド設計書 8.7）。
 * ドロップ先が無い（列の外で離した）か、元と同じ位置なら null（何もしない）。
 * destination.index は「自分を除いた並びでの位置」で、API 設計書 10. の displayOrder と同じ定義なのでそのまま使う。
 */
export function dragEndToMove(result: DropResult): MoveRequest | null {
  const { source, destination, draggableId } = result;
  if (!destination) return null;
  if (destination.droppableId === source.droppableId && destination.index === source.index) {
    return null;
  }
  return {
    id: Number(draggableId),
    listId: destination.droppableId as ListId,
    displayOrder: destination.index,
  };
}
