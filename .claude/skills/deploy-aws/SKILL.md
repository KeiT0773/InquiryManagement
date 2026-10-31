---
name: deploy-aws
description: このアプリを AWS に構築・更新・休止・再開するときの手順と約束。「デプロイして」「AWS に上げて」「再開して」「休止して」「止めて」「バックエンド（画面）を更新して」「terraform を実行して」「AWS の状態を確認して」と頼まれたとき、および infra/ の Terraform やスクリプトを実行するときに必ず使う。AWS の実物を変える操作は、内容を示して利用者の承認を得てから行う。
---

# AWS へのデプロイ手順（Claude 用）

本番の構成は CloudFront + EC2 + RDS for MySQL（技術スタック 9.）。構成の詳細は [docs/infra-design.md](../../../docs/infra-design.md)、人向けの手順と解説は [docs/aws-deployment-guide.md](../../../docs/aws-deployment-guide.md)（以下「手順書」）にある。コマンドはすべて Git Bash で、リポジトリのルートから実行する。

## 0. 必ず守ること

| 約束 | 理由 |
| --- | --- |
| 作業の最初に `aws sts get-caller-identity` を実行し、アカウント（`512795167785`）と IAM ユーザーを報告する | 意図しないアカウントを操作しないため |
| AWS の実物を変える操作（`terraform apply` / `destroy`、`infra/scripts/` のスクリプト、`aws ... create-*` / `delete-*` / `run-instances` / `terminate-instances`）は、**何が起きるかを示して利用者が承認してから**実行する。特に撤去（destroy・delete・terminate）は、3. の手順で毎回確認する | 取り消せない操作や、課金が始まる操作であるため |
| **GitHub のリポジトリを削除しない**（`KeiT0773/InquiryManagement`、`KeiT0773/TASKMANAGEMENT` を含む）。`gh repo delete`、`gh api` での `DELETE`、アーカイブ・名前の変更・公開範囲の変更も行わない。頼まれた場合も実行せず、本人がブラウザの GitHub の設定画面で行うよう伝える | 文書・コード・PR の履歴がすべて失われ、戻せないため。`.claude/settings.json` の `deny` でも止めている |
| スクリプトの `--yes`（確認を省く指定）は、同じ内容を一度 `--yes` なしで実行して計画を示し、利用者が承認したあとにだけ付ける | `--yes` は確認を省略するため |
| `~/.aws/credentials` を読まない。アクセスキーを会話に出さない | キーの漏えいを防ぐ |
| EC2 に入るための鍵（SSH の秘密鍵など）を会話に出さない・コミットしない | 鍵の漏えいはサーバーの乗っ取りにつながる |
| `rm` は使えない（`.claude/settings.json` で禁止）。一時ファイルは作業用フォルダーに置く | — |
| 作業の最後に「稼働中か休止中か」を報告する。稼働中なら、1 時間あたりの費用（インフラ設計書の見積もり）がかかり続けていることと、休止の方法を伝える | 休止し忘れによる課金を防ぐ |
| 構成を変えるときは、Issue → ブランチ → PR で `infra/terraform/` を直し、**マージ後の main で** apply する | ブランチのコードで apply すると、AWS の実物が main より先に進んでしまう |
| リソースの規模を、インフラ設計書 2.1 の上限（`t3.micro`・`db.t4g.micro` など、無料利用枠と同じ規模）より大きくしない | 要件定義書 7.「費用」 |
| アクセス元の制限（CloudFront Functions）を外したり、IPv4 や自宅以外のネットワークを許可リストに加えたりしない。EC2・RDS をインターネットから直接呼べるようにしない（EC2 のセキュリティグループは CloudFront のプレフィックスリストからの 80 番だけ。SSH の 22 番は開けない。インフラ設計書 5.3・6.2） | 要件定義書 7.「アクセス制御」「データ保護」 |
| 金額をこのファイルに書くときは「0.07 ドル」のように書き、ドル記号と数字を続けない | スキルの読み込み時に、ドル記号と数字の組が引数に置き換わってしまうため |

