---
name: quality-review
description: このプロジェクトの実装を品質チェック・レビューする手順とチェックリスト。「品質チェックして」「レビューして」「標準から外れていないか見て」「文書と実装が合っているか確認して」「Terraform（インフラのコード）を確認して」と頼まれたとき、および PR を作る前のセルフレビュー（infra/ の変更を含む）で必ず使う。機械チェック → 文書との突き合わせ → 標準からのずれ、の順で確認し、結果を 3 区分で報告する。
---

# 品質レビューの手順

このプロジェクト（Spring Boot 4 / React 19 / PostgreSQL 16 / Terraform + AWS）の実装を、**機械チェック → 文書との突き合わせ → 標準（デファクト）からのずれ** の順で確認する。文書と実装が食い違っていたら **文書を正** として実装を直す（文書どうしが矛盾しているときは 2. の末尾を参照）。

## 1. 機械チェックを回す（Git Bash）

```bash
# フロントエンド：lint（warning もエラー）→ Prettier → tsc → Vitest
cd frontend && npm run check

# バックエンド：Checkstyle → javac -Xlint:all -Werror → テスト（PostgreSQL が必要）
docker compose up -d                 # リポジトリルート
cd backend && ./gradlew check

# インフラ（infra/ を変えたとき）：書式 → 文法 → 計画（読み取りのみ）→ 関数のテスト → スクリプトの構文
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan -lock=false     # apply はしない
node --test infra/terraform/functions/viewer-allowlist.test.mjs
for f in infra/scripts/*.sh; do bash -n "$f" || echo "NG: $f"; done
```

| チェック | 合格条件 | 落ちたとき |
| --- | --- | --- |
| `oxlint --deny-warnings` | 0 件 | ルールを緩めるのではなくコードを直す。`react/exhaustive-deps` の指摘は依存配列の漏れなので必ず直す |
| `prettier --check` | 全通過 | `npm run format`。改行が原因なら 6. の「改行コード」を確認 |
| `tsc -b` | 0 件 | TS 6 は `strict` が既定で有効。`any` や `!` で黙らせない |
| `vitest run` | 全通過 | 新しい振る舞いにはテストを足す。「修正前に落ち、修正後に通る」ことを確認する |
| Checkstyle | 0 件（`build/reports/checkstyle/`） | 既存コードと衝突するルールならルール側を直してよいが、`NeedBraces` / `UnusedImports` 等の明らかな改善はコードを直す |
| `-Werror` | コンパイル成功 | 警告の原因を直す。`@SuppressWarnings` は理由をコメントに書く |
| `terraform fmt -check` | 差分なし | `terraform -chdir=infra/terraform fmt -recursive` で整形する |
| `terraform validate` | `Success!` | 未初期化なら `terraform -chdir=infra/terraform init -backend=false`（state に接続せずに文法だけ確認できる） |
| `terraform plan` | 変更の意図どおり。**意図しない `destroy` / `-/+`（作り直し）が無い**こと。特に `aws_db_instance.main` の作り直しはデータの消失につながる | 原因の行（`# forces replacement`）を特定して直す。休止中は全件が `+`（作成）になるのが正常 |
| `node --test`（CloudFront Functions） | 全通過 | 関数を変えたらテストも足す。許可・拒否の両方の場合を確かめる |
| `bash -n`（スクリプト） | エラーなし | 構文を直す。shellcheck は未導入（導入するなら技術スタックに追記） |

`terraform plan` は AWS の情報を読むため、AWS の認証（`aws sts get-caller-identity`）と `init` 済みであることが必要。読み取りだけなので AWS の実物は変わらないが、`-lock=false` を付けて state 用バケットにロック用のファイルも書かないようにする。tflint は未導入のため任意（導入するなら技術スタックに追記する）。

Docker Desktop が止まっていて DB を起動できないときは、スキル `start-dev-servers` の手順に従う。DB 無しではバックエンドのテストは実行できない（`BackendApplicationTests` も実 DB に接続する）ので、「テストは未実行」と明記して報告する。

## 2. 文書との突き合わせ

`docs/` の各文書と実装を、次の観点で読み比べる。根拠となる章番号を指摘に添える。

