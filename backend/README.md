# backend（Ruby on Rails、API モード）

問い合わせ管理アプリのバックエンド。Ruby 4.0 / Rails 8.1 / MySQL 8.4（[技術スタック](../docs/tech-stack.md) 3.）。

**PC に Ruby は入れない。** Rails は Docker Compose のコンテナ（`backend`）の中で動かし、Rails のコマンドは必ず `docker compose exec backend` を付けて実行する（[CLAUDE.md](../CLAUDE.md) 3.）。

## 起動と停止

コマンドはすべて Git Bash で、リポジトリのルートから実行する。

```bash
docker compose up -d                                  # MySQL（3306）と Rails（3001）を起動
docker compose exec backend bin/rails db:prepare      # 初回だけ：テーブルを作り、リストとサンプルデータを入れる
curl http://localhost:3001/up                         # 200 なら起動している
docker compose logs -f backend                        # Rails のログを見る
docker compose stop                                   # 停止（データは残る）
```

ポートは変えない（[CLAUDE.md](../CLAUDE.md) 6.）。

## よく使うコマンド

| コマンド | 内容 |
| --- | --- |
| `docker compose exec backend bin/ci` | 機械チェックを一括で実行（RuboCop・bundler-audit・Brakeman・テスト・seed の確認） |
| `docker compose exec backend bin/rubocop` | コード検査（rubocop-rails-omakase） |
| `docker compose exec backend bin/brakeman --no-pager` | セキュリティ検査 |
| `docker compose exec backend bin/rails test` | テスト |
| `docker compose exec backend bin/rails db:migrate` | マイグレーションの適用 |
| `docker compose exec backend bin/rails db:seed` | リストの 3 件と開発用のサンプルデータ 8 件を入れる（何度実行しても重複しない。[データ設計書](../docs/data-design.md) 10.4） |
| `docker compose exec backend bin/rails console` | Rails のコンソール |
| `docker compose exec backend bundle install` | `Gemfile` を変えたあとの gem の導入（`Gemfile.lock` も更新される） |
| `docker compose down -v` | コンテナと DB のデータを消す（開発中にやり直したいときだけ） |

Claude Code のシェルなど、端末が無い環境から `docker compose exec` を実行するときは、`-T` を付ける（例：`docker compose exec -T backend bin/ci`）。付けないと、端末の割り当てを待って止まる。

## ファイル

| ファイル | 内容 |
| --- | --- |
| `Dockerfile.dev` | ローカル開発用のイメージ（`compose.yaml` の `backend`）。ソースはマウントする |
| `Dockerfile` | 本番用のイメージ（Rails の雛形のまま。[インフラ設計書](../docs/infra-design.md) 7.3） |
| `config/database.yml` | 接続先は環境変数（`DATABASE_HOST`・`DATABASE_USERNAME`・`DATABASE_PASSWORD`）で渡す |
| `config/initializers/cors.rb` | 開発時だけ `http://localhost:3000` からの呼び出しを許可する |
| `config/locales/ja.yml` | 入力チェックのメッセージ（日本語） |
