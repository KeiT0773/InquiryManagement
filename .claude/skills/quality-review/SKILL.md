---
name: quality-review
description: このプロジェクトの実装を品質チェック・レビューする手順とチェックリスト。「品質チェックして」「レビューして」「標準から外れていないか見て」「文書と実装が合っているか確認して」「Terraform（インフラのコード）を確認して」と頼まれたとき、および PR を作る前のセルフレビュー（infra/ の変更を含む）で必ず使う。機械チェック → 文書との突き合わせ → 標準からのずれ、の順で確認し、結果を 3 区分で報告する。
---

# 品質レビューの手順

このプロジェクト（Ruby on Rails 8.1（API モード）/ Next.js 16 / MySQL 8.4 / Terraform + AWS の CloudFront・EC2・RDS）の実装を、**機械チェック → 文書との突き合わせ → 標準（デファクト）からのずれ** の順で確認する。文書と実装が食い違っていたら **文書を正** として実装を直す（文書どうしが矛盾しているときは 2. の末尾を参照）。

## 1. 機械チェックを回す（Git Bash）

```bash
# フロントエンド：コード検査 → 整形の確認 → 型検査 → テスト（npm run check に束ねる。雛形の作成時に定義する）
cd frontend && npm run check

# バックエンド：Rails はコンテナの中で実行する（PC に Ruby は無い）
docker compose up -d                                   # リポジトリルート。MySQL と Rails
docker compose exec backend bin/rubocop                # コード検査（rubocop-rails-omakase）
docker compose exec backend bin/brakeman --no-pager    # セキュリティ検査
docker compose exec backend bin/rails test             # テスト（MySQL が必要）

# インフラ（infra/ を変えたとき）：書式 → 文法 → 計画（読み取りのみ）→ スクリプトの構文
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan -lock=false     # apply はしない
for f in infra/scripts/*.sh; do bash -n "$f" || echo "NG: $f"; done
```

Rails 8.1 の雛形に `bin/ci`（上の 3 つをまとめて実行する仕組み）があれば、`docker compose exec backend bin/ci` で代えてよい。

| チェック | 合格条件 | 落ちたとき |
| --- | --- | --- |
| フロントエンドのコード検査（雛形に同梱のもの） | 0 件（warning もエラー扱い） | ルールを緩めるのではなくコードを直す。React の hooks の依存配列の指摘は必ず直す |
| Prettier | 全通過 | `npm run format`。改行が原因なら 6. の「改行コード」を確認 |
| TypeScript の型検査 | 0 件 | `any` や `!` で黙らせない |
| Vitest | 全通過 | 新しい振る舞いにはテストを足す。「修正前に落ち、修正後に通る」ことを確認する |
| RuboCop | 0 件 | `bin/rubocop -a` で安全な自動修正だけ当ててから残りを手で直す。規約を変えるなら理由を `.rubocop.yml` にコメントで書く |
| Brakeman | 警告 0 件 | 誤検知と判断した場合だけ `config/brakeman.ignore` に入れ、理由を `note` に書く |
| `bin/rails test` | 全通過 | テストを消して通さない。DB の構造が原因なら `bin/rails db:test:prepare` を実行する |
| `terraform fmt -check` | 差分なし | `terraform -chdir=infra/terraform fmt -recursive` で整形する |
| `terraform validate` | `Success!` | 未初期化なら `terraform -chdir=infra/terraform init -backend=false` |
| `terraform plan` | 変更の意図どおり。**意図しない `destroy` / `-/+`（作り直し）が無い**こと。特に RDS の作り直しはデータの消失につながる。EC2 の作り直しは `user_data` を変えたときだけ正常（EC2 は使い捨て。設計書 7.2） | 原因の行（`# forces replacement`）を特定して直す |
| `bash -n`（スクリプト） | エラーなし | 構文を直す |

Docker Desktop が止まっていてコンテナを起動できないときは、スキル `start-dev-servers` の手順に従う。DB 無しではバックエンドのテストは実行できないので、「テストは未実行」と明記して報告する。

## 2. 文書との突き合わせ

`docs/` の各文書と実装を、次の観点で読み比べる。根拠となる章番号を指摘に添える。

