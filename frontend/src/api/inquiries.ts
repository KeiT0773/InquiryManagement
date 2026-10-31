// 問い合わせの API（API 設計書 6.〜12.、フロントエンド設計書 6.1）
import type {
  Inquiry,
  InquiryCreateInput,
  InquiryMoveInput,
  InquiryUpdateInput,
  ListId,
} from '@/types/inquiry';
import { apiDelete, apiGet, apiPatch, apiPost, apiPut } from './client';

// GET /api/inquiries[?listId=]。listId・displayOrder の順に返る
export function getInquiries(listId?: ListId): Promise<Inquiry[]> {
  const query = listId === undefined ? '' : `?listId=${encodeURIComponent(listId)}`;
  return apiGet<Inquiry[]>(`/api/inquiries${query}`);
}

// GET /api/inquiries/{id}
export function getInquiry(id: number): Promise<Inquiry> {
  return apiGet<Inquiry>(`/api/inquiries/${id}`);
}

// POST /api/inquiries。必ず「未対応」に登録される
export function createInquiry(input: InquiryCreateInput): Promise<Inquiry> {
  return apiPost<InquiryCreateInput, Inquiry>('/api/inquiries', input);
}

// PATCH /api/inquiries/{id}。変える項目だけを送る
export function updateInquiry(id: number, input: InquiryUpdateInput): Promise<Inquiry> {
  return apiPatch<InquiryUpdateInput, Inquiry>(`/api/inquiries/${id}`, input);
}

// PUT /api/inquiries/{id}/position。displayOrder を省くと移動先の末尾
export function moveInquiry(id: number, input: InquiryMoveInput): Promise<Inquiry> {
  return apiPut<InquiryMoveInput, Inquiry>(`/api/inquiries/${id}/position`, input);
}

// POST /api/inquiries/sort（body なし、204）
export function sortInquiries(): Promise<void> {
  return apiPost<undefined, void>('/api/inquiries/sort');
}

// DELETE /api/inquiries/{id}（204）
export function deleteInquiry(id: number): Promise<void> {
  return apiDelete<void>(`/api/inquiries/${id}`);
}
