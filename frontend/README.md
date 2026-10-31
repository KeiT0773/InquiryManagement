# frontend（Next.js）

問い合わせ管理アプリのフロントエンド。Next.js 16（App Router）/ React 19 / TypeScript（[技術スタック](../docs/tech-stack.md) 4.）。設計は [フロントエンド設計書](../docs/frontend-design.md) を参照。

本番は静的ファイルに書き出し（`output: 'export'`）、EC2 上の nginx で配信する。Next.js のサーバーは本番では動かないため、サーバーでだけ動く機能（サーバーでのデータ取得、Route Handlers、`rewrites`、画像の最適化など）は使わない。

## 起動

コマンドは Git Bash で実行する。先にリポジトリのルートで `docker compose up -d` を実行し、バックエンド（http://localhost:3001）を起動しておく（[CLAUDE.md](../CLAUDE.md) 4.）。

```bash
cd frontend
npm install       # 初回と、package.json が変わったとき
npm run dev       # http://localhost:3000
```

ポートは変えない（[CLAUDE.md](../CLAUDE.md) 6.）。3000 が使用中だと Next.js は自動で別のポートへ移るので、起動時に表示される URL が http://localhost:3000 か確かめる。

## よく使うコマンド

| コマンド | 内容 |
| --- | --- |
| `npm run check` | 機械チェックを一括で実行（コード検査 → 整形の確認 → 型検査 → テスト） |
| `npm run lint` | コード検査（ESLint。警告も失敗にする） |
| `npm run format` | 整形（Prettier） |
| `npm run typecheck` | 型検査（`next typegen` で Next.js の型を作ってから `tsc`） |
| `npm test` | テスト（Vitest） |
| `npm run build` | 本番用の静的ファイルを `out/` に書き出す |

## API の接続先

API の URL の先頭は環境変数 `NEXT_PUBLIC_API_BASE_URL` で切り替える（[フロントエンド設計書](../docs/frontend-design.md) 9.）。

| ファイル | 値 | 使われるとき |
| --- | --- | --- |
| `.env.development` | `http://localhost:3001` | `npm run dev`。Rails を直接呼ぶ（Rails が CORS で許可している） |
| `.env.production` | 空 | `npm run build`。画面と同じドメインの `/api` を呼ぶ |

値はビルド時にコードへ埋め込まれる。秘密の値ではないため、どちらのファイルもコミットする。