| 文書 | 確認する項目 |
| --- | --- |
| 要件定義書 10.・11. | 決定事項（登録は「未対応」だけ、必須項目は件名・問い合わせ者・問い合わせ内容、削除は確認ダイアログあり、対応者は自由入力で未割当は赤字、受付日は自動で変更不可、同時編集は後勝ち）と、受け入れ基準の各行を実装で満たせるか |
| 機能要件書 3. | 各機能の振る舞い。FR-01 の登録時の項目と初期値（種別「質問」、優先度「中」）、FR-02 で必須項目を空にしたときは保存しない、FR-04 の 2 通りのステータス変更（詳細画面からは移動先の末尾）、FR-09 の同時利用時の扱い |
| 機能要件書 3.1 | 並べ替えの規則：優先度（高→中→低）→ 同じ優先度の中は **対応期限の近い順、未設定は後ろ** → 優先度も期限も同じものは元の順序（安定ソート）。登録・優先度変更は **操作した問い合わせを、優先度も期限も同じまとまりの末尾** に置く。**移動・削除・期限の変更では並べ替えない**。FR-01 の対象は「未対応」だけ |
| 画面要件書 3.・5. | 3 列が横スクロール無しで見え、各列に件数。カード表面は件名・優先度・問い合わせ者（「様」付き）・対応者・種別・対応期限だけ。登録フォームは「未対応」列にだけあり、エラー表示・Esc で閉じる。問い合わせ詳細の項目と操作、削除の確認ダイアログ |
| データ要件書 2. | 項目・必須/任意・設定者。2.1 の文字数の上限（件名 100、問い合わせ者 50、連絡先 100、問い合わせ内容 2,000、対応メモ 2,000、対応者 50）を **前後の空白を除いてから** 判定、2.2 の空の値の扱い（任意項目の空は「値なし」）、2.3 の個人情報の扱い |
| 技術スタック 3.〜6. | **書かれている gem・npm パッケージが実際に `Gemfile` / `package.json` に入っているか**（選定済みなのに未導入、またはその逆）。版数の記述が実物と合っているか。ポート（3000 / 3001 / 3306）、CORS の許可元が開発時の `http://localhost:3000` だけか、Next.js が `output: 'export'` で書き出しサーバーでだけ動く機能を使っていないか |
| データ設計書 4.〜7.・10. | マイグレーションの結果（`db/schema.rb`）が 4. のテーブル定義・5. の制約（`CHECK`・外部キー・索引）と一致するか。空白だけの値・空文字を `NULL` にしてから保存しているか（全角の空白も含む）。受付日は `Time.zone.today`（日本時間）で設定しているか。表示順を振り直すトランザクションは、対象のリストの `lists` の行を `display_order` の小さい順に行ロックしてから読み直しているか（6.2）。`lists` の初期データはマイグレーション、サンプルデータは `db/seeds/development.rb` にあるか |
| API 設計書 2.・2.1〜2.3 | ベースパス `/api`、camelCase、日付 `YYYY-MM-DD`、日時は UTC の `Z`（ミリ秒まで）、値が無い項目は `null` で省略しない、区分値は DB の値のまま。エラーは Problem Details（`title` / `status` / `detail` / `instance`、`detail` は日本語、`Content-Type: application/problem+json`）。入力チェックは 422 で `errors`（`field` は camelCase）付き、JSON として読めない要求は 400、`id` が数値でない・存在しないは 404。CORS は開発環境の `http://localhost:3000` だけ |
| API 設計書 8.〜12.・14. | 各 API の「処理」の手順どおりか。登録は `listId` を受け取らず必ず「未対応」、受付日はサーバーが設定。編集は `PATCH` で **送られた項目だけ** を変える（キーの有無で「送らない」と「`null`」を区別）、優先度が変わったときだけ並べ直す。移動の `displayOrder` は「自分を除いた並びの位置」で、省略・件数以上なら末尾。表示順を振り直す API は `lists` の行をロックしてから処理。並べ替えは安定ソート（Ruby の `sort_by` に元の位置を加える。14.） |
| フロントエンド設計書 2.・5. | 失敗の文言の場所（取得はボード全体／登録はフォームの中／編集はその項目の下／削除は詳細のフッター／移動・並べ替え・詳細を開く操作はボード上部）。書き込み後は応答を差し込まず影響を受けたリストを `GET` で取り直す。楽観更新は D&D だけ。404 は「ほかのメンバーが削除」として全件を取り直す。詳細を開く前に `GET /api/inquiries/{id}` で最新の 1 件を取る |
| フロントエンド設計書 4.・7.・8. | 部品の責務と props、型が API 設計書 4. と 1 対 1 か。登録フォームは「未対応」だけで、必須 3 項目の空は送らず赤枠と項目名の文言。詳細は項目ごとに確定した **その項目だけ** を `PATCH`（変更が無ければ送らない、必須項目の空は元に戻す）。ステータスの選択は `displayOrder` なしで移動。削除は `window.confirm` を経る。対応者の未割当は赤字、期限超過は「完了」以外だけ |
| インフラ設計書 | 5. のチェックリストを参照 |

