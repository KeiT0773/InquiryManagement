import {
  useEffect,
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
  type MouseEvent,
} from 'react';
import { ApiError } from '@/api/client';
import { CATEGORIES, CATEGORY_LABEL, PRIORITIES } from '@/constants/labels';
import type {
  BoardList,
  Category,
  Inquiry,
  InquiryUpdateInput,
  ListId,
  Priority,
} from '@/types/inquiry';
import { formatFullDate } from '@/utils/date';
import { errorMessage } from '@/utils/errorMessage';
import { PriorityBadge } from '../PriorityBadge/PriorityBadge';
import styles from './InquiryDetail.module.css';

type Props = {
  inquiry: Inquiry;
  lists: BoardList[];
  /** 項目が確定したときの保存先。確定した 1 項目だけを渡す。失敗したときは ApiError を投げること */
  onSave: (input: InquiryUpdateInput) => Promise<void>;
  /** ステータスを選び直したとき（移動先の末尾へ）。失敗したときは ApiError を投げること */
  onMove: (listId: ListId) => Promise<void>;
  /** 確認ダイアログで OK を押したとき。失敗したときは ApiError を投げること */
  onDelete: () => Promise<void>;
  onClose: () => void;
};

/** 入力欄の値（下書き）。入力欄は文字列しか持てないので、null は '' で表す */
type Draft = {
  title: string;
  customerName: string;
  contact: string;
  category: Category;
  content: string;
  memo: string;
  assignee: string;
  dueOn: string;
  priority: Priority;
  listId: ListId;
};

/** 保存で送る項目（ステータスは保存ではなく移動なので含めない） */
type SaveField = Exclude<keyof Draft, 'listId'>;
/** 失敗の文言を出す場所 */
type ErrorPlace = keyof Draft | 'delete';

/** 空にできない項目（FR-02） */
const REQUIRED: readonly SaveField[] = ['title', 'customerName', 'content'];
/** 空なら null を送る項目 */
const NULLABLE: readonly SaveField[] = ['contact', 'memo', 'assignee', 'dueOn'];

function draftOf(inquiry: Inquiry): Draft {
  return {
    title: inquiry.title,
    customerName: inquiry.customerName,
    contact: inquiry.contact ?? '',
    category: inquiry.category,
    content: inquiry.content,
    memo: inquiry.memo ?? '',
    assignee: inquiry.assignee ?? '',
    dueOn: inquiry.dueOn ?? '',
    priority: inquiry.priority,
    listId: inquiry.listId,
  };
}

/**
 * 問い合わせ詳細（SC-02、フロントエンド設計書 8.6）。ボードの手前に重ねるモーダル。
 * 「保存」ボタンは無く、項目ごとに確定したときに **その項目だけ** を onSave に渡す。
 * ステータスの選択は onMove、フッターの「問い合わせを削除」は確認ダイアログを経て onDelete を呼ぶ。
 * Board は key={inquiry.id} で描画し、別の問い合わせを開いたときは作り直される。
 */
