# Launches one unattended PC routine of Take My Package (.claude/rutinas/README.md, "Las rutinas de
# la PC"), meant to be run by a Windows scheduled task.
#   -Rutina arte   -> .claude/rutinas/sesion-arte.md (Blender + ComfyUI)
#   -Rutina build  -> .claude/rutinas/pc-build.md (Windows export, FPS with the real GPU)
# Works in its own clone, never in the repo Nacho works in. Windows PowerShell 5.1.
param(
    [Parameter(Mandatory = $true)][ValidateSet('arte', 'build')][string]$Rutina,
    [int]$LockWaitMinutes = 0,
    [string]$Clone = 'D:\Programas\Utilities\Proyectos\Prometeus-rutina',
    [string]$Remote = 'https://github.com/Delestal94/Prometeus.git',
    [string]$Blender = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe',
    [string]$Godot = 'D:\Descargas\Godot_v4.7.2-stable_win64_console.exe',
    [string]$ComfyMcp = 'D:\Programas\comfy-venv\Scripts\comfy-mcp.exe',
    [string]$ComfyBin = 'D:\Programas\comfy-venv\Scripts\comfy.exe',
    [string]$Model = 'claude-opus-5-5',
    # Internal: set when the script re-launches itself from the freshly checked-out clone.
    [switch]$Fresh,
    [string]$LogPath = ''
)
# Continue, not Stop: in 5.1 a native command's stderr becomes an error record; exit codes are checked by hand.
$ErrorActionPreference = 'Continue'

$state = Join-Path $env:LOCALAPPDATA 'prometeus-rutinas'
$logs = Join-Path $state 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$log = if ($LogPath) { $LogPath } else { Join-Path $logs ("{0}-{1}.log" -f $Rutina, (Get-Date -Format 'yyyyMMdd-HHmm')) }

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Out-File -FilePath $log -Append -Encoding utf8
}

# The cloud can't read these logs, so a failed run opens (or comments on) one GitHub issue per routine
# ("Rutina de PC caída: build" / ": arte") and a good run of the SAME routine closes it (a success of
# the art session once closed the build's issue, #483). The repo is public: only error lines and the
# last 10 log lines go to the issue, never the whole log.
$repo = 'Delestal94/Prometeus'

# Windows PowerShell 5.1 pipes text to native commands in ASCII ("fall?"). Bodies go through a UTF-8
# (no BOM) file instead; this also fixes what gh prints, which is parsed below.
$utf8 = New-Object System.Text.UTF8Encoding $false
$OutputEncoding = $utf8
try { [Console]::OutputEncoding = $utf8 } catch { }

function New-BodyFile([string]$text) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("rutina-issue-{0}.md" -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($tmp, $text, $utf8)
    $tmp
}

# Open `rutina-caida` issue whose title matches the regex (ASCII-only patterns, so a console that
# garbles accents cannot make the match fail and open a duplicate each run). $null if none.
function Find-OpenIssue([string]$titlePattern) {
    $json = (gh issue list --repo $repo --label rutina-caida --state open --limit 50 --json 'number,title' 2>$null) -join "`n"
    if (-not $json.Trim()) { return $null }
    $hit = @($json | ConvertFrom-Json) | Where-Object { $_.title -match $titlePattern } | Select-Object -First 1
    if ($hit) { $hit.number } else { $null }
}

