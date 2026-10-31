import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from 'react';
import { ApiError } from '@/api/client';
import { CATEGORIES, CATEGORY_LABEL, PRIORITIES } from '@/constants/labels';
import type { Category, InquiryCreateInput, Priority } from '@/types/inquiry';
import { errorMessage } from '@/utils/errorMessage';
import { PriorityBadge } from '../PriorityBadge/PriorityBadge';
import styles from './AddInquiryForm.module.css';

type Props = {
  /** 送信先。useBoard の addInquiry を渡す。失敗したときは ApiError を投げること */
  onSubmit: (input: InquiryCreateInput) => Promise<void>;
};

/** 必須の 3 項目（FR-01） */
type RequiredField = 'title' | 'customerName' | 'content';

const REQUIRED_LABEL: Record<RequiredField, string> = {
  title: '件名',
  customerName: '問い合わせ者',
  content: '問い合わせ内容',
};

const REQUIRED_FIELDS: readonly RequiredField[] = ['title', 'customerName', 'content'];

const EMPTY_VALUES: Record<RequiredField, string> = { title: '', customerName: '', content: '' };

/**
 * 「未対応」列の最下部の「＋ 問い合わせを登録」ボタンと、押したときに現れる入力フォーム
 * （FR-01、画面要件書 5.1、フロントエンド設計書 8.5）。
 * 入力内容・開閉・送信中・失敗の状態を自分で持ち、送信そのものは onSubmit に委ねる。
 */
export function AddInquiryForm({ onSubmit }: Props) {
  const [open, setOpen] = useState(false);
  const [values, setValues] = useState<Record<RequiredField, string>>(EMPTY_VALUES);
  const [category, setCategory] = useState<Category>('question');
  const [priority, setPriority] = useState<Priority>('medium');
  const [missing, setMissing] = useState<RequiredField[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const titleRef = useRef<HTMLInputElement>(null);
  const customerNameRef = useRef<HTMLInputElement>(null);
  const contentRef = useRef<HTMLTextAreaElement>(null);
  const refs = { title: titleRef, customerName: customerNameRef, content: contentRef };

  // 開いたときに件名へフォーカスを当てる
  useEffect(() => {
    if (open) titleRef.current?.focus();
  }, [open]);

  function reset() {
    setValues(EMPTY_VALUES);
    setCategory('question');
    setPriority('medium');
    setMissing([]);
    setError(null);
  }

  function close() {
    setOpen(false);
    reset();
  }

  function change(field: RequiredField, value: string) {
    setValues((v) => ({ ...v, [field]: value }));
    // 入力し直した欄は赤枠を消す
    setMissing((m) => m.filter((f) => f !== field));
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (submitting) return;

    // 前後の空白（全角の空白を含む）を除く。JavaScript の trim は全角の空白も除く
    const trimmed = {
      title: values.title.trim(),
      customerName: values.customerName.trim(),
      content: values.content.trim(),
    };
    const empty = REQUIRED_FIELDS.filter((f) => trimmed[f] === '');
    if (empty.length > 0) {
      // 空の項目があれば送らず、赤枠と文言で示し、最初の空の欄にフォーカスを移す
      setMissing(empty);
      refs[empty[0]].current?.focus();
      return;
    }

    setSubmitting(true);
    try {
      await onSubmit({ ...trimmed, category, priority });
      // 続けて登録できるよう、開いたまま初期値に戻す
      reset();
      titleRef.current?.focus();
    } catch (err: unknown) {
      // 入力内容は残し、文言だけを出す（フロントエンド設計書 2. 方針 7）
      setError(err instanceof ApiError ? err : new ApiError(null, String(err)));
    } finally {
      setSubmitting(false);
    }
  }

  function handleKeyDown(e: KeyboardEvent<HTMLFormElement>) {
    if (e.key === 'Escape') close();
  }

  if (!open) {
    return (
      <div className={styles.addArea}>
        <button type="button" className={styles.addButton} onClick={() => setOpen(true)}>
          ＋ 問い合わせを登録
        </button>
      </div>
    );
  }

  function inputClass(field: RequiredField, base: string) {
    return missing.includes(field) ? `${base} ${styles.inputError}` : base;
  }

  return (
    <div className={styles.addArea}>
      <form className={styles.form} onSubmit={handleSubmit} onKeyDown={handleKeyDown} noValidate>
        <input
          ref={titleRef}
          type="text"
          className={inputClass('title', styles.input)}
          placeholder="件名を入力（必須）"
          aria-label="件名"
          aria-invalid={missing.includes('title')}
          maxLength={100}
          value={values.title}
          onChange={(e) => change('title', e.target.value)}
        />
        <input
          ref={customerNameRef}
          type="text"
          className={inputClass('customerName', `${styles.input} ${styles.sub}`)}
          placeholder="問い合わせ者（必須）"
          aria-label="問い合わせ者"
          aria-invalid={missing.includes('customerName')}
          maxLength={50}
          value={values.customerName}
          onChange={(e) => change('customerName', e.target.value)}
        />
        <textarea
          ref={contentRef}
          className={inputClass('content', styles.textarea)}
          rows={3}
          placeholder="問い合わせ内容（必須）"
          aria-label="問い合わせ内容"
          aria-invalid={missing.includes('content')}
          maxLength={2000}
          value={values.content}
          onChange={(e) => change('content', e.target.value)}
        />
        <select
          className={`${styles.input} ${styles.sub}`}
          aria-label="種別"
          value={category}
          onChange={(e) => setCategory(e.target.value as Category)}
        >
          {CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABEL[c]}
            </option>
          ))}
        </select>
        <div className={styles.priorityOptions} role="radiogroup" aria-label="優先度">
          {PRIORITIES.map((p) => (
            <label key={p} className={styles.priorityOption}>
              <input
                type="radio"
                name="add-priority"
                value={p}
                checked={priority === p}
                onChange={() => setPriority(p)}
              />
              <PriorityBadge priority={p} />
            </label>
          ))}
        </div>
        {missing.length > 0 && (
          <p className={styles.error} role="alert">
            {missing.map((f) => REQUIRED_LABEL[f]).join('・')}を入力してください
          </p>
        )}
        {error !== null && (
          <p className={styles.error} role="alert">
            {errorMessage(error)}
          </p>
        )}
        <div className={styles.buttons}>
          <button type="submit" className={styles.primary} disabled={submitting}>
            登録
          </button>
          <button type="button" className={styles.secondary} onClick={close} disabled={submitting}>
            キャンセル
          </button>
        </div>
      </form>
    </div>
  );
}
