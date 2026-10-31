import { Draggable } from '@hello-pangea/dnd';
import type { KeyboardEvent } from 'react';
import type { Inquiry } from '@/types/inquiry';
import { formatMonthDay, isOverdue } from '@/utils/date';
import { CategoryTag } from '../CategoryTag/CategoryTag';
import { PriorityBadge } from '../PriorityBadge/PriorityBadge';
import styles from './InquiryCard.module.css';

type Props = {
  inquiry: Inquiry;
  /** 列内での順番（0 始まり）。Draggable に渡す */
  index: number;
  /** クリック（または Enter）したとき。問い合わせ詳細を開く */
  onClick: () => void;
};

/**
 * 問い合わせ 1 件のカード（SC-01、フロントエンド設計書 8.2）。
 * 1 行目に優先度と件名、2 行目に問い合わせ者と対応者、3 行目に種別と対応期限を表示する。
 * つかんで動かせ（FR-04・FR-05）、クリックで問い合わせ詳細（SC-02）を開く。
 * クリックとドラッグの区別はライブラリが行う。ライブラリのキーボード操作は Space で持ち上げるため、Enter で開く。
 */
export function InquiryCard({ inquiry, index, onClick }: Props) {
  const overdue = isOverdue(inquiry);

  function handleKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    if (e.key === 'Enter') {
      e.preventDefault();
      onClick();
    }
  }

  return (
    <Draggable draggableId={String(inquiry.id)} index={index}>
      {(provided, snapshot) => (
        <div
          ref={provided.innerRef}
          {...provided.draggableProps}
          {...provided.dragHandleProps}
          className={snapshot.isDragging ? `${styles.card} ${styles.dragging}` : styles.card}
          onClick={onClick}
          onKeyDown={handleKeyDown}
        >
          <div className={styles.titleRow}>
            <PriorityBadge priority={inquiry.priority} />
            <span className={styles.title}>{inquiry.title}</span>
          </div>
          <div className={styles.people}>
            <span className={styles.customer}>{inquiry.customerName} 様</span>
            {inquiry.assignee === null ? (
              <span className={`${styles.assignee} ${styles.unassigned}`}>対応者 未割当</span>
            ) : (
              <span className={styles.assignee}>対応者 {inquiry.assignee}</span>
            )}
          </div>
          <div className={styles.meta}>
            <CategoryTag category={inquiry.category} />
            {/* 期限が無くても行を出し、カードの高さを揃える */}
            <span className={overdue ? `${styles.due} ${styles.overdue}` : styles.due}>
              {inquiry.dueOn !== null &&
                `期限 ${formatMonthDay(inquiry.dueOn)}${overdue ? '（期限切れ）' : ''}`}
            </span>
          </div>
        </div>
      )}
    </Draggable>
  );
}
