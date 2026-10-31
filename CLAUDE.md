# CLAUDE.md

このファイルは Claude Code がこのリポジトリで作業するときに必ず従うルールを定義する。
人間向けの詳しい解説は [docs/development-workflow.md](docs/development-workflow.md) を参照。

---

## 1. プロジェクト概要

カンバンボード方式の問い合わせ管理アプリ。問い合わせを登録し、ステータス（未対応 / 対応中 / 完了）で管理する。ボードの構造は先行プロジェクトのタスク管理アプリ（`KeiT0773/TASKMANAGEMENT`）と同じにする。Web アプリケーション開発の流れ（要件定義 → 設計 → 実装）を実践的に学ぶことも目的の一つ。

文書は次の構成で作る（「作成予定」のものは未作成）。

| 文書 | 内容 |
| --- | --- |
| [要件定義書](docs/requirements.md) | 背景・目的、スコープ、非機能要件、制約、決定事項、受け入れ基準（上位文書） |
| [機能要件書](docs/functional-requirements.md) | 機能一覧と機能ごとの詳細（FR-01〜FR-10） |
| [画面要件書](docs/screen-requirements.md) | 画面一覧、画面構成、画面遷移、画面イメージ（SC-01 ボード画面, SC-02 問い合わせ詳細） |
| [データ要件書](docs/data-requirements.md) | データ項目の定義、ER図、データフロー図 |
| [データ設計書](docs/data-design.md) | テーブル定義、制約、初期データ、マイグレーション方針 |
| [API 設計書](docs/api-design.md) | REST API の一覧、共通方針、要求・応答の JSON 形式 |
| [フロントエンド設計書](docs/frontend-design.md) | コンポーネント構成、状態の持ち方、API 呼び出しの方針、表示ルール |
| [技術スタック](docs/tech-stack.md) | 各層で使用する言語・フレームワーク・周辺ツールの選定と理由 |
| [インフラ設計書](docs/infra-design.md) | AWS 上の構成（CloudFront + EC2 + RDS）、ネットワーク、秘密情報、費用、Terraform の構成 |
| [AWS デプロイ手順書](docs/aws-deployment-guide.md) | AWS・Terraform・IaC の解説、AWS CLI の認証設定、構築・更新・休止・再開の手順（作成予定） |
| [開発フロー](docs/development-workflow.md) | Issue・ブランチ・PR の運用ルール |

構成は `docs/`（要件定義書・設計書）、`mock/`（画面モック）、`backend/`（Ruby on Rails、API モード）、`frontend/`（Next.js）、`infra/`（AWS の構成の Terraform とデプロイ用スクリプト）、`compose.yaml`（ローカル開発用の Rails と MySQL）。技術の選定はタスク管理アプリと異なる（[技術スタック](docs/tech-stack.md)）。現時点で存在するのは `docs/` と `mock/` だけで、`backend/`・`frontend/`・`infra/`・`compose.yaml` はこれから作る。

---

## 2. 開発フロー（必須・例外なし）

コードや文書を変更するときは、**必ず**次の順序を踏むこと。

### 手順

```bash
# 1. Issue を起票する（Issue のない作業は始めない）
gh issue create

# 2. main を最新にしてからブランチを切る
git switch main
git pull --ff-only
git switch -c feat/12-inquiry-create

# 3. 変更してコミットし、push する
git add <変更したファイル>
git commit -m "feat: 問い合わせ登録機能を追加"
git push -u origin feat/12-inquiry-create

# 4. PR を作る（本文に Closes #12 を必ず入れる）
gh pr create

# 5. squash マージする（マージ後、ブランチは自動削除される）
gh pr merge --squash
```

### 禁止事項

以下はローカルのフックと GitHub の Ruleset の両方でブロックされる。回避を試みてはならない。

- `main` ブランチ上でのコミット
- `main` ブランチへの直接 push
- force push（`git push --force`、`git push +...`）
- `main` へのローカル merge（マージは必ず GitHub 上の PR で行う）
- `main` ブランチの削除

次は Claude の設定（`.claude/settings.json` の `deny`）で禁止している。頼まれても実行せず、必要なら本人がブラウザの GitHub の画面で行う。

- GitHub リポジトリの削除・アーカイブ・名前の変更（`gh repo delete` / `archive` / `rename`、`gh api` での `DELETE`）

