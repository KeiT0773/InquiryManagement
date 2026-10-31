import { Droppable } from '@hello-pangea/dnd';
import type { BoardList as BoardListData, Inquiry, InquiryCreateInput } from '@/types/inquiry';
import { AddInquiryForm } from '../AddInquiryForm/AddInquiryForm';
import { InquiryCard } from '../InquiryCard/InquiryCard';
import styles from './BoardList.module.css';

type Props = {
  list: BoardListData;
  /** このリストに属する問い合わせ。API から返った順（displayOrder 昇順）のまま渡す */
  inquiries: Inquiry[];
  /** 「＋ 問い合わせを登録」からの登録。「未対応」にだけ渡す */
  onAdd?: (input: InquiryCreateInput) => Promise<void>;
  /** カードをクリックしたとき。問い合わせ詳細を開く */
  onCardClick: (id: number) => void;
};

/**
 * 1 つのリスト（列）。見出しと件数、問い合わせの一覧を縦に並べる（SC-01）。
 * 一覧の領域はドロップ先（Droppable、droppableId = list.id）で、多いときは列の中だけがスクロールする。
 * 登録フォームは「未対応」だけに、スクロールする領域の外の最下部に置く（常に見えるように。8.5）。
 */
export function BoardList({ list, inquiries, onAdd, onCardClick }: Props) {
  return (
    <section className={`${styles.list} ${styles[list.id]}`} aria-label={list.name}>
      <h2 className={styles.header}>
        <span>{list.name}</span>
        <span className={styles.count}>{inquiries.length}件</span>
      </h2>
      <Droppable droppableId={list.id}>
        {(provided) => (
          <div ref={provided.innerRef} {...provided.droppableProps} className={styles.cards}>
            {inquiries.map((inquiry, index) => (
              <InquiryCard
                key={inquiry.id}
                inquiry={inquiry}
                index={index}
                onClick={() => onCardClick(inquiry.id)}
              />
            ))}
            {/* ドラッグ中に隙間を作るための要素。Droppable の子の末尾に必ず置く */}
            {provided.placeholder}
          </div>
        )}
      </Droppable>
      {onAdd !== undefined && <AddInquiryForm onSubmit={onAdd} />}
    </section>
  );
}
