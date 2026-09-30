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
    [string]$Model = 'claude-opus-5-5'
)
# Continue, not Stop: in 5.1 a native command's stderr becomes an error record; exit codes are checked by hand.
$ErrorActionPreference = 'Continue'

$state = Join-Path $env:LOCALAPPDATA 'prometeus-rutinas'
$logs = Join-Path $state 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$log = Join-Path $logs ("{0}-{1}.log" -f $Rutina, (Get-Date -Format 'yyyyMMdd-HHmm'))

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Out-File -FilePath $log -Append -Encoding utf8
}

# Keep the last 200 logs.
Get-ChildItem $logs -Filter '*.log' | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 200 | Remove-Item -Force -ErrorAction SilentlyContinue

# One PC routine at a time: they share the 8 GB GPU. The OS drops the lock if this process dies.
$lockPath = Join-Path $state 'rutina.lock'
$lock = $null
$deadline = (Get-Date).AddMinutes($LockWaitMinutes)
while (-not $lock) {
    try {
        $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch {
        if ((Get-Date) -ge $deadline) { Write-Log 'another PC routine is running: skipped'; exit 0 }
        Start-Sleep -Seconds 60
    }
}

try {
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
    if ($LASTEXITCODE -eq 0) { Write-Log 'PAUSA on origin/main: skipped'; exit 0 }

    # Start from a clean origin/main; ignored files (.godot import cache, builds/) survive.
    git reset --quiet --hard
    git clean -fdq
    git switch --quiet --detach origin/main
    if ($LASTEXITCODE -ne 0) { throw 'git switch failed' }

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
            'blender'   = @{ type = 'stdio'; command = 'uvx'; args = @('blender-mcp'); env = @{} }
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

    Write-Log "claude -p ($file) starting"
    & claude -p $prompt --model $Model --permission-mode auto --permission-prompts none `
        --mcp-config $mcpPath --strict-mcp-config --output-format text *>> $log
    Write-Log "claude exited with $LASTEXITCODE"
} catch {
    Write-Log "error: $_"
    exit 1
} finally {
    # Only what this routine opened: Godot run on the clone and the exported build inside it.
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { ($_.Name -like 'Godot*' -and $_.CommandLine -like "*$Clone*") -or $_.ExecutablePath -like "$Clone*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($lock) { $lock.Close() }
}
