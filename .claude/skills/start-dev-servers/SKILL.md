---
name: start-dev-servers
description: このプロジェクトの DB・バックエンド・フロントエンドを起動する手順。サーバーを起動・再起動するとき、ポートが使用中のとき、動作確認のために開発サーバーを立てるときに必ず使う。ポートは既定（Next.js 3000 / Rails 3001 / MySQL 3306）に固定し、別ポートでの起動は行わない。
---

# 開発サーバーの起動手順

このリポジトリのサーバーは **必ず既定のポート** で起動する。ポートが使用中でも別のポートへ逃げてはならない（CLAUDE.md「6. サーバー起動時のポート」）。

| サーバー | 起動コマンド（実行ディレクトリ） | ポート | ポートの根拠 |
| --- | --- | --- | --- |
| MySQL | `docker compose up -d`（リポジトリルート） | 3306 | `compose.yaml` |
| バックエンド（Rails） | `docker compose up -d`（リポジトリルート。MySQL と一緒に起動する） | 3001 | `compose.yaml`（Rails の既定 3000 は Next.js と重なるため。技術スタック 6.1） |
| フロントエンド（Next.js） | `npm run dev`（`frontend/`） | 3000 | Next.js の既定 |

起動順は MySQL・Rails（Docker Compose）→ Next.js。Ruby は PC に入れないため、Rails は必ずコンテナで動かす（技術スタック 6.）。

## 手順

### 1. Docker Desktop が動いているか確認する

```bash
docker info > /dev/null 2>&1 && echo "Docker は起動しています" || echo "Docker Desktop を起動してください"
```

止まっていたら、ユーザーに Docker Desktop の起動を頼む（Claude からは起動しない）。

### 2. ポートの使用状況を確認する

起動する前に、そのポートを誰かが使っていないか調べる（PowerShell）。

```powershell
Get-NetTCPConnection -LocalPort 3000,3001,3306 -State Listen -ErrorAction SilentlyContinue |
  Select-Object LocalPort, OwningProcess
```

```bash
docker compose ps   # このリポジトリのコンテナが動いているか
```

何も表示されなければ空いているので、4. へ進む。

### 3. 使用中なら、占有しているものを停止する

PID から何が動いているかを確認する。

```powershell
Get-CimInstance Win32_Process -Filter "ProcessId=<PID>" |
  Select-Object ProcessId, ParentProcessId, CreationDate, CommandLine
```

3001・3306 の持ち主が `com.docker.backend` などの Docker のプロセスなら、どのコンテナかを `docker ps --format "table {{.Names}}\t{{.Ports}}"` で確かめる。

| 占有しているもの | 対応 |
| --- | --- |
| このアプリ自身の古いサーバー（`next dev`・`npm run dev` を含む node、このリポジトリの Docker Compose のコンテナ） | 確認なしに停止してよい。`npm run dev` は親の npm プロセスも一緒に止める。コンテナは `docker compose stop` で止める |
| それ以外のプロセス・別のプロジェクトのコンテナ（例：ほかのアプリの MySQL） | 何が動いているかをユーザーに伝え、止めてよいか確認してから停止する |

```powershell
Stop-Process -Id <PID> -Force -Confirm:$false
```

停止後、2. をもう一度実行してポートが空いたことを確認する。

ユーザーが自分のターミナルで起動しているサーバーを止めた場合は、**止めたことと、起動し直す必要があることを必ず伝える**（ユーザーのターミナルには何も表示されないため）。

### 4. 既定のポートで起動する

```bash
# Git Bash
docker compose up -d                 # リポジトリルート。MySQL（3306）と Rails（3001）
cd frontend && npm run dev           # 3000
```

Claude がバックグラウンドで起動する場合も、ポートの指定は付けない。Rails のポートは `compose.yaml` に書かれており、コマンドで変えない。

Next.js の開発サーバーは、3000 が使用中だと `Port 3000 is in use, trying 3001 instead.` のように **自動で別のポートへ移る**。移った先が Rails の 3001 と重なることもある。起動時の表示に出る URL が `http://localhost:3000` でなければ、すぐに停止し、2.・3. で 3000 を空けてから起動し直す。

### 5. 起動を確認する

| URL | 期待する応答 |
| --- | --- |
| http://localhost:3001/up | 200（Rails 標準の死活確認。緑の画面） |
| http://localhost:3000 | ボード画面 |

Rails が起動しないときは `docker compose logs backend` で原因を見る。DB の準備ができていない（マイグレーション前）なら `docker compose exec -T backend bin/rails db:prepare` を実行する。Claude が実行するときは `-T` を必ず付ける（端末が無いため、付けないと止まる。CLAUDE.md 3.）。

## やってはいけないこと

- `npm run dev -- --port 3002`、`npx next dev -p 3002`、`PORT=3002 npm run dev` のように、フロントエンドを別のポートで起動する
- `bin/rails server -p 3002`、`PORT=3000 bin/rails s` のように、バックエンドのポートを変える
- `compose.yaml` のポートの割り当てを、一時的な回避のために書き換える
- 「ポートが使用中」の表示を見て、そのまま別のポートで動作確認を続ける
- PC に Ruby を入れて、コンテナの外で Rails を動かす

コマンドでのポートの変更は `.claude/hooks/guard-ports.ps1` が実行前に拒否する。

## 理由

Rails が CORS で許可する送信元（http://localhost:3000）、フロントエンドが呼ぶ API の URL（http://localhost:3001）、README の URL、ユーザーがブラウザで開いているページは、すべて既定のポートを前提にしている。別のポートで起動すると、ユーザーが見ているサーバーと Claude が確認したサーバーが別物になり、「Claude の環境では動くのにユーザーの画面では動かない」食い違いが生じる。

## Claude が自分で立てたサーバーの後始末

動作確認のために Claude がバックグラウンドで起動したサーバー（`npm run dev`）は、確認が終わったら停止し、ユーザーのサーバーだけが残っている状態に戻す。Docker Compose のコンテナを Claude が起動した場合は、ユーザーに残すか確認する。停止したこと・残しているものを報告する。
