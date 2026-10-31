---
name: deploy-aws
description: このアプリを AWS に構築・更新・休止・再開するときの手順と約束。「デプロイして」「AWS に上げて」「再開して」「休止して」「止めて」「バックエンド（画面）を更新して」「terraform を実行して」「AWS の状態を確認して」と頼まれたとき、および infra/ の Terraform やスクリプトを実行するときに必ず使う。AWS の実物を変える操作は、内容を示して利用者の承認を得てから行う。
---

# AWS へのデプロイ手順（Claude 用）

構成は [docs/infra-design.md](../../../docs/infra-design.md)、人向けの手順と解説は [docs/aws-deployment-guide.md](../../../docs/aws-deployment-guide.md) にある。コマンドはすべて Git Bash で、リポジトリのルートから実行する。

## 0. 必ず守ること

| 約束 | 理由 |
| --- | --- |
| 作業の最初に `aws sts get-caller-identity` を実行し、アカウント（`512795167785`）と IAM ユーザーを報告する | 意図しないアカウントを操作しないため |
| AWS の実物を変える操作（`terraform apply` / `destroy`、`startup.sh`、`shutdown.sh`、`deploy-backend.sh`、`aws ... create-*` / `delete-*`）は、**何が起きるかを示して利用者が承認してから**実行する。特に撤去（destroy・delete）は、3. の手順で毎回確認する | 取り消せない操作や、課金が始まる操作であるため |
| **GitHub のリポジトリを削除しない**（`KeiT0773/InquiryManagement`、`KeiT0773/TASKMANAGEMENT` を含む）。`gh repo delete`、`gh api` での `DELETE`、アーカイブ・名前の変更・公開範囲の変更も行わない。頼まれた場合も実行せず、本人がブラウザの GitHub の設定画面で行うよう伝える | 文書・コード・PR の履歴がすべて失われ、戻せないため。`.claude/settings.json` の `deny` でも止めている |
| スクリプトの `--yes` は、同じ内容を一度 `--yes` なしで実行して計画を示し、利用者が承認したあとにだけ付ける | `--yes` は確認を省略するため |
| `~/.aws/credentials` を読まない。アクセスキーを会話に出さない | キーの漏えいを防ぐ（手順書 4.4） |
| `rm` は使えない（`.claude/settings.json` で禁止）。一時ファイルは作業用フォルダーに置く | — |
| 作業の最後に「稼働中か休止中か」を報告する。稼働中なら、約 0.07 ドル / 時間かかり続けていることと、`shutdown.sh` で休止できることを伝える | 休止し忘れによる課金を防ぐ |
| 構成を変えるときは、Issue → ブランチ → PR で `infra/terraform/` を直し、**マージ後の main で** apply する | ブランチのコードで apply すると、AWS の実物が main より先に進んでしまう（手順書 6.4） |
| リソースの規模を設計書 2.1 の上限より大きくしない | 要件定義書 7.「費用」 |
| アクセス元の制限（CloudFront Functions）を外したり、IPv4 や自宅以外のネットワークを許可リストに加えたりしない。許可リストはスクリプトが自動で取得する | 要件定義書 7.「アクセス制御」（自宅のネットワークからだけ。設計書 6.5） |
| 金額をこのファイルに書くときは「0.07 ドル」のように書き、ドル記号と数字を続けない | スキルの読み込み時に、ドル記号と数字の組が引数に置き換わってしまうため |

## 1. いまの状態を調べる（読み取りだけ。承認は不要）

```bash
aws sts get-caller-identity
terraform -chdir=infra/terraform state list                      # 空なら休止中
aws rds describe-db-instances --db-instance-identifier inquirymanagement --query 'DBInstances[0].DBInstanceStatus' --output text
aws rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].[DBSnapshotIdentifier,SnapshotCreateTime]' --output table
terraform -chdir=infra/terraform output app_url                   # 稼働中なら URL
```

`terraform` が「Backend initialization required」と言うときは、`terraform -chdir=infra/terraform init -backend-config="bucket=inquirymanagement-tfstate-512795167785"` を実行する（state を読むだけの準備で、AWS には何も作らない）。

## 2. 操作ごとの流れ

どの操作も **「1 回目は `--yes` なしで実行 → 出力（計画の集計や対象）を利用者に要約して示す → 承認後に `--yes` 付きで実行」** の 2 段階にする。スクリプトは、端末から入力できないときは確認の手前で止まるので、1 回目は安全に実行できる。

| 頼まれたこと | 1 回目（確認用） | 承認後 | 所要時間 |
| --- | --- | --- | --- |
| 再開・初回の構築 | `bash infra/scripts/startup.sh` | `bash infra/scripts/startup.sh --yes` | 20〜30 分 |
| 休止 | `bash infra/scripts/shutdown.sh` | `bash infra/scripts/shutdown.sh --yes` | 15〜25 分 |
| バックエンドの更新 | `bash infra/scripts/deploy-backend.sh` | `bash infra/scripts/deploy-backend.sh --yes` | 5〜10 分 |
| 画面の更新 | — | `bash infra/scripts/deploy-frontend.sh`（構成を変えないため確認なし。ただし実行することは事前に伝える） | 2〜3 分 |
| 自宅のネットワーク番号が変わった（画面が 403 になる） | `bash infra/scripts/update-allowed-ip.sh` | `bash infra/scripts/update-allowed-ip.sh --yes` | 2〜5 分 |