### ブランチ命名規則

```
<種別>/<Issue番号>-<英小文字の要約>
```

| 種別 | 用途 |
| --- | --- |
| `feat` | 機能追加 |
| `fix` | バグ修正 |
| `docs` | 文書のみの変更 |
| `refactor` | 挙動を変えない内部改善 |
| `test` | テストの追加・修正 |
| `chore` | ビルド設定、依存関係、開発環境など |

例：`feat/12-inquiry-create`、`fix/15-due-date-timezone`、`docs/18-add-api-spec`

要約部分は英小文字・数字・ハイフンのみ。次の正規表現に適合しない名前でブランチを作ろうとすると、ローカルのフックが拒否する。

```
^(feat|fix|docs|refactor|test|chore)/[0-9]+-[a-z0-9._-]+$
```

### コミットメッセージ

```
<種別>: <日本語の要約>
```

種別はブランチ名と同じ 6 種。要約は「何をしたか」を体言止めまたは「〜を追加/変更/修正」で書く。

例：`feat: 問い合わせ登録機能を追加`、`docs: データ設計書にインデックス定義を追加`

必要なら空行を挟んで本文で理由を書く。Claude が作成したコミットには末尾に共著者行を入れる。

### PR

- タイトルは squash マージ後の main のコミットメッセージになるため、コミットメッセージと同じ規約で書く
- 本文には `Closes #<Issue番号>` を必ず入れる（マージ時に Issue が自動クローズされる）
- テンプレート [.github/pull_request_template.md](.github/pull_request_template.md) の項目を埋める
- 承認者は不要（ソロ開発のため）だが、PR を経由すること自体は必須

---

## 3. ユーザーに渡すコマンドの書き方

**ユーザーが自分で打つコマンドは Git Bash 構文で書くこと。**

ユーザーは Cursor のターミナルパネルで Git Bash を使っている。セッション環境が PowerShell を報告することがあるが、それはツールが使えるシェルであって、ユーザーが実際に触っているシェルではない。

| 正しい（Git Bash） | 誤り（PowerShell/cmd） |
| --- | --- |
| `docker compose exec backend bin/rails db:migrate` | `docker compose exec backend bin\rails db:migrate` |
| `cd frontend/src` | `cd frontend\src` |
| `curl http://localhost:3001/up` | `curl.exe ...` |

シェルによって内容が変わるコマンドを書くときは、どちらのシェル向けかを明記する。

Ruby は PC に入れず、Rails のコマンド（`bin/rails`、`bin/rubocop`、`bundle` など）は **必ず `docker compose exec backend` を付けてコンテナの中で実行する**（[技術スタック](docs/tech-stack.md) 6.）。

**Claude が自分で `docker compose exec` を実行するときは `-T` を付ける**（例：`docker compose exec -T backend bin/ci`）。Claude のシェルには端末が無く、`-T` が無いと端末の割り当てを待って止まる。ユーザーに渡すコマンドには付けなくてよい。

### Git Bash から `gh api` を使うときの注意

Git Bash（MSYS）はスラッシュで始まる引数を Windows のパスとして書き換えてしまう。`gh api` のエンドポイントは **先頭のスラッシュを省く**こと。

```bash
gh api repos/KeiT0773/InquiryManagement/rulesets   # 正しい
gh api /repos/KeiT0773/InquiryManagement/rulesets  # invalid API endpoint エラーになる
```

---

## 4. ローカル環境

```bash
# 1. データベースとバックエンド（リポジトリルートで実行。MySQL と Rails のコンテナが起動する）
docker compose up -d
docker compose exec backend bin/rails db:prepare   # 初回だけ（テーブルの作成と、リスト・サンプルデータの投入）

# 2. フロントエンド（別のターミナルで）
cd frontend
npm run dev
```

画面は http://localhost:3000 。バックエンドの動作確認は http://localhost:3001/up （Rails 標準の死活確認）。詳細は backend/README.md・frontend/README.md（雛形の作成時に作る）を参照。

---

## 5. 文書を変更するときの約束

`docs/` 配下の文書には文書情報テーブルと変更履歴テーブルがある。内容を変更したときは、**版数・最終更新日・変更履歴の 3 つを必ず更新する**こと。版数は軽微な追記なら小数点以下を、構成の変更を伴うなら整数部を上げる。