## 1. いまの状態を調べる（読み取りだけ。承認は不要）

```bash
aws sts get-caller-identity                               # 最初に必ず（0.）
terraform -chdir=infra/terraform state list               # 何も出なければ休止中。未初期化なら下の init
terraform -chdir=infra/terraform output -raw app_url      # 稼働中の URL
aws rds describe-db-instances --db-instance-identifier inquirymanagement --query 'DBInstances[0].DBInstanceStatus' --output text
aws ec2 describe-instances --filters Name=tag:Project,Values=inquirymanagement Name=instance-state-name,Values=pending,running --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text
aws rds describe-db-snapshots --snapshot-type manual --query "DBSnapshots[?starts_with(DBSnapshotIdentifier, 'inquirymanagement-')].[DBSnapshotIdentifier,SnapshotCreateTime]" --output table
```

Terraform が未初期化（`.terraform/terraform.tfstate` が無い）のときは、次で state の保存先に接続する（読み取りだけで、AWS の実物は変えない）。

```bash
terraform -chdir=infra/terraform init -reconfigure -backend-config="bucket=inquirymanagement-tfstate-$(aws sts get-caller-identity --query Account --output text)"
```

## 2. 操作ごとの流れ

どの操作も **「1 回目は `--yes` なしで実行 → 出力（計画の集計や対象）を利用者に要約して示す → 承認後に `--yes` を付けて実行」** の 2 段階にする。Claude のシェルには端末が無いため、`--yes` なしのスクリプトは確認の手前で「確認の入力ができないため、ここで止めました」と表示して止まる。これが 1 回目の結果で、ここまでに AWS の実物は変わっていない（ただし `terraform.tfvars` の値は書き換わる）。

| 利用者の依頼 | スクリプト | 1 回目で示すこと | 実行の前提 |
| --- | --- | --- | --- |
| 「構築して」「再開して」 | `bash infra/scripts/startup.sh` | 作る件数（`Plan: N to add`）、復元するスナップショット（無ければ DB を新規作成）、許可するネットワーク番号、費用（約 0.05 ドル / 時間）、20〜30 分かかること | main を最新にし、`backend/`・`frontend/` に未コミットの変更が無い。Docker Desktop が起動している。state 用バケットがある（無ければ手順書 5.。作成は AWS の実物を変えるので承認を得る） |
| 「バックエンドを更新して」 | `bash infra/scripts/deploy-backend.sh` | 計画が `aws_ssm_parameter.image_tag["backend-image-tag"]` の更新だけであること、新しいタグ | 稼働中。PR をマージしたあとの main |
| 「画面を更新して」 | `bash infra/scripts/deploy-frontend.sh` | 計画が `aws_ssm_parameter.image_tag["web-image-tag"]` の更新だけであること、新しいタグ | 同上 |
| 「自宅のネットワーク番号が変わった」「403 になる」 | `bash infra/scripts/update-allowed-ip.sh` | 新しいネットワーク番号と、計画が `aws_cloudfront_function.viewer_allowlist` の更新だけであること | 稼働中 |
| 「休止して」「止めて」 | `bash infra/scripts/shutdown.sh` | **3. の手順で**、撤去する件数、スナップショットを取ること、URL が変わること | — |
| 構成の変更（`infra/terraform/` を直した） | `terraform -chdir=infra/terraform plan` → `apply` | 計画の全体。特に `-/+`・`-` の行 | PR をマージしたあとの main（0.） |

- 1 回目の出力に **イメージの作成（ECR への登録）** が含まれることがある（`deploy-*.sh` は確認の前にイメージを登録する）。ECR への登録は課金にも構成にもほぼ影響しないが、利用者への要約に含める。
- スクリプトが「想定外の削除・作り直し」「DB（RDS）の削除・作り直し」で止めたら、押し切らずに計画の該当行を利用者に示して相談する。EC2（`aws_instance.app`）の作り直しは `user_data` を変えたときの正常な動き（インフラ設計書 7.2）で、スクリプトが確認を求める。
- 実行が途中で失敗したら、表示された手順書の節（9.1〜9.6）の手順で原因を調べ、利用者に報告してから次の操作をする。

