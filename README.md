# 問い合わせ管理アプリ

カンバンボード方式の問い合わせ管理アプリ。問い合わせを登録し、ステータス（未対応 / 対応中 / 完了）で管理する。

| 層 | 技術 | ディレクトリ |
| --- | --- | --- |
| フロントエンド | Next.js（静的書き出し） | [frontend/](frontend/) |
| バックエンド | Ruby on Rails（API モード） | [backend/](backend/) |
| データベース | MySQL 8.4 | `compose.yaml`（ローカル） |
| 本番環境 | AWS（CloudFront + EC2 + RDS） | `infra/`（作成予定） |

要件と設計は [docs/](docs/)、Claude Code が従うルールは [CLAUDE.md](CLAUDE.md)、画面モックは [mock/](mock/) にある。

## ローカルでの起動

必要なもの：Docker Desktop、Node.js 24。コマンドは Git Bash で、リポジトリのルートから実行する。

```bash
docker compose up -d                                  # MySQL（3306）と Rails（3001）
docker compose exec backend bin/rails db:prepare      # 初回だけ

cd frontend
npm install                                           # 初回だけ
npm run dev                                           # Next.js（3000）
```

| URL | 内容 |
| --- | --- |
| http://localhost:3000 | 画面 |
| http://localhost:3001/up | バックエンドの死活確認（200 なら起動している） |

詳しくは [backend/README.md](backend/README.md)・[frontend/README.md](frontend/README.md) を参照。