> 下表の章番号・規則・名前は、先行プロジェクトのタスク管理アプリの文書に基づく。本プロジェクトの文書（要件定義書〜設計書）が揃ったら、その内容に合わせて書き直す。それまでは観点の例として使う。

| 文書 | 確認する項目 |
| --- | --- |
| 機能要件書 3.1 | 優先度順の並べ替え規則：登録・優先度変更は **操作したカードを同じ優先度の末尾** に置く。FR-10（全リスト並べ替え）には「操作したカード」が無い。**移動・削除では並べ替えない**。同じ優先度の中の順序は保つ（安定ソート） |
| API 設計書 2. | ベースパス `/api`、camelCase、日付 `YYYY-MM-DD`、日時は UTC で末尾 `Z`（マイクロ秒まで）、値が無い項目は `null` で省略しない、区分値は DB の値のまま |
| API 設計書 2.1・2.2 | エラーは `ProblemDetail`（`title` / `status` / `detail` / `instance`）。入力チェックの 400 は `detail` に日本語を「、」で連結し `errors` を付ける。ステータスの使い分け（201 + `Location`、204 は sort と delete、body の `listId` 不在は 404 ではなく 400） |
| API 設計書 8.〜12. | 各 API の「処理」の手順どおりか。`title` は **前後の空白を除いてから** 1〜100 文字を判定、`priority` 省略時は `medium`、`description` の空白のみは `null`、移動の `displayOrder` は「自分を除いた並びの位置」で枚数以上なら末尾、削除後は `displayOrder` を詰める |
| フロントエンド設計書 2. 方針 7〜9 | 失敗文言の場所（取得はボード全体／登録・編集はその入力欄／移動・並べ替えはボード上部／削除はカード詳細のフッター）。**上部の文言は次の操作（移動・編集・登録・削除）が成功したときにも消す**。書き込み後は応答を差し込まず `GET` で取り直す。楽観更新は D&D だけ |
| フロントエンド設計書 4.2・8.5〜8.8 | コンポーネントの責務と props、追加フォーム・カード詳細・D&D・ツールバーの挙動表（保存の契機、Escape・背景クリックで閉じる、`maxLength`、フォーカスの位置） |
| 画面要件書 3.・5. | 3 列が横スクロール無しで見える、ツールバーはリストの枠の外、追加フォームは列の最下部、カード表面はタイトル・優先度・期限のみ、削除ボタンはカード詳細の下部 |
| データ設計書 2.・6. | 空文字は保存せず `NULL`、`display_order` は 0 からの連番で毎回振り直す、振り直しは 1 トランザクション、Flyway の適用済みファイルは編集しない |
| 技術スタック 3.〜4. | **書かれているライブラリが実際に `build.gradle` / `package.json` に入っているか**（選定済みなのに未導入、またはその逆）。バージョンの記述が実物と合っているか |
| 要件定義書 10.・11. | 決定事項（削除の確認ダイアログ無し、リスト固定、優先度 3 段階）と受け入れ基準の各行を実装で満たせるか |
| 要件定義書 7.（費用・アクセス制御・データ保護）、インフラ設計書 | `infra/terraform/` のリソース・規模・ネットワーク・セキュリティグループ・アクセス元の制限が設計書どおりか（5. のチェックリスト）。出力の名前やスクリプトの使い方が手順書（`docs/aws-deployment-guide.md`）と一致しているか |

文書どうしが矛盾しているとき（例：上位文書は「取得する」、下位文書の決定事項は「呼ばない」）は、**決定事項として明記されている方を正** とし、もう一方の文書を直す。文書を直したら版数・最終更新日・変更履歴の 3 つを更新する（CLAUDE.md 5.）。

## 3. バックエンドのチェックリスト（Spring Boot の標準）