## 3. destroy（撤去）の前に必ず行うこと

撤去は取り消せない。DB のデータ、EC2 の中の設定やファイルは消えると戻らない。次の操作は、**その会話の中で利用者が内容を見て明示的に承認したあとにだけ**実行する。

| 対象の操作 |
| --- |
| `terraform destroy`、`terraform apply` に `-destroy` で作った計画を渡すもの、`terraform state rm` |
| `bash infra/scripts/shutdown.sh`（中で `terraform destroy` と `aws rds delete-db-snapshot`（古いスナップショット）を行う） |
| `aws ... delete-*`、`aws ec2 terminate-instances`、`aws s3 rm`、`aws s3 rb`（スナップショット・インスタンス・バケットなどの削除） |

**手順**

1. **消えるものを示す。** `terraform plan -destroy`（または確認用の実行）で、件数と主なリソースを要約する。RDS・スナップショット・EC2 が含まれるかを必ず書く
2. **結果を伝える。** 取り消せないこと、データがどうなるか（スナップショットを取るか、取らずに消えるか）、費用がどう変わるか、URL が変わること
3. **承認を得る。** 利用者の返事で「消してよい」と明示されたことを確かめてから実行する。返事があいまいなら、もう一度確かめる
4. **結果を確かめる。** `terraform state list` が空か、残ったもの（スナップショット・state 用バケットなど）を報告する

**禁止すること**

- 前の承認を使い回さない。以前「休止して」と言われていても、撤去のたびに 1.〜3. を行う。計画で示した内容と違うものを消すことになったら、改めて承認を得る
- `-auto-approve` を destroy に付けない（`.claude/settings.json` の `deny` でも止めている）
- スクリプトが「想定外の削除・作り直し」で止めたときに、手でコマンドを打って押し切らない

**利用者が手動（コンソール）で削除したとき**

Terraform の外で消すと、state（台帳）には「まだある」と記録が残り、実物と食い違う。その場合は、`terraform plan` で食い違いを確かめることと、state を整理するか（`terraform state rm` など）を利用者に伝え、確認を取ってから行う。

## 4. 確認（稼働中）

スクリプトは最後に自動で確認する（画面・`/api/lists` が IPv6 で 200、IPv4 からは 403）。手で確かめるときは次のとおり。

```bash
URL="$(terraform -chdir=infra/terraform output -raw app_url)"
curl -6 -s -o /dev/null -w '%{http_code}
' "$URL/"          # 200
curl -6 -s "$URL/api/lists"                                   # 3 つのリストの JSON
curl -4 -s -o /dev/null -w '%{http_code}
' "$URL/"          # 403（IPv4 は拒否）
MSYS_NO_PATHCONV=1 aws logs tail /inquirymanagement/backend --since 30m   # Rails のログ
MSYS_NO_PATHCONV=1 aws logs tail /inquirymanagement/web --since 30m       # nginx のログ
```

EC2 の中を調べるときは SSM Session Manager を使う（手順書 9.1）。Claude からは、対話のシェルを開く代わりに Run Command で読み取りのコマンドだけを送る。

```bash
MSYS_NO_PATHCONV=1 aws ssm send-command --instance-ids "$(terraform -chdir=infra/terraform output -raw instance_id)"   --document-name AWS-RunShellScript --parameters 'commands=["cd /opt/inquirymanagement && docker compose ps"]'   --query Command.CommandId --output text
aws ssm get-command-invocation --command-id <上の ID> --instance-id <インスタンス ID> --query StandardOutputContent --output text
```

`.env` は秘密の値を含むため、中身を表示するコマンドを送らない。

## 5. 作業の終わりに報告すること

- 稼働中か休止中か（`terraform state list` が空かどうか）
- 稼働中なら URL と、1 時間あたり約 0.05 ドルかかっていること、休止は `bash infra/scripts/shutdown.sh`
- 残っているスナップショットの一覧
- 手順書と実際の動きが違った点があれば、その内容（手順書を直す Issue を提案する）
