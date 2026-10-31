import { AppHeader } from '@/components/AppHeader/AppHeader';
import { Board } from '@/components/Board/Board';

// 画面全体（フロントエンド設計書 3.・4.）。ヘッダーとボードを縦に並べるだけ
export default function Home() {
  return (
    <>
      <AppHeader />
      <Board />
    </>
  );
}