時間がかかるコマンドは、`run_in_background` で実行して完了を待つ。

### 利用者に示す内容

- **startup**：復元するスナップショットの名前（無ければ「DB は空から始まる」）、アクセスを許可するネットワーク（`xxxx:xxxx:xxxx:xxxx::/64`）、`Plan: N to add, 0 to change, 0 to destroy`、課金が始まること（約 0.07 ドル / 時間）
- **shutdown**：撤去する件数、スナップショットを取ってから消すこと、登録した問い合わせは次の再開で戻ること、再開後は URL が変わること
- **deploy-backend**：イメージのタグ（コミット）、`Plan:` の集計。タスク定義が作り直し（`-/+`）になるのは正常

### スクリプトが止めたとき

- 「想定外の削除・作り直しが含まれています」：**`--yes` を付けて押し切らない。** 表示されたリソースと原因を利用者に伝える。RDS（`aws_db_instance.main`）の作り直しはデータの消失につながる
- 「backend/ にコミットしていない変更があります」：コミットしてから実行し直す（イメージのタグとコードを一致させるため）
- 「Docker が起動していません」：利用者に Docker Desktop の起動を頼む
- 「IPv6 で通信できません」：アプリは自宅の IPv6 のネットワークからだけ使える。利用者に IPv6 の接続（ルーター、VPN）を確かめてもらう
- それ以外のエラーは、手順書 9. のトラブルシューティングで原因を調べ、分かったことを報告してから次の操作を相談する

## 3. destroy（撤去）の前に必ず行うこと

撤去は取り消せない。DB のデータ、S3 の画面のファイル、ECR のイメージは消えると戻らない。次の操作は、**その会話の中で利用者が内容を見て明示的に承認したあとにだけ**実行する。

| 対象の操作 |
| --- |
| `terraform destroy`、`terraform apply` に `-destroy` で作った計画を渡すもの、`terraform state rm` |
| `bash infra/scripts/shutdown.sh --yes`（休止。中で `terraform destroy` を行う） |
| `aws ... delete-*`、`aws ... terminate-*`、`aws s3 rm`、`aws s3 rb`（スナップショット・バケット・予算などの削除） |

**手順**

1. **消えるものを示す。** `terraform plan -destroy`（または `--yes` なしの `shutdown.sh`）で、件数と主なリソースを要約する。RDS・スナップショット・S3 の中身が含まれるかを必ず書く
2. **結果を伝える。** 取り消せないこと、データがどうなるか（スナップショットを取るか、取らずに消えるか）、費用がどう変わるか、URL が変わること
3. **承認を得る。** 利用者の返事で「消してよい」と明示されたことを確かめてから実行する。返事があいまいなら、もう一度確かめる
4. **結果を確かめる。** `terraform state list` が空か、残ったもの（スナップショット・state 用バケット・予算）を報告する

**禁止すること**

- 前の承認を使い回さない。以前「休止して」と言われていても、撤去のたびに 1.〜3. を行う。計画で示した内容と違うものを消すことになったら、改めて承認を得る
- `-auto-approve` を destroy に付けない（`.claude/settings.json` の `deny` でも止めている）
- `shutdown.sh --yes` は、同じ内容を `--yes` なしで示して承認を得た直後にだけ使う
- スクリプトが「想定外の削除・作り直し」で止めたときに、手でコマンドを打って押し切らない

**利用者が手動（コンソール）で削除したとき**

Terraform の外で消すと、state（台帳）には「まだある」と記録が残り、実物と食い違う。その場合は、次の 2 点を利用者に伝え、どちらも確認を取ってから行う。
- `terraform plan` で食い違いを確かめる（消えたものは「作成」として表示される）
- state を整理するか（`terraform state rm`、または全部消えたなら state 用バケットの削除。手順書 7.4）

## 4. 確認（稼働中）

```bash
APP_URL=$(terraform -chdir=infra/terraform output -raw app_url)
curl -6 -i "${APP_URL}/api/health/db"  # 200（自宅の IPv6 から）
curl -6 -i "${APP_URL}/api/inquiries"  # 200
curl -4 -i "${APP_URL}/api/health"     # 403（IPv4 は拒否される。設計どおり）
MSYS_NO_PATHCONV=1 aws logs tail /ecs/inquirymanagement-backend --since 30m
```

## 5. 作業の終わりに報告すること

- 稼働中か休止中か（`terraform state list` が空かどうか）
- 稼働中なら URL と、約 0.07 ドル / 時間かかっていること
- 残っているスナップショットの一覧
- 手順書と実際の動きが違った点があれば、その内容（手順書を直す Issue を提案する）
