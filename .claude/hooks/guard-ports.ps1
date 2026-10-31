# サーバーを既定のポートで起動させる PreToolUse フック
#
# Claude Code がシェルコマンドを実行する直前に呼ばれ、標準入力から受け取った
# JSON の tool_input.command を検査する。バックエンド・フロントエンドのサーバーを
# 既定以外のポートで起動しようとするコマンドは、終了コード 2 を返して実行を中止させる。
#
# 既定のポート:
#   フロントエンド（Next.js） 3000
#   バックエンド（Rails）     3001（Rails の既定 3000 は Next.js と重なるため。docs/tech-stack.md 6.1）
#
# ポートが使用中のときは、別のポートへ逃げるのではなく、占有しているプロセスを
# 停止してから既定のポートで起動する。手順は .claude/skills/start-dev-servers/SKILL.md
# と CLAUDE.md「6. サーバー起動時のポート」を参照。

$ErrorActionPreference = 'Stop'

$FrontendPort = 3000
$BackendPort  = 3001

# 標準エラー出力はコンソールの既定コードページで書かれると日本語が文字化けするため、
# UTF-8 のバイト列を直接ストリームへ書き込む。
function Write-Stderr([string]$text) {
    $stream = [Console]::OpenStandardError()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text + "`n")
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

function Approve {
    exit 0
}

function Deny([string]$server, [int]$defaultPort, [string]$requested, [string]$text) {
    Write-Stderr @"
[ポート規則違反] $server を既定以外のポート（$requested）で起動しようとしています。（$text）

このリポジトリでは、サーバーは必ず既定のポートで起動します。
  フロントエンド（Next.js） 3000
  バックエンド（Rails）     3001

ポート $defaultPort が使用中なら、別のポートへ逃げるのではなく、占有している
プロセスを停止してから既定のポートで起動し直してください。

  # 占有しているプロセスを調べる（PowerShell）
  Get-NetTCPConnection -LocalPort $defaultPort -State Listen | Select-Object OwningProcess
  Get-CimInstance Win32_Process -Filter "ProcessId=<PID>" | Select-Object ProcessId, CommandLine

  # このアプリ自身の古いサーバーなら停止する
  Stop-Process -Id <PID> -Force -Confirm:`$false

手順の全文は .claude/skills/start-dev-servers/SKILL.md と CLAUDE.md を参照。
"@
    exit 2
}

# --- 標準入力の JSON を読む -------------------------------------------------

try {
    # Claude Code は JSON を UTF-8 で渡す。既定のコードページで読むと日本語が化けるため明示する
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Approve }
    $payload = $raw | ConvertFrom-Json
} catch {
    # 入力を解釈できないときは判定を諦めて通す（誤ってブロックしないため）
    Approve
}

$command = $null
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
    $command = $payload.tool_input.command
}
if ([string]::IsNullOrWhiteSpace($command)) { Approve }

# --- コマンドを区切り単位に分解して判定する ---------------------------------

$segments = @($command -split '(?:&&|\|\||;|\r?\n|\|)')

foreach ($segment in $segments) {
    $text = $segment.Trim()
    if ($text -eq '') { continue }

    # ポートの指定を取り出す: --port <n> / --port=<n> / -p <n> / -p<n> / 環境変数 PORT=<n>
    $requested = $null
    if ($text -match '(?:^|\s)(?:--port|-p)(?:=|\s*)(\d+)') { $requested = [int]$Matches[1] }
    elseif ($text -match '(?:^|\s)PORT=(\d+)') { $requested = [int]$Matches[1] }
    if ($null -eq $requested) { continue }

    # フロントエンド: next dev / next start / npm run dev / npm start / npx next
    $isFrontend = ($text -match '\bnext\s+(dev|start)\b') -or
                  ($text -match '\bnpm\s+(run\s+dev|start)\b') -or
                  ($text -match '\bnpx\s+next\b')
    if ($isFrontend -and $requested -ne $FrontendPort) {
        Deny 'フロントエンド（Next.js）' $FrontendPort $requested $text
    }

    # バックエンド: rails server / rails s / puma / rackup（docker compose exec 経由を含む）
    $isBackend = ($text -match '\brails\s+(server|s)\b') -or
                 ($text -match '\b(puma|rackup)\b')
    if ($isBackend -and $requested -ne $BackendPort) {
        Deny 'バックエンド（Rails）' $BackendPort $requested $text
    }
}

Approve
