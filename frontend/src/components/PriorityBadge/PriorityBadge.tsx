import { PRIORITY_LABEL } from '@/constants/labels';
import type { Priority } from '@/types/inquiry';
import styles from './PriorityBadge.module.css';

/** 優先度を表示名（高 / 中 / 低）と色で表示する（FR-08、フロントエンド設計書 8.1） */
export function PriorityBadge({ priority }: { priority: Priority }) {
  return <span className={`${styles.badge} ${styles[priority]}`}>{PRIORITY_LABEL[priority]}</span>;
}