export function InquiryDetail({ inquiry, lists, onSave, onMove, onDelete, onClose }: Props) {
  const [draft, setDraft] = useState<Draft>(() => draftOf(inquiry));
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<{ place: ErrorPlace; error: ApiError } | null>(null);
  const titleRef = useRef<HTMLInputElement>(null);
  // 保存を直列にする。前の保存が終わる前に次の項目が確定しても、順番に送られるようにする
  const queueRef = useRef<Promise<void>>(Promise.resolve());

  // 開いたときに件名へフォーカスを当てる
  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  // Escape で閉じる（フォーカスがどこにあっても効くよう window で受ける）
  useEffect(() => {
    function onKeyDown(e: globalThis.KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  /** 保存・移動を順番に実行し、失敗したら place の下に文言を出す */
  function enqueue(place: ErrorPlace, run: () => Promise<void>, onFailure?: () => void) {
    queueRef.current = queueRef.current.then(async () => {
      setSaving(true);
      try {
        await run();
        setError((current) => (current?.place === place ? null : current));
      } catch (err: unknown) {
        setError({ place, error: err instanceof ApiError ? err : new ApiError(null, String(err)) });
        onFailure?.();
      } finally {
        setSaving(false);
      }
    });
  }

  /**
   * 項目が確定したときの保存（8.6「保存の手順」）。value を渡すと下書きの代わりにその値を使う
   * （select・ラジオ・日付は、変更と同時に確定するため）。
   */
  function save(field: SaveField, value: string = draft[field]) {
    const trimmed = value.trim();

    // 1. 必須項目が空なら保存せず、下書きを元の値に戻す（文言は出さない）
    if (REQUIRED.includes(field) && trimmed === '') {
      setDraft((d) => ({ ...d, [field]: draftOf(inquiry)[field] }));
      return;
    }

    // 2. 現在の値と同じなら送らない（フォーカスが外れただけのとき）
    const sent = NULLABLE.includes(field) && trimmed === '' ? null : trimmed;
    if (sent === inquiry[field]) {
      setDraft((d) => ({ ...d, [field]: sent ?? '' }));
      return;
    }

    // 3.〜6. その項目だけを送る。成功したら下書きを送った値にそろえ、他の項目の下書きは触らない
    enqueue(field, async () => {
      await onSave({ [field]: sent } as InquiryUpdateInput);
      setDraft((d) => ({ ...d, [field]: sent ?? '' }));
    });
  }

  /** ステータスの選び直し（5.6）。失敗したら選択を元の値に戻す */
  function move(listId: ListId) {
    setDraft((d) => ({ ...d, listId }));
    if (listId === inquiry.listId) return;
    const original = inquiry.listId;
    enqueue(
      'listId',
      () => onMove(listId),
      () => setDraft((d) => ({ ...d, listId: original })),
    );
  }

  /**
   * 削除（FR-03）。確認ダイアログで OK のときだけ送る。保存の直列化とは独立に送る
   * （成功すれば問い合わせごと無くなり Board が閉じるため）。失敗したらフッターに文言を出し、開いたまま
   */
  async function handleDelete() {
    const confirmed = window.confirm(
      `問い合わせ「${inquiry.title}」を削除しますか？\nこの操作は取り消せません。`,
    );
    if (!confirmed) return;

    setDeleting(true);
    try {
      await onDelete();
    } catch (err: unknown) {
      setError({
        place: 'delete',
        error: err instanceof ApiError ? err : new ApiError(null, String(err)),
      });
    } finally {
      setDeleting(false);
    }
  }

  /** 1 行の入力欄は Enter でも確定する（blur で保存される） */
  function blurOnEnter(e: ReactKeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter') {
      e.preventDefault();
      e.currentTarget.blur();
    }
  }

  function handleOverlayClick(e: MouseEvent<HTMLDivElement>) {
    // モーダルの外側（背景）を押したときだけ閉じる
    if (e.target === e.currentTarget) onClose();
  }

  function fieldError(place: ErrorPlace, prefix = '') {
    if (error === null || error.place !== place) return null;
    return (
      <p className={styles.error} role="alert">
        {prefix}
        {errorMessage(error.error)}
      </p>
    );
  }

  /** 1 行の文字入力欄（件名・問い合わせ者・連絡先・対応者） */
  function textField(
    field: 'title' | 'customerName' | 'contact' | 'assignee',
    label: string,
    maxLength: number,
    { placeholder, grow = false }: { placeholder?: string; grow?: boolean } = {},
  ) {
    const id = `detail-${field}`;
    return (
      <div className={grow ? `${styles.field} ${styles.grow}` : styles.field}>
        <label htmlFor={id} className={styles.fieldLabel}>
          {label}
        </label>
        <input
          id={id}
          ref={field === 'title' ? titleRef : undefined}
          type="text"
          className={styles.input}
          maxLength={maxLength}
          placeholder={placeholder}
          value={draft[field]}
          onChange={(e) => setDraft((d) => ({ ...d, [field]: e.target.value }))}
          onBlur={() => save(field)}
          onKeyDown={blurOnEnter}
        />
        {fieldError(field)}
      </div>
    );
  }

  /** 複数行の入力欄（問い合わせ内容・対応メモ）。Enter は改行で、blur で確定する */
  function textareaField(
    field: 'content' | 'memo',
    label: string,
    rows: number,
    placeholder: string,
  ) {
    const id = `detail-${field}`;
    return (
      <div className={styles.field}>
        <label htmlFor={id} className={styles.fieldLabel}>
          {label}
        </label>
        <textarea
          id={id}
          className={styles.textarea}
          rows={rows}
          maxLength={2000}
          placeholder={placeholder}
          value={draft[field]}
          onChange={(e) => setDraft((d) => ({ ...d, [field]: e.target.value }))}
          onBlur={() => save(field)}
        />
        {fieldError(field)}
      </div>
    );
  }

  return (
    <div className={styles.overlay} onClick={handleOverlayClick} data-testid="detail-overlay">
      <div
        className={styles.modal}
        role="dialog"
        aria-modal="true"
        aria-labelledby="detail-heading"
      >
        <div className={styles.header}>
          <h2 id="detail-heading" className={styles.heading}>
            問い合わせ詳細
            {saving && <span className={styles.saving}>保存中…</span>}
          </h2>
          <button type="button" className={styles.close} onClick={onClose}>
            閉じる
          </button>
        </div>

        {/* 文言（role=alert）をラベルの中に入れると入力欄の名前に混ざるため、label と入力欄は id で結ぶ */}
        <div className={styles.body}>
          {textField('title', '件名', 100)}

          <div className={styles.row}>
            {textField('customerName', '問い合わせ者', 50, {
              placeholder: '例：山田 太郎（必須）',
              grow: true,
            })}
            {textField('contact', '連絡先', 100, {
              placeholder: 'メールアドレスまたは電話番号',
              grow: true,
            })}
          </div>

          <div className={styles.row}>
            <div className={styles.field}>
              <label htmlFor="detail-category" className={styles.fieldLabel}>
                種別
              </label>
              <select
                id="detail-category"
                className={styles.input}
                value={draft.category}
                onChange={(e) => {
                  const category = e.target.value as Category;
                  setDraft((d) => ({ ...d, category }));
                  save('category', category);
                }}
              >
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {CATEGORY_LABEL[c]}
                  </option>
                ))}
              </select>
              {fieldError('category')}
            </div>

            <div className={styles.field}>
              <label htmlFor="detail-listId" className={styles.fieldLabel}>
                ステータス
              </label>
              <select
                id="detail-listId"
                className={styles.input}
                value={draft.listId}
                onChange={(e) => move(e.target.value as ListId)}
              >
                {lists.map((list) => (
                  <option key={list.id} value={list.id}>
                    {list.name}
                  </option>
                ))}
              </select>
              {fieldError('listId')}
            </div>

            <div className={styles.field}>
              <label htmlFor="detail-dueOn" className={styles.fieldLabel}>
                対応期限
              </label>
              <input
                id="detail-dueOn"
                type="date"
                className={styles.input}
                value={draft.dueOn}
                onChange={(e) => {
                  const dueOn = e.target.value;
                  setDraft((d) => ({ ...d, dueOn }));
                  save('dueOn', dueOn);
                }}
              />
              {fieldError('dueOn')}
            </div>
          </div>

          {textareaField('content', '問い合わせ内容', 4, '問い合わせの内容を入力（必須）')}
          {textareaField('memo', '対応メモ', 3, '回答内容や対応経過を入力（任意）')}

          <div className={styles.row}>
            {textField('assignee', '対応者', 50, { placeholder: '未割当', grow: true })}

            <fieldset className={`${styles.field} ${styles.grow}`}>
              <legend className={styles.fieldLabel}>優先度</legend>
              <div className={styles.priorityOptions}>
                {PRIORITIES.map((p) => (
                  <label key={p} className={styles.priorityOption}>
                    <input
                      type="radio"
                      name="detail-priority"
                      value={p}
                      checked={draft.priority === p}
                      onChange={() => {
                        setDraft((d) => ({ ...d, priority: p }));
                        save('priority', p);
                      }}
                    />
                    <PriorityBadge priority={p} />
                  </label>
                ))}
              </div>
              {fieldError('priority')}
            </fieldset>
          </div>

          <p className={styles.received}>受付日 {formatFullDate(inquiry.receivedOn)}</p>
        </div>

        {/* 削除は誤操作を防ぐため、右上の「閉じる」から離れた最下部に置く（画面要件書 5.2） */}
        <div className={styles.footer}>
          {fieldError('delete', '削除できませんでした。')}
          <button
            type="button"
            className={styles.delete}
            disabled={deleting}
            onClick={() => void handleDelete()}
          >
            {deleting ? '削除中…' : '問い合わせを削除'}
          </button>
        </div>
      </div>
    </div>
  );
}