- Controller は HTTP の変換だけ。業務処理とトランザクションは Service、SQL は Repository の派生クエリ（`findByListIdOrderByDisplayOrderAsc` など）
- Service はクラスに `@Transactional(readOnly = true)`、書き込みメソッドだけ `@Transactional` で上書き
- 要求・応答は `record`。エンティティを直接返さない。エンティティは setter を公開せず、操作の意味を表すメソッド（`update` / `moveTo` / `assignDisplayOrder`）で変える
- Bean Validation は要求 record に付け、DB の制約（`CHECK` / `NOT NULL`）と二重にかける。正規化（strip、空白 → `null`）は検証の **前** に済ませる
- エラー応答は `ProblemDetail` に統一。`spring.mvc.problemdetails.enabled=true` を前提にする
- `application.properties`：`spring.jpa.hibernate.ddl-auto=none`、`spring.jpa.open-in-view=false`、`server.port` は書かない。`show-sql=true` は開発専用（本番では無効にする）
- Flyway：適用済みの `V*.sql` は編集しない。定義変更は次の連番で追加
- 依存を増やすときは技術スタック文書 3. に行を追加する。「必要になるまで追加しない」（技術スタック 2.）
- テストは `@SpringBootTest` + `MockMvcTester` で API 単位。クラスに `@Transactional` を付けてロールバックさせ、DB にデータを残さない。件数そのものは検証しない
- 標準から外れていても **理由がコメントに書かれていれば** 許容する（例：`GlobalExceptionHandler` の `@Order(HIGHEST_PRECEDENCE)`、Actuator ではなく自作の `HealthController`）。理由が無ければ指摘する

## 4. フロントエンドのチェックリスト（React の標準）

> コンポーネント名・フック名（`CardDetail`、`useBoard` など）はタスク管理アプリのもの。フロントエンド設計書が確定したら、本プロジェクトの名前に書き直す。

- 関数コンポーネント + hooks。`React.FC` や class は使わない。`main.tsx` は `createRoot` + `StrictMode`
- `useEffect` は依存配列を正しく書き（`exhaustive-deps` 0 件）、非同期処理にはクリーンアップ（`cancelled` フラグ）を付ける
- 一覧の `key` は `id`。`CardDetail` は `key={card.id}` で作り直す
- 状態は最小限：一覧（`lists` / `cards`）は `useBoard` だけが持ち、入力の下書きは入力側のコンポーネント（`AddCardForm` / `CardDetail`）が持つ。状態管理ライブラリは入れない
- API 呼び出しは `src/api/` の薄い関数（`getCards` / `createCard` …）経由。コンポーネントやフックから `fetch` を直接呼ばない。エラーは `ApiError` 1 種類
- `src/types/board.ts` は API 設計書 4. と 1 対 1。項目名・型・`null` 可否を変えない
- a11y：失敗文言は `role="alert"`、`<label htmlFor>` + `id`（文言をラベルの中に入れない）、モーダルは `role="dialog"` + `aria-modal` + `aria-labelledby`、ボタンは `<button type="button">`
- スタイルは CSS Modules。グローバルは `index.css`（`*` と `body`）だけ。色や寸法は画面モック（`mock/style.css`）と設計書 8. に合わせる
- テストは Testing Library の役割・名前（`getByRole`、`findByText`）で要素を取り、クラス名や内部状態を見ない。`fetch` は `vi.stubGlobal` で差し替える
- 設定：`.oxlintrc.json` は `react/rules-of-hooks` と `react/exhaustive-deps` を `error`、`npm run lint` は `--deny-warnings`。Vitest の `passWithNoTests` は付けない

## 5. インフラ（Terraform・スクリプト）のチェックリスト

`infra/` を変えたとき、またはレビューを頼まれたときに確認する。根拠は [docs/infra-design.md](../../../docs/infra-design.md)（以下「設計書」）。

**規模と費用（要件定義書 7.「費用」、設計書 2.1）**
- リソースの規模が設計書 2.1 の上限内か。`db_instance_class` は `validation` で micro だけに制限、ECS の CPU・メモリは変数にせず `locals` で固定している。上限を変える変更は、要件定義書の改訂から行う
- 有料の機能（RDS の Performance Insights の長期保持・拡張モニタリング、ECS の Container Insights、NAT Gateway、AWS WAF、Secrets Manager）を足していないか。足すなら費用の見積もり（設計書 11.）も更新する

**秘密情報と Git**
- パスワード・アクセスキーをコードに書いていない。DB パスワードは `random_password` → SSM パラメータストア → タスク定義の `secrets`（設計書 9.1）
- `infra/.gitignore` で `.terraform/`・`*.tfstate*`・`*.tfvars`（`.example` は除く）・`tfplan*` を除外している。plan ファイルには秘密の値がそのまま入るため、絶対にコミットしない。`git status` にこれらが出ていないか
- `.terraform.lock.hcl` はコミットする（プロバイダーの版を固定するため）

