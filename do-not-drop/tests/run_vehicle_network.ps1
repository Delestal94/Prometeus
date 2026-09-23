param(
    [string]$Godot = 'D:\Descargas\Godot_v4.7.2-stable_win64.exe',
    [int]$Port = 17887
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testLogPath = Join-Path ([IO.Path]::GetTempPath()) ('do-not-drop-visual-net-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testLogPath | Out-Null
$commonArgs = @('--headless', '--max-fps', '60', '--path', ('"' + $projectPath + '"'), 'res://tests/vehicle_network_probe.tscn', '--', "--port=$Port")
$testHost = $null
$testClient = $null
try {
    $testHost = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--host') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testLogPath 'host.log') -RedirectStandardError (Join-Path $testLogPath 'host.err')
    $null = $testHost.Handle  # Without touching Handle first, ExitCode reads back empty.
    $testClient = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--client') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testLogPath 'client.log') -RedirectStandardError (Join-Path $testLogPath 'client.err')
    $null = $testClient.Handle  # Without touching Handle first, ExitCode reads back empty.
    $clientExited = $testClient.WaitForExit(20000)
    # The host waits ~0.5s after the client's ack before leaving its own
    # session and quitting (vehicle_network_probe.gd), plus real network
    # teardown -- 2s here was too tight and flaked under normal timing
    # variance even when both processes printed PASS.
    $hostExited = $testHost.WaitForExit(8000)
    Get-Content -LiteralPath (Join-Path $testLogPath 'host.log'), (Join-Path $testLogPath 'host.err'), (Join-Path $testLogPath 'client.log'), (Join-Path $testLogPath 'client.err')
    $errors = @(Get-Content -LiteralPath (Join-Path $testLogPath 'host.err'), (Join-Path $testLogPath 'client.err') | Where-Object { $_ -match 'ERROR:|SCRIPT ERROR:' })
    if (-not $clientExited -or -not $hostExited -or $testClient.ExitCode -ne 0 -or $testHost.ExitCode -ne 0 -or $errors.Count -gt 0) {
        throw "Network presentation regression failed. Logs: $testLogPath"
    }
    Write-Output "PASS: two-process network test. Logs: $testLogPath"
} finally {
    foreach ($testProcess in @($testHost, $testClient)) {
        if ($null -ne $testProcess -and -not $testProcess.HasExited) {
            Stop-Process -Id $testProcess.Id
        }
    }
}
