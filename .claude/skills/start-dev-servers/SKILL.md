---
name: start-dev-servers
description: このプロジェクトの DB・バックエンド・フロントエンドを起動する手順。サーバーを起動・再起動するとき、ポートが使用中のとき、動作確認のために開発サーバーを立てるときに必ず使う。ポートは既定（8080 / 5173）に固定し、別ポートでの起動は行わない。
---

# 開発サーバーの起動手順

このリポジトリのサーバーは **必ず既定のポート** で起動する。ポートが使用中でも別のポートへ逃げてはならない（CLAUDE.md「6. サーバー起動時のポート」）。

| サーバー | 起動コマンド（実行ディレクトリ） | ポート | ポートの根拠 |
| --- | --- | --- | --- |
| PostgreSQL | `docker compose up -d`（リポジトリルート） | 5432 | `compose.yaml` |
| バックエンド | `./gradlew bootRun`（`backend/`） | 8080 | Spring Boot の既定。`application.properties` に `server.port` は書かない |
| フロントエンド | `npm run dev`（`frontend/`） | 5173 | `vite.config.ts` の `server.port: 5173, strictPort: true` |

起動順は DB → バックエンド → フロントエンド。

## 手順

### 1. ポートの使用状況を確認する

起動する前に、そのポートを誰かが使っていないか調べる（PowerShell）。

```powershell
Get-NetTCPConnection -LocalPort 8080,5173 -State Listen -ErrorAction SilentlyContinue |
  Select-Object LocalPort, OwningProcess
```

何も表示されなければ空いているので、3. へ進む。

### 2. 使用中なら、占有しているプロセスを停止する

PID から何が動いているかを確認する。

```powershell
Get-CimInstance Win32_Process -Filter "ProcessId=<PID>" |
  Select-Object ProcessId, ParentProcessId, CreationDate, CommandLine
```

| 占有しているもの | 対応 |
| --- | --- |
| このアプリ自身の古いサーバー（`vite.js`、`npm run dev`、`gradlew bootRun`、`BackendApplication` を含む java など） | 確認なしに停止してよい。`npm run dev` は親の npm プロセスも一緒に止める |
| それ以外のプロセス | 何が動いているかをユーザーに伝え、止めてよいか確認してから停止する |

```powershell
Stop-Process -Id <PID> -Force -Confirm:$false
```

停止後、1. をもう一度実行してポートが空いたことを確認する。

ユーザーが自分のターミナルで起動しているサーバーを止めた場合は、**止めたことと、起動し直す必要があることを必ず伝える**（ユーザーのターミナルには何も表示されないため）。

### 3. 既定のポートで起動する

```bash
# Git Bash
docker compose up -d                 # リポジトリルート
cd backend && ./gradlew bootRun      # 8080
cd frontend && npm run dev           # 5173
```

Claude がバックグラウンドで起動する場合も、ポートの指定は付けない。

### 4. 起動を確認する

| URL | 期待する応答 |
| --- | --- |
| http://localhost:8080/api/health | `{"status":"ok"}` |
| http://localhost:5173/api/health | `{"status":"ok"}`（Vite のプロキシがバックエンドへ転送できている） |
| http://localhost:5173 | ボード画面 |

`http://localhost:5173/api/health` が JSON ではなく画面の HTML を返す場合、その開発サーバーはプロキシ設定を読み込んでいない。2. の手順で停止して起動し直す。

## やってはいけないこと

- `npx vite --port 5174` や `npm run dev -- --port 5175` のように、別のポートを指定して起動する
- `./gradlew bootRun --args='--server.port=8081'`、`SERVER_PORT=8081` のように、バックエンドのポートを変える
- 「ポートが使用中」の表示を見て、そのまま別のポートで動作確認を続ける

これらのコマンドは `.claude/hooks/guard-ports.ps1` が実行前に拒否する。

## 理由

フロントエンドのプロキシ（`/api` → 8080）、README の URL、ユーザーがブラウザで開いているページは、すべて既定のポートを前提にしている。別のポートで起動すると、ユーザーが見ているサーバーと Claude が確認したサーバーが別物になり、「Claude の環境では動くのにユーザーの画面では動かない」食い違いが生じる。

## Claude が自分で立てたサーバーの後始末

動作確認のために Claude がバックグラウンドで起動したサーバーは、確認が終わったら停止し、ユーザーのサーバーだけが残っている状態に戻す。停止したこと・残しているものを報告する。
