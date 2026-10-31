import type { Metadata } from 'next';
import './globals.css';

// HTML の骨組み。サーバーコンポーネントで、書き出し時に HTML になる（フロントエンド設計書 3.）
export const metadata: Metadata = {
  title: '問い合わせ管理ボード',
};

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
