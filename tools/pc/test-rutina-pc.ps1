# Behaviour test for the health reporting of rutina-pc.ps1 (N-973), with a fake `gh`:
#   pwsh -NoProfile -File tools/pc/test-rutina-pc.ps1
# It loads only the functions of the script (parsed from its AST, the script itself is not run),
# so it needs no Windows, no gh and no network (PowerShell 7 or Windows PowerShell 5.1). Exit code 1
# if any check fails. UTF-8 with BOM, like the script, for the accents under 5.1.
param([string]$Script = (Join-Path $PSScriptRoot 'rutina-pc.ps1'))
$ErrorActionPreference = 'Stop'

$ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
$wanted = 'New-BodyFile', 'Find-OpenIssue', 'Add-IssueComment', 'Limit-Line', 'Report-Health', 'Add-Skip', 'Write-Log'
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($wanted -contains $f.Name) { . ([scriptblock]::Create($f.Extent.Text)) }
}

$failures = 0
function Check($cond, $msg) {
    if (-not $cond) { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Fake gh: records "args | body file text" per call and answers `issue list` from $script:openIssues.
$script:calls = @()
$script:openIssues = @()
$script:bodyBytes = $null
function gh {
    $a = @($args)
    $entry = ($a -join ' ')
    $i = [array]::IndexOf($a, '--body-file')
    if ($i -ge 0) {
        $script:bodyBytes = [IO.File]::ReadAllBytes($a[$i + 1])
        $entry += ' || ' + [Text.Encoding]::UTF8.GetString($script:bodyBytes)
    }
    $script:calls += $entry
    if ($a[0] -eq 'issue' -and $a[1] -eq 'list') { return (ConvertTo-Json -InputObject @($script:openIssues) -Compress) }
}
function Reset-Fake([object[]]$open = @()) { $script:calls = @(); $script:openIssues = $open; $script:bodyBytes = $null }

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("test-rutina-pc-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$state = $tmpRoot
$repo = 'owner/repo'
$utf8 = New-Object System.Text.UTF8Encoding $false
$log = Join-Path $tmpRoot 'run.log'

function Set-Log([string[]]$lines) { [IO.File]::WriteAllLines($log, $lines, $utf8) }
$title = { param($r) "Rutina de PC caída: $r" }
$buildIssue = @{ number = 11; title = (& $title 'build') }
$arteIssue = @{ number = 12; title = (& $title 'arte') }
$legacyIssue = @{ number = 5; title = 'Rutina de PC caída' }
$heartbeat = @{ number = 7; title = 'Rutina caída (latido): Build de la PC' }

try {
    # 1. build fails: opens the build issue (title carries the routine), body from a UTF-8 file without BOM.
    $Rutina = 'build'
    Set-Log @('2026-10-21 03:00:00 claude -p (pc-build.md) starting', 'error: algo falló en la exportación', 'claude exited with 1')
    Reset-Fake
    Report-Health $false 'claude salió con código 1'
    $create = @($script:calls | Where-Object { $_ -like 'issue create*' })
    Check ($create.Count -eq 1) 'build failure opens exactly one issue'
    Check ($create[0] -like '*--title Rutina de PC caída: build*') 'title carries the routine (build)'
    Check ($create[0] -like '*--label rutina-caida*') 'label rutina-caida'
    Check ($create[0] -like '*falló*') 'accents intact in the body file (falló)'
    Check ($create[0] -like '*código 1*') 'accents intact in the body file (código)'
    Check ($create[0] -like '*Últimas 10 líneas del log*') 'body has the last 10 lines section'
    Check ($script:bodyBytes -and -not ($script:bodyBytes[0] -eq 0xEF -and $script:bodyBytes[1] -eq 0xBB)) 'body file has no BOM'
    Check (-not ($create[0] -like '*Cupo del plan agotado*')) 'a plain failure is not marked as quota'
    Check (@($script:calls | Where-Object { $_ -like '*--body-file -*' }).Count -eq 0) 'no body through the pipe'

    # 2. art succeeds while the build issue is open: it must stay open.
    $Rutina = 'arte'
    Reset-Fake @($buildIssue)
    Report-Health $true ''
    Check (@($script:calls | Where-Object { $_ -like 'issue close*' }).Count -eq 0) 'an art success does not close the build issue'
    Check (@($script:calls | Where-Object { $_ -like 'issue comment*' }).Count -eq 0) 'an art success does not comment on the build issue'

    # 3. build succeeds: closes its own issue (with a comment) and only that one.
    $Rutina = 'build'
    Reset-Fake @($buildIssue, $arteIssue, $heartbeat)
    Report-Health $true ''
    $close = @($script:calls | Where-Object { $_ -like 'issue close*' })
    Check ($close.Count -eq 1 -and $close[0] -like 'issue close 11 *') 'a build success closes only the build issue'
    Check (@($script:calls | Where-Object { $_ -like 'issue comment 11 *Volvió a andar*' }).Count -eq 1) 'closing comment (with accents) on #11'

    # 4. legacy issue without suffix: closed by a success of either routine, with an explanation.
    $Rutina = 'arte'
    Reset-Fake @($legacyIssue, $buildIssue)
    Report-Health $true ''
    $close = @($script:calls | Where-Object { $_ -like 'issue close*' })
    Check ($close.Count -eq 1 -and $close[0] -like 'issue close 5 *') 'a success closes the legacy issue (and not the build one)'
    Check (@($script:calls | Where-Object { $_ -like 'issue comment 5 *esquema anterior*' }).Count -eq 1) 'legacy issue closed with an explanation'
    # ... and a failure does not touch the legacy one: it opens its own.
    Reset-Fake @($legacyIssue)
    Report-Health $false 'x'
    Check (@($script:calls | Where-Object { $_ -like 'issue create*' }).Count -eq 1) 'with only the legacy issue open, a failure opens the routine issue'

    # 5. a second build failure comments on the open build issue instead of opening another.
    $Rutina = 'build'
    Reset-Fake @($buildIssue, $arteIssue)
    Report-Health $false 'otra vez'
    Check (@($script:calls | Where-Object { $_ -like 'issue create*' }).Count -eq 0) 'no duplicate issue'
    Check (@($script:calls | Where-Object { $_ -like 'issue comment 11 *' }).Count -eq 1) 'comment on the build issue'

    # 6. usage limit: marked as quota, not as a breakdown; 10 tail lines, each cut to 300 chars.
    $Rutina = 'arte'
    $long = 'x' * 500
    Set-Log (@(1..15 | ForEach-Object { "linea $_" }) + @($long, "Claude AI usage limit reached|1760000000"))
    Reset-Fake
    Report-Health $false 'claude salió con código 1'
    $create = @($script:calls | Where-Object { $_ -like 'issue create*' })
    Check ($create.Count -eq 1 -and $create[0] -like '*--title Rutina de PC caída: arte*') 'quota run still reported on the arte issue'
    Check ($create[0] -like '*|| Cupo del plan agotado (regla 13), no es una caída real*') 'body starts with the quota notice'
    $tailPart = ($create[0] -split 'Últimas 10 líneas del log:')[1]
    Check ($tailPart -notlike '*linea 6*' -and $tailPart -like '*linea 8*') 'only the last 10 non-empty lines'
    Check ($tailPart -notlike ('*' + ('x' * 301) + '*') -and $tailPart -like ('*' + ('x' * 300) + '…*')) 'lines cut to 300 characters'
    foreach ($text in 'You have hit your limit', 'API Error: 429 rate_limit_error', 'monthly quota exceeded') {
        Set-Log @('claude -p starting', $text)
        Reset-Fake
        Report-Health $false 'x'
        Check ($script:calls[-1] -like '*Cupo del plan agotado*') "quota detected: $text"
    }
    foreach ($text in 'error: build of 1429 files failed', 'fatal: not a git repository', 'API Error: 400 invalid model') {
        Set-Log @('claude -p starting', $text)
        Reset-Fake
        Report-Health $false 'x'
        Check ($script:calls[-1] -notlike '*Cupo del plan agotado*') "not quota: $text"
    }

    # 7. skips: saltos.log line, comment only if this routine has an open issue, never a new issue, throttled.
    $Rutina = 'build'
    $skipLog = Join-Path $state 'saltos.log'
    Reset-Fake
    Add-Skip 'PAUSA on origin/main: skipped'
    Check ((Test-Path $skipLog) -and (Get-Content $skipLog -Raw) -match "\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\tbuild\tPAUSA on origin/main: skipped") 'saltos.log line: date, routine, reason'
    Check (@($script:calls | Where-Object { $_ -like 'issue create*' -or $_ -like 'issue comment*' }).Count -eq 0) 'a skip without an open issue does nothing on GitHub'
    Remove-Item $skipLog
    Reset-Fake @($buildIssue, $arteIssue)
    Add-Skip 'another PC routine is running: skipped'
    Check (@($script:calls | Where-Object { $_ -like 'issue comment 11 *no es una falla*' }).Count -eq 1) 'a skip comments on the open issue of its routine'
    Reset-Fake @($buildIssue)
    Add-Skip 'another PC routine is running: skipped'
    Check (@($script:calls | Where-Object { $_ -like 'issue comment*' }).Count -eq 0) 'the same skip is not commented again within 12 hours'
    Check (@(Get-Content $skipLog).Count -eq 2) 'but it is still logged'
    Reset-Fake @($arteIssue)
    Add-Skip 'PAUSA on origin/main: skipped'
    Check (@($script:calls | Where-Object { $_ -like 'issue comment*' }).Count -eq 0) 'a skip does not comment on the other routine issue'
} finally {
    Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) { Write-Host "$failures check(s) failed"; exit 1 }
Write-Host 'rutina-pc health tests: OK'