---

## 6. サーバー起動時のポート（必須・例外なし）

サーバーは **必ず既定のポートで起動する**。ポートが使用中でも、別のポートへ逃げてはならない。

| サーバー | ポート | 根拠 |
| --- | --- | --- |
| フロントエンド（Next.js） | 3000 | Next.js の既定。`npm run dev` にポートの指定は付けない |
| バックエンド（Rails） | 3001 | `compose.yaml` で Rails を 3001 で起動する（Rails の既定 3000 は Next.js と重なるため。[技術スタック](docs/tech-stack.md) 6.1） |
| MySQL（Docker） | 3306 | `compose.yaml` |

### ポートが使用中のとき

1. そのポートを占有しているプロセスを調べる（`Get-NetTCPConnection -LocalPort 3000 -State Listen` → `Get-CimInstance Win32_Process -Filter "ProcessId=<PID>"`）。3001・3306 が Docker のものなら `docker compose ps` で確かめる
2. このアプリ自身の古いサーバー（node/next、このリポジトリの Docker Compose のコンテナ）なら **停止する**。無関係のプロセスなら、何が動いているかをユーザーに伝えてから停止する
3. 既定のポートで起動し直す
4. ユーザーのターミナルで動いていたサーバーを止めた場合は、止めたことと起動し直す必要があることを必ず伝える

手順の全文はスキル `start-dev-servers`（[.claude/skills/start-dev-servers/SKILL.md](.claude/skills/start-dev-servers/SKILL.md)）にある。サーバーを起動・再起動するときは必ずこのスキルに従う。

### 禁止事項

以下は [.claude/hooks/guard-ports.ps1](.claude/hooks/guard-ports.ps1)（PreToolUse フック）が実行前に拒否する。

- `npx next dev -p 3002`、`npm run dev -- --port 3002`、`PORT=3002 npm run dev` のように、フロントエンドを 3000 以外で起動する
- `bin/rails server -p 3002`、`bin/rails s --port=3002`、`PORT=3002 bin/rails s` のように、バックエンドを 3001 以外で起動する

理由：CORS で許可する送信元、README の URL、ユーザーがブラウザで開いているページはすべて既定ポートを前提にしている。別ポートで起動すると、ユーザーが見ているサーバーと Claude が確認したサーバーが別物になり、「Claude の環境では動くのにユーザーの画面では動かない」食い違いが生じる。動作確認のために Claude が立てたサーバーは、確認後に必ず停止する。

---

## 7. 品質チェック・レビュー

実装の品質チェックやレビューを行うとき、および PR を作る前のセルフレビューは、スキル `quality-review`（[.claude/skills/quality-review/SKILL.md](.claude/skills/quality-review/SKILL.md)）に従う。機械チェック（`cd frontend && npm run check`、`docker compose exec -T backend bin/ci`）→ 文書との突き合わせ → 標準からのずれ、の順で確認し、文書と実装が食い違っていれば文書を正として実装を直す。

---

## 8. AWS へのデプロイ

AWS への構築・更新・休止・再開と、`infra/` の Terraform・スクリプトの実行は、スキル `deploy-aws`（[.claude/skills/deploy-aws/SKILL.md](.claude/skills/deploy-aws/SKILL.md)）に従う。具体的な手順は、`infra/` の Terraform とスクリプトを作るときにスキルへ書き足す。

- AWS の実物を変える操作は、内容（計画の集計など）を示して利用者の承認を得てから行う。スクリプトの `--yes` は承認後にだけ付ける
- 撤去（`terraform destroy`、`aws ... delete-*`、`aws ec2 terminate-instances` など）は、消えるものを示し、その会話の中で利用者が明示的に承認してから実行する。前の承認は使い回さず、`-auto-approve` は付けない
- `~/.aws/credentials` を読まない。アクセスキーを会話に出さない
- 作業の最後に、稼働中か休止中かを報告する（稼働中は約 0.05 ドル / 時間かかる。[インフラ設計書](docs/infra-design.md) 11.）
- リソースの規模は、無料利用枠の対象と同じ規模を上限とする（[インフラ設計書](docs/infra-design.md) 2.1）
