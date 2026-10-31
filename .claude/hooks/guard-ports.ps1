# サーバーを既定のポートで起動させる PreToolUse フック
#
# Claude Code がシェルコマンドを実行する直前に呼ばれ、標準入力から受け取った
# JSON の tool_input.command を検査する。バックエンド・フロントエンドのサーバーを
# 既定以外のポートで起動しようとするコマンドは、終了コード 2 を返して実行を中止させる。
#
# 既定のポート:
#   バックエンド（Spring Boot） 8080
#   フロントエンド（Vite）      5173
#
# ポートが使用中のときは、別のポートへ逃げるのではなく、占有しているプロセスを
# 停止してから既定のポートで起動する。手順は .claude/skills/start-dev-servers/SKILL.md
# と CLAUDE.md「6. サーバー起動時のポート」を参照。

$ErrorActionPreference = 'Stop'

$BackendPort  = 8080
$FrontendPort = 5173

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
  バックエンド（Spring Boot） 8080
  フロントエンド（Vite）      5173

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

    # フロントエンド: vite / npm run dev / npm start に --port <n> または --port=<n>
    $isFrontend = ($text -match '(^|[\s/\\])vite(\.js)?(\s|$)') -or
                  ($text -match '\bnpm\s+(run\s+dev|start)\b') -or
                  ($text -match '\bnpx\s+vite\b')
    if ($isFrontend -and $text -match '--port(?:=|\s+)(\d+)') {
        $requested = [int]$Matches[1]
        if ($requested -ne $FrontendPort) {
            Deny 'フロントエンド（Vite）' $FrontendPort $requested $text
        }
    }

    # バックエンド: gradlew bootRun / java -jar / spring-boot:run に
    # server.port=<n>、-Dserver.port=<n>、SERVER_PORT=<n>
    $isBackend = ($text -match '\bbootRun\b') -or
                 ($text -match '\bspring-boot:run\b') -or
                 ($text -match '\bjava(\.exe)?\b.*\.jar\b')
    if ($isBackend) {
        $requested = $null
        if ($text -match 'server\.port(?:=|\s+)(\d+)') { $requested = [int]$Matches[1] }
        elseif ($text -match '\bSERVER_PORT=(\d+)') { $requested = [int]$Matches[1] }
        if ($null -ne $requested -and $requested -ne $BackendPort) {
            Deny 'バックエンド（Spring Boot）' $BackendPort $requested $text
        }
    }
}

Approve