function Add-IssueComment($number, [string]$text) {
    $tmp = New-BodyFile $text
    try { gh issue comment $number --repo $repo --body-file $tmp | Out-Null } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

function Limit-Line([string]$s) { if ($s.Length -gt 300) { $s.Substring(0, 300) + '…' } else { $s } }

function Report-Health([bool]$ok, [string]$detail) {
    try {
        $now = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $mine = Find-OpenIssue ('^Rutina de PC .*: {0}$' -f $Rutina)
        if ($ok) {
            if ($mine) {
                Add-IssueComment $mine "Volvió a andar: la rutina ``$Rutina`` terminó bien el $now."
                gh issue close $mine --repo $repo | Out-Null
            }
            # Old scheme (one issue for both routines, no suffix): a success of either closes it; the next
            # failure opens the issue of its own routine.
            $legacy = Find-OpenIssue '^Rutina de PC [^:]+$'
            if ($legacy) {
                Add-IssueComment $legacy ("Cierro este issue del esquema anterior (uno solo para build y arte): desde N-973 hay un issue por rutina, " +
                    "'Rutina de PC caída: build' y ': arte', y solo lo cierra un éxito de su propia rutina. Terminó bien ``$Rutina`` el $now; " +
                    "si la otra sigue caída, su issue se abre en su próxima falla.")
                gh issue close $legacy --repo $repo | Out-Null
            }
            return
        }
        $lines = @(Get-Content $log -Encoding utf8 -ErrorAction SilentlyContinue)
        $errors = @($lines |
            Where-Object { $_ -match 'API Error|error:|Error:|exited with|failed|fatal' -and $_ -notmatch 'Permission allow rule' } |
            Select-Object -Last 8 | ForEach-Object { Limit-Line $_ })
        $tail = @($lines | Where-Object { $_.Trim() } | Select-Object -Last 10 | ForEach-Object { Limit-Line $_ })
        # Plan quota (README rule 13) is not a real breakdown: say so, but still report it (the run did not
        # happen). Only the lines that go to the issue are searched, so a stray "429" elsewhere is ignored.
        $quotaPattern = 'usage limit|rate.?limit|quota|limit reached|hit your .{0,20}limit|\b429\b'
        $quota = @(($errors + $tail) | Where-Object { $_ -match $quotaPattern }).Count -gt 0
        $fence = '```'
        $head = if ($quota) {
            "Cupo del plan agotado (regla 13), no es una caída real: la rutina ``$Rutina`` de la PC no pudo correr el $now. Se resuelve cuando el cupo se renueva; no hace falta arreglar nada. Detalle: $detail"
        } else {
            "La rutina ``$Rutina`` de la PC falló el ${now}: $detail"
        }
        $body = "$head`n`nLíneas de error (log completo en la PC: ``$log``):`n$fence`n$($errors -join "`n")`n$fence`n`n" +
            "Últimas 10 líneas del log:`n$fence`n$($tail -join "`n")`n$fence"
        if ($mine) {
            Add-IssueComment $mine $body
        } else {
            $tmp = New-BodyFile $body
            try { gh issue create --repo $repo --title "Rutina de PC caída: $Rutina" --label rutina-caida --body-file $tmp | Out-Null } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log "could not report health to GitHub: $_"
    }
}

# A skipped run exits 0 and used to leave no trace (or one line in a log nobody reads). Now: one line in
# saltos.log (date, routine, reason) and, if this routine has an open issue, a comment on it. A skip
# never opens an issue; the same skip is commented at most once every 12 hours (PAUSA can last days).
function Add-Skip([string]$reason) {
    Write-Log $reason
    try {
        $skipLog = Join-Path $state 'saltos.log'
        $recent = $false
        if (Test-Path $skipLog) {
            $last = Get-Content $skipLog -Encoding utf8 -ErrorAction SilentlyContinue |
                Where-Object { $_.EndsWith("`t$Rutina`t$reason") } | Select-Object -Last 1
            if ($last) {
                $when = [datetime]::MinValue
                if ([datetime]::TryParseExact(($last -split "`t")[0], 'yyyy-MM-dd HH:mm:ss', $null, 'None', [ref]$when)) {
                    $recent = ((Get-Date) - $when).TotalHours -lt 12
                }
            }
        }
        "{0}`t{1}`t{2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Rutina, $reason |
            Out-File -FilePath $skipLog -Append -Encoding utf8
        if (-not $recent) {
            $mine = Find-OpenIssue ('^Rutina de PC .*: {0}$' -f $Rutina)
            if ($mine) { Add-IssueComment $mine "Corrida saltada el $(Get-Date -Format 'yyyy-MM-dd HH:mm') (no es una falla): $reason." }
        }
    } catch {
        Write-Log "could not record the skip: $_"
    }
}

# Keep the last 200 logs.
Get-ChildItem $logs -Filter '*.log' | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 200 | Remove-Item -Force -ErrorAction SilentlyContinue

# One PC routine at a time: they share the 8 GB GPU. The OS drops the lock if this process dies.
# The re-launched copy (-Fresh) runs while its parent holds the lock.
$lockPath = Join-Path $state 'rutina.lock'
$lock = $null
$deadline = (Get-Date).AddMinutes($LockWaitMinutes)
while (-not $lock -and -not $Fresh) {
    try {
        $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch {
        if ((Get-Date) -ge $deadline) { Add-Skip 'another PC routine is running: skipped'; exit 0 }
        Start-Sleep -Seconds 60
    }
}

try {
    if (-not $Fresh) {
        if (-not (Test-Path (Join-Path $Clone '.git'))) {
            Write-Log "cloning into $Clone"
            git clone --quiet $Remote $Clone
            if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
        }
        Set-Location $Clone
        git config user.name 'Nacho'
        git config user.email 'delestal.miguelignacio@gmail.com'
        git config core.hooksPath .githooks

        git fetch --quiet --prune origin
        if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }
        # Hand brake: same file the cloud routines honour.
        git cat-file -e origin/main:.claude/rutinas/PAUSA 2>$null
        if ($LASTEXITCODE -eq 0) { Add-Skip 'PAUSA on origin/main: skipped'; exit 0 }
        # Budget level (README rule 1 bis): the art session skips at "minimo" and only runs every
        # 6 hours at "ahorro"; the build always runs. Checked here so Claude is not even started.
        $budget = (git show origin/main:.claude/rutinas/PRESUPUESTO 2>$null | Select-Object -First 1)
        if ($budget) { $budget = ($budget.Trim() -split '\s+')[0].ToLower() }
        if ($Rutina -eq 'arte' -and $budget -eq 'minimo') { Add-Skip 'PRESUPUESTO minimo: art session skipped'; exit 0 }
        if ($Rutina -eq 'arte' -and $budget -eq 'ahorro' -and ((Get-Date).Hour % 6) -ne 0) {
            Add-Skip 'PRESUPUESTO ahorro: art session only at 00, 06, 12 and 18 h'; exit 0
        }

        # Start from a clean origin/main; ignored files (.godot import cache, builds/) survive.
        git reset --quiet --hard
        git clean -fdq
        git switch --quiet --detach origin/main
        if ($LASTEXITCODE -ne 0) { throw 'git switch failed' }

        # This process runs whatever copy of the script the last routine left in the clone (a routine
        # can leave it on an old branch: the 06:30 run of 2026-09-30 used a copy without the health
        # issue). Hand over to the copy just checked out from origin/main.
        $freshScript = Join-Path $Clone 'tools\pc\rutina-pc.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $freshScript -Rutina $Rutina -Fresh -LogPath $log `
            -Clone $Clone -Remote $Remote -Blender $Blender -Godot $Godot -ComfyMcp $ComfyMcp -ComfyBin $ComfyBin -Model $Model
        exit $LASTEXITCODE
    }
    Set-Location $Clone

    if ($Rutina -eq 'arte') {
        $up = $false
        try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 9876); $c.Close(); $up = $true } catch {}
        if (-not $up) {
            Write-Log 'starting Blender with the MCP server'
            $script = Join-Path $Clone 'tools\pc\blender_mcp_autostart.py'
            Start-Process -FilePath $Blender -ArgumentList @('--python', "`"$script`"") -WindowStyle Minimized
            for ($i = 0; $i -lt 60 -and -not $up; $i++) {
                Start-Sleep -Seconds 3
                try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 9876); $c.Close(); $up = $true } catch {}
            }
            if (-not $up) { Write-Log 'Blender MCP server did not come up: the routine will report it' }
        }
    }

    # Only Blender and ComfyUI: the routines need nothing else, and --strict-mcp-config skips the rest.
    $mcp = @{
        mcpServers = @{
            'blender'   = @{ type = 'stdio'; command = 'uvx'; args = @('mcp-for-blender'); env = @{} }
            'comfy-mcp' = @{ type = 'stdio'; command = $ComfyMcp; args = @(); env = @{ COMFY_BIN = $ComfyBin } }
        }
    }
    $mcpPath = Join-Path $state 'mcp-pc.json'
    $mcp | ConvertTo-Json -Depth 5 | Out-File -FilePath $mcpPath -Encoding ascii

    $env:GODOT = $Godot
    $env:TMP_DUENO = 'nacho'
    $file = @{ arte = 'sesion-arte.md'; build = 'pc-build.md' }[$Rutina]
    $prompt = "Hacé ``git fetch origin``, leé ``.claude/rutinas/$file`` de origin/main " +
        "(``git show origin/main:.claude/rutinas/$file``) y seguilo al pie de la letra. " +
        "Corrés en la PC de Nacho (rutina local, sin nadie mirando), en el clon $Clone."

    # An old CLI rejects the current model with a 400 and the run dies in seconds (2026-09-30):
    # update first; if the update fails the run still tries with what is installed.
    Write-Log 'updating Claude Code'
    & npm install --global '@anthropic-ai/claude-code@latest' --no-fund --no-audit --loglevel=error 2>&1 |
        ForEach-Object { "$_" } | Out-File -FilePath $log -Append -Encoding utf8
    Write-Log "claude $((& claude --version 2>$null) -join ' ')"

    Write-Log "claude -p ($file) starting"
    # 2>&1 + Out-File utf8: Windows PowerShell's *>> writes UTF-16, which nobody could read.
    & claude -p $prompt --model $Model --permission-mode auto --permission-prompts none `
        --mcp-config $mcpPath --strict-mcp-config --output-format text 2>&1 |
        ForEach-Object { "$_" } | Out-File -FilePath $log -Append -Encoding utf8
    $code = $LASTEXITCODE
    Write-Log "claude exited with $code"
    if ($code -eq 0) { Report-Health $true '' } else { Report-Health $false "claude salió con código $code" }
} catch {
    Write-Log "error: $_"
    Report-Health $false "$_"
    exit 1
} finally {
    # Only what this routine opened: Godot run on the clone and the exported build inside it.
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { ($_.Name -like 'Godot*' -and $_.CommandLine -like "*$Clone*") -or $_.ExecutablePath -like "$Clone*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($lock) { $lock.Close() }
}