文書どうしが矛盾しているときは、**決定事項として明記されている方を正** とし、もう一方の文書を直す。文書を直したら版数・最終更新日・変更履歴の 3 つを更新する（CLAUDE.md 5.）。

## 3. バックエンドのチェックリスト（Rails の標準）

- Controller は HTTP の変換（パラメータの受け取り、Strong Parameters、ステータスコード、JSON の組み立て）だけ。業務の処理（並べ替え、表示順の振り直し）はモデルか、`app/models` に置いた処理用のクラス（PORO）にまとめる
- 複数の行を書き換える処理（表示順の振り直しなど）は `ActiveRecord::Base.transaction` で 1 トランザクションにする
- 入力チェックはモデルの validations に書き、DB の制約（`null: false`、文字数、外部キー）と二重にかける。前後の空白の除去（`normalizes`）は検証の **前** に済ませる
- 応答の JSON は、返す項目を明示して組み立てる（`render json: model` でモデルの全列をそのまま返さない）
- マイグレーション：適用済みのファイルは編集しない。定義の変更は新しいマイグレーションを追加する。`db/schema.rb` はコミットする
- N+1 問題（一覧の取得でレコードごとに SQL が出る）が無いこと
- gem を増やすときは技術スタック文書 3. に行を追加する。「必要になるまで追加しない」（技術スタック 2.）
- テストは Minitest。API ごとに統合テスト（`ActionDispatch::IntegrationTest`）を書く。テストのデータは fixtures を使い、テストごとにロールバックされることを前提にする
- 標準から外れていても **理由がコメントに書かれていれば** 許容する。理由が無ければ指摘する

## 4. フロントエンドのチェックリスト（Next.js・React の標準）

- App Router を使い、`next.config` に `output: 'export'` がある。サーバーでだけ動く機能（サーバーでのデータ取得、Route Handlers、`rewrites`、`headers`、画像の最適化など）を使っていない（技術スタック 4.）
- 操作を扱う部品はクライアントコンポーネント（`'use client'`）にし、必要な範囲だけに付ける
- 関数コンポーネント + hooks。`useEffect` は依存配列を正しく書き、非同期処理にはクリーンアップ（`cancelled` フラグなど）を付ける
- 一覧の `key` は `id`。配列の添字を使わない
- 状態は最小限：一覧はボードの状態を持つ 1 か所（フック）だけが持ち、入力の下書きは入力側の部品が持つ。状態管理ライブラリは入れない
- API の呼び出しは `src/api/` などの薄い関数を経由し、部品から `fetch` を直接呼ばない。API の URL は環境変数で切り替える（技術スタック 4.）
- a11y：失敗の文言は `role="alert"`、`<label htmlFor>` + `id`、モーダルは `role="dialog"` + `aria-modal` + `aria-labelledby`、ボタンは `<button type="button">`
- スタイルは CSS Modules。色や寸法は画面モック（`mock/style.css`）に合わせる
- テストは Testing Library の役割・名前（`getByRole`、`findByText`）で要素を取り、クラス名や内部状態を見ない。`fetch` は `vi.stubGlobal` で差し替える
- 部品の名前と責務は[フロントエンド設計書](../../../docs/frontend-design.md) 3.・4. に従う（`useBoard` だけが一覧を持ち、`AddInquiryForm` / `InquiryDetail` は下書きを持って関数に送信を委ねる。`InquiryDetail` は `key={inquiry.id}` で作り直す）

