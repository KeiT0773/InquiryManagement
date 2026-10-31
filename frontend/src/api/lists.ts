import type { BoardList } from '@/types/inquiry';
import { apiGet } from './client';

// GET /api/lists（API 設計書 5.）
export function getLists(): Promise<BoardList[]> {
  return apiGet<BoardList[]>('/api/lists');
}
