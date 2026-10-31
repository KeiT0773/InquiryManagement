import { CATEGORY_LABEL } from '@/constants/labels';
import type { Category } from '@/types/inquiry';
import styles from './CategoryTag.module.css';

/** 種別を表示名と色で表示する（画面要件書 3.、フロントエンド設計書 8.1） */
export function CategoryTag({ category }: { category: Category }) {
  return <span className={`${styles.tag} ${styles[category]}`}>{CATEGORY_LABEL[category]}</span>;
}
