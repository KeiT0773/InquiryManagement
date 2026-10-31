# 開発フローを守らせる PreToolUse フック
#
# Claude Code がシェルコマンドを実行する直前に呼ばれ、標準入力から受け取った
# JSON の tool_input.command を検査する。開発フローに反するコマンドだった場合は
# 終了コード 2 を返してコマンドの実行そのものを中止させる。
#
# 判定内容はリポジトリの docs/development-workflow.md 「8. ローカルのフック」を参照。

$ErrorActionPreference = 'Stop'

$BranchNamePattern = '^(feat|fix|docs|refactor|test|chore)/[0-9]+-[a-z0-9._-]+$'

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

function Deny([string]$reason, [string]$guidance) {
    Write-Stderr "[開発フロー違反] $reason`n`n$guidance`n`n詳細は docs/development-workflow.md および CLAUDE.md を参照。"
    exit 2
}

function Deny-MainBranch([string]$reason) {
    Deny $reason @"
このリポジトリでは main ブランチを直接変更できません。次の手順で進めてください。

  1. Issue を起票する
     gh issue create

  2. main を最新にしてからブランチを切る
     git switch main
     git pull --ff-only
     git switch -c <種別>/<Issue番号>-<要約>

  3. コミットして push する
     git push -u origin <ブランチ名>

  4. PR を作る（本文に Closes #<Issue番号> を書く）
     gh pr create

main への直接 push は GitHub の Ruleset でも拒否されるため、このフックを
回避しても反映はできません。
"@
}

function Deny-BranchName([string]$name) {
    Deny "ブランチ名 '$name' が命名規則に合っていません。" @"
ブランチ名は次の形式にしてください。

  <種別>/<Issue番号>-<英小文字の要約>

  種別: feat / fix / docs / refactor / test / chore
  要約: 英小文字・数字・ハイフンのみ（日本語や大文字は使えません）

  例: feat/12-inquiry-create
      fix/15-due-date-timezone
      chore/4-setup-dev-workflow

対応する Issue がまだ無い場合は、先に gh issue create で起票してください。
"@
}

# --- 標準入力の JSON を読む -------------------------------------------------

