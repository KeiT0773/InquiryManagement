import type { NextConfig } from 'next';

// 本番は静的ファイルに書き出し（out/）、EC2 上の nginx で配信する（技術スタック 4.、フロントエンド設計書 2.）。
// Next.js のサーバーは本番で動かないため、サーバーでだけ動く機能（rewrites、画像の最適化など）は使わない。
const nextConfig: NextConfig = {
  output: 'export',
};

export default nextConfig;
