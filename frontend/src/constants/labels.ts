// 種別・優先度の表示名と、選択肢の並び順（フロントエンド設計書 8.1）。色は各部品の .module.css に持つ
import type { Category, Priority } from '@/types/inquiry';

export const PRIORITIES: readonly Priority[] = ['high', 'medium', 'low'];

export const PRIORITY_LABEL: Record<Priority, string> = {
  high: '高',
  medium: '中',
  low: '低',
};

export const CATEGORIES: readonly Category[] = ['question', 'bug', 'request', 'other'];

export const CATEGORY_LABEL: Record<Category, string> = {
  question: '質問',
  bug: '不具合',
  request: '要望',
  other: 'その他',
};
