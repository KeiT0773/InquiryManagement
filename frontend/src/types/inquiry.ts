// API の要求・応答に対応する型（フロントエンド設計書 7.、API 設計書 4.・8.〜10.）。
// 項目名・型・NULL 可否は API 設計書から変えない。日付・日時は文字列のまま持ち、Date 型にはしない。

export type Category = 'question' | 'bug' | 'request' | 'other';
export type Priority = 'high' | 'medium' | 'low';
export type ListId = 'open' | 'working' | 'closed';

export type BoardList = {
  id: ListId;
  name: string;
  displayOrder: number;
};

export type Inquiry = {
  id: number;
  title: string;
  customerName: string;
  contact: string | null;
  category: Category;
  content: string;
  memo: string | null;
  assignee: string | null;
  receivedOn: string;
  dueOn: string | null;
  priority: Priority;
  listId: ListId;
  displayOrder: number;
  createdAt: string;
  updatedAt: string;
};

export type InquiryCreateInput = {
  title: string;
  customerName: string;
  content: string;
  category: Category;
  priority: Priority;
};

// 変える項目だけを送る。任意項目を空にするときは '' ではなく null を入れる
export type InquiryUpdateInput = Partial<{
  title: string;
  customerName: string;
  contact: string | null;
  category: Category;
  content: string;
  memo: string | null;
  assignee: string | null;
  dueOn: string | null;
  priority: Priority;
}>;

export type InquiryMoveInput = {
  listId: ListId;
  displayOrder?: number;
};