try {
    $raw = [Console]::In.ReadToEnd()
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

# --- 現在のブランチを調べる -------------------------------------------------

$repoDir = $payload.cwd
if ([string]::IsNullOrWhiteSpace($repoDir) -or -not (Test-Path $repoDir)) {
    $repoDir = (Get-Location).Path
}

$currentBranch = ''
try {
    $ErrorActionPreference = 'Continue'
    $currentBranch = (& git -C $repoDir rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
    $ErrorActionPreference = 'Stop'
} catch {
    # git リポジトリでない、git が無いなどの場合は通す
    Approve
}
if ([string]::IsNullOrWhiteSpace($currentBranch)) { Approve }

$onMain = ($currentBranch -eq 'main')

# --- コマンドを区切り単位に分解して git のサブコマンドを取り出す ------------

function Get-Tokens([string]$segment) {
    return @($segment.Trim() -split '\s+' | Where-Object { $_ -ne '' })
}

function Get-GitSubcommandIndex($tokens) {
    if ($tokens.Count -eq 0) { return -1 }
    if ($tokens[0] -notmatch '^git(\.exe)?$') { return -1 }

    $i = 1
    while ($i -lt $tokens.Count) {
        $token = $tokens[$i]
        if ($token.StartsWith('-')) {
            # 値を伴うグローバルオプションは次のトークンごと読み飛ばす
            if ($token -eq '-C' -or $token -eq '-c' -or $token -eq '--git-dir' -or $token -eq '--work-tree') {
                $i += 2
            } else {
                $i += 1
            }
            continue
        }
        return $i
    }
    return -1
}

# 新しく作られるブランチ名を取り出す（git switch -c / git checkout -b）
function Get-NewBranchName($tokens, [int]$subIndex) {
    $sub = $tokens[$subIndex]
    $flags = switch ($sub) {
        'switch'   { @('-c', '-C') }
        'checkout' { @('-b', '-B') }
        default    { @() }
    }
    if ($flags.Count -eq 0) { return $null }

    for ($i = $subIndex + 1; $i -lt $tokens.Count - 1; $i++) {
        if ($flags -contains $tokens[$i]) { return $tokens[$i + 1].Trim('"', "'") }
    }
    return $null
}

# push されるブランチ名を取り出す
# 削除の push かどうかを判別し、削除対象のブランチ名を返す（削除でなければ $null）
function Get-DeletedBranchName($tokens, [int]$subIndex) {
    $hasDeleteFlag = $false
    $positional = @()
    for ($i = $subIndex + 1; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        if ($token.StartsWith('-')) {
            if ($token -eq '--delete' -or $token -eq '-d') { $hasDeleteFlag = $true }
            continue
        }
        $positional += $token.Trim('"', "'")
    }

    if ($hasDeleteFlag) {
        if ($positional.Count -ge 2) { return ($positional[1] -replace '^refs/heads/', '') }
        return ''
    }

    # git push origin :branch という書き方も削除を意味する
    foreach ($item in $positional) {
        if ($item.StartsWith(':')) { return ($item.Substring(1) -replace '^refs/heads/', '') }
    }

    return $null
}

function Get-PushedBranchName($tokens, [int]$subIndex, [string]$fallback) {
    $positional = @()
    for ($i = $subIndex + 1; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        if ($token.StartsWith('-')) {
            # 削除やタグの push は命名規則の対象外
            if ($token -eq '--delete' -or $token -eq '-d' -or $token -eq '--tags') { return $null }
            continue
        }
        $positional += $token.Trim('"', "'")
    }

    if ($positional.Count -lt 2) { return $fallback }

    $refspec = $positional[1]
    if ($refspec -match '^refs/tags/') { return $null }
    # git push origin :branch は削除なので命名規則の対象外
    if ($refspec.StartsWith(':')) { return $null }
    if ($refspec.Contains(':')) { $refspec = ($refspec -split ':')[-1] }
    return ($refspec -replace '^refs/heads/', '')
}

$segments = @($command -split '(?:&&|\|\||;|\r?\n|\|)')

$gitCalls = @()
$switchesToMain = $false

foreach ($segment in $segments) {
    $tokens = Get-Tokens $segment
    $subIndex = Get-GitSubcommandIndex $tokens
    if ($subIndex -lt 0) { continue }

    $gitCalls += [pscustomobject]@{
        Name     = $tokens[$subIndex]
        Tokens   = $tokens
        SubIndex = $subIndex
        Text     = $segment.Trim()
    }

    if (($tokens[$subIndex] -eq 'switch' -or $tokens[$subIndex] -eq 'checkout') -and $segment -match '(^|\s)main(\s|$)') {
        $switchesToMain = $true
    }
}

if ($gitCalls.Count -eq 0) { Approve }

# --- 判定 1: main ブランチの保護 --------------------------------------------

foreach ($call in $gitCalls) {
    $name = $call.Name
    $text = $call.Text

    # ブランチの削除は main の内容を変えないため、main 保護の判定から除外する。
    # ただし main 自身の削除は拒否する。
    if ($name -eq 'push') {
        $deleted = Get-DeletedBranchName $call.Tokens $call.SubIndex
        if ($null -ne $deleted) {
            if ($deleted -eq 'main') {
                Deny-MainBranch "main ブランチの削除は禁止されています。（$text）"
            }
            continue
        }
    }

    # ブランチに関係なく、main を push 先に名指しするものは拒否
    if ($name -eq 'push' -and $text -match '\bmain\b') {
        Deny-MainBranch "main ブランチへの直接 push は禁止されています。（$text）"
    }

    if ($name -eq 'push' -and $onMain) {
        Deny-MainBranch "現在 main ブランチにいます。main から push することはできません。（$text）"
    }

    if ($name -eq 'commit' -and ($onMain -or $switchesToMain)) {
        Deny-MainBranch "main ブランチ上でコミットすることはできません。（$text）"
    }

    if ($name -eq 'merge' -and $onMain) {
        Deny-MainBranch "main へのローカル merge は禁止されています。マージは GitHub 上の Pull Request で行ってください。（$text）"
    }
}

# --- 判定 2: ブランチ名の命名規則 -------------------------------------------
#
# GitHub の Ruleset では branch_name_pattern（メタデータ制限）が個人 Free
# アカウントで使えないため、命名規則はここで担保する。

foreach ($call in $gitCalls) {
    $target = $null

    if ($call.Name -eq 'switch' -or $call.Name -eq 'checkout') {
        $target = Get-NewBranchName $call.Tokens $call.SubIndex
    } elseif ($call.Name -eq 'push') {
        $target = Get-PushedBranchName $call.Tokens $call.SubIndex $currentBranch
    }

    if ([string]::IsNullOrWhiteSpace($target)) { continue }
    if ($target -eq 'main' -or $target -eq 'HEAD') { continue }
    if ($target -notmatch $BranchNamePattern) { Deny-BranchName $target }
}

Approve