## 5. インフラ（Terraform・スクリプト）のチェックリスト

`infra/` を変えたとき、またはレビューを頼まれたときに確認する。根拠はインフラ設計書（作成後に章番号を追記する）。

**規模と費用（要件定義書 7.「費用」）**
- EC2・RDS の規模が設計書 2.1 の上限（`t3.micro`、`db.t4g.micro` / `db.t3.micro`、gp3 20 GB）を超えていない。`variables.tf` の validation で制限している
- 有料の追加機能（RDS の拡張モニタリング、NAT Gateway、AWS WAF、Secrets Manager など）を足していない。足すなら費用の見積もりも更新する

**秘密情報と Git**
- パスワード・アクセスキーをコードや `compose.yaml`・`config/` に書いていない。Rails の `config/master.key` と `.env` はコミットしない
- `infra/.gitignore` で `.terraform/`・`*.tfstate*`・`*.tfvars`（`.example` は除く）・`tfplan*` を除外している。plan ファイルには秘密の値が入るため、絶対にコミットしない
- `.terraform.lock.hcl` はコミットする

**書き方の標準**
- `required_version` とプロバイダーの `version = "~> X.Y"` で版を固定している
- 共通のタグは `provider` の `default_tags` で付ける。リソース名は変数のプロジェクト名から作る
- 入力の検査は `variable` の `validation`、作る前の条件は `lifecycle.precondition`。エラー文は日本語で、何をすればよいかまで書く
- データを持つリソース（RDS）が作り直し（`-/+`）にならない。EC2 は `user_data` を変えたときだけ作り直しになり、それ以外の変更で作り直しにならない

**セキュリティ（要件定義書 7.「データ保護」「アクセス制御」）**
- RDS は `publicly_accessible = false` で、受け付けるのは EC2 のセキュリティグループからだけ
- EC2 のセキュリティグループの受信は、CloudFront のマネージドプレフィックスリストからの 80 番だけ。SSH の 22 番を開けていない・キーペアを作っていない（設計書 5.3）
- nginx が `X-Origin-Verify` ヘッダーを確かめ、一致しなければ 403 を返す。値は SSM から読み、コードや `user_data` に書いていない（設計書 6.2・9.）
- RDS との接続が TLS 必須（`ssl_mode: required`）。Rails の `assume_ssl` が有効（設計書 6.3・7.3）
- アクセス元の制限（CloudFront Functions）が、画面と `/api/*` の **両方** に付いている。許可リストに IPv4 や広い範囲を入れていない
- IAM のポリシーは対象を絞っている（`"Resource": "*"` を安易に使わない）

**適用**
- レビューで行うのは `plan` まで。`apply` / `destroy` はレビューの中では行わない。適用は PR をマージした後の main で、スキル `deploy-aws` の手順に従う

## 6. 横断のチェック

- **改行コード**：ルートの `.gitattributes`（`* text=auto eol=lf`）と `.editorconfig` により LF。`git ls-files --eol | grep 'w/crlf'` が `*.bat` 以外を返したら直す。Rails の `bin/` のスクリプトが CRLF になるとコンテナで動かないので特に注意する
- README のコマンドは Git Bash 構文。Rails のコマンドは `docker compose exec backend` を付けた形で書く（CLAUDE.md 3.）
- 文書を変えたら版数・最終更新日・変更履歴（CLAUDE.md 5.）。依存や設定を足したら技術スタック文書と README も更新
- 新しい npm スクリプトや Rails のタスクを足したら、`frontend/README.md` / `backend/README.md` / ルートの `README.md` の表に追記

## 7. 報告の形式

結果は次の 3 区分に分けて報告する。各項目に根拠（文書の章番号、または標準の名前）を添える。

1. **文書と実装の食い違い**（文書を正として直すもの）
2. **標準からのずれ**（直すもの／直さないもの。**直さない判断にも理由を書く**）
3. **確認して問題なしと判断したもの**（何を見て問題なしとしたかを 1 行で）

修正は CLAUDE.md 2. の開発フロー（Issue → ブランチ → PR）に従い、PR のマージはユーザーの承認を得てから行う。レビューの結果がどうであれ、GitHub のリポジトリそのものは削除しない（スキル `deploy-aws` の 0.）。