**書き方の標準**
- `required_version` とプロバイダーの `version = "~> X.Y"` で版を固定している
- 共通のタグは `provider` の `default_tags` で付け、リソースごとに書かない。リソース名は `var.project` から作る
- 入力の検査は `variable` の `validation`、作る前の条件（空のイメージタグ、空の許可リストなど）は `lifecycle.precondition` で書く。エラー文は日本語で、何をすればよいかまで書く
- データを持つリソース（RDS）が作り直し（`-/+`）にならない。作るときだけ使う値は `ignore_changes` に入れる
- `force_delete` / `force_destroy` は、休止（`terraform destroy`）で消すことを前提にしたリソースだけに付ける
- `-target` を普段の手順に使わない（ECR を先に作る初回・再開だけ）
- 各 `.tf` ファイルの先頭に、役割と設計書の章番号のコメントがある

**セキュリティ（要件定義書 7.「データ保護」「アクセス制御」、設計書 5.3・6.）**
- セキュリティグループの受信は送信元を絞っている（`0.0.0.0/0` からの受信を作らない。ALB は CloudFront のプレフィックスリスト、ECS は ALB の SG、RDS は ECS の SG から）
- `publicly_accessible = false`（RDS）、`internal = true`（ALB）、S3 はパブリックアクセスをすべて禁止し OAC で CloudFront からだけ読める
- アクセス元の制限（CloudFront Functions、設計書 6.5）が、既定と `/api/*` の**両方**のビヘイビアに付いている。許可リストに IPv4 や広い範囲を入れていない。`is_ipv6_enabled = true`
- IAM のポリシーは対象を絞っている（タスク実行ロールが読めるのは DB パスワードのパラメータ 1 つだけ。`"Resource": "*"` を足していない）

**文書・スクリプトとの一致**
- 出力の名前（`outputs.tf`）・リソースの名前と、手順書のコマンド・`infra/scripts/` の使い方が一致しているか（例：`terraform output -raw app_url`、`/ecs/inquirymanagement-backend`、DB の識別子 `inquirymanagement`）
- スクリプトは Git Bash で動く bash か。AWS の実物を変える前に `confirm` を通り、保存した計画を `assert_no_unexpected_destroy` で検査しているか（設計書 12.3）
- `/` で始まる引数（CloudFront のパス、ロググループ名）に `MSYS_NO_PATHCONV=1` を付けているか（手順書 1.2）

**適用**
- レビューで行うのは `plan` まで。`apply` / `destroy` はレビューの中では行わない。適用は PR をマージした後の main で、スキル `deploy-aws` の手順に従う

## 6. 横断のチェック

- **改行コード**：ルートの `.gitattributes`（`* text=auto eol=lf`）と `.editorconfig` により LF。`git ls-files --eol | grep 'w/crlf'` が `*.bat` 以外を返したら、`sed -i 's/\r$//'` で直すか作業ツリーを取り直す
- README のコマンドは Git Bash 構文（`./gradlew`、スラッシュ区切り）。PowerShell 構文が残っていたら直す（CLAUDE.md 3.）
- 文書を変えたら版数・最終更新日・変更履歴（CLAUDE.md 5.）。依存や設定を足したら技術スタック文書と README も更新
- 新しい npm スクリプトや Gradle タスクを足したら、`frontend/README.md` / `backend/README.md` / ルート `README.md` の表に追記

## 7. 報告の形式

結果は次の 3 区分に分けて報告する。各項目に根拠（文書の章番号、または標準の名前）を添える。

1. **文書と実装の食い違い**（文書を正として直すもの）
2. **標準からのずれ**（直すもの／直さないもの。**直さない判断にも理由を書く**）
3. **確認して問題なしと判断したもの**（何を見て問題なしとしたかを 1 行で）

修正は CLAUDE.md 2. の開発フロー（Issue → ブランチ → PR）に従い、PR のマージはユーザーの承認を得てから行う。レビューの結果がどうであれ、GitHub のリポジトリそのものは削除しない（スキル `deploy-aws` の 0.）。
