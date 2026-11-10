Set-StrictMode -Version Latest

function Get-BridgeExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config,[Parameter(Mandatory)][ValidateSet('scrcpy.exe','adb.exe')][string]$Name)
    $dependency = Test-BridgeDependencies -Config $Config | Where-Object { $_.Name -eq $(if ($Name -eq 'scrcpy.exe') { 'scrcpy' } else { 'ADB' }) -and $_.Available } | Select-Object -First 1
    if (-not $dependency) { throw "$Name is missing. Run .\run.ps1 -InstallDependencies first." }
    $dependency.Path
}

function Test-BridgeTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config,[Parameter(Mandatory)][string]$DeviceSerial)
    $device = Get-AdbDeviceInventory -Config $Config | Where-Object { $_.Serial -eq $DeviceSerial -and $_.State -eq 'device' -and $_.Transport -eq 'Network' } | Select-Object -First 1
    if (-not $device) { throw "ADB target '$DeviceSerial' is not an authorized network device." }
    $device
}

function Stop-BridgeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$ScrcpyPath
    )

    if ($ProcessId -le 0) { return }
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process -or $process.ProcessName -ne 'scrcpy') { return }
    try { $actualPath = [string]$process.Path }
    catch { throw "Cannot verify the recorded scrcpy process path for PID ${ProcessId}: $($_.Exception.Message)" }
    if (-not $actualPath) { throw "Cannot verify the recorded scrcpy process path for PID $ProcessId." }
    if ($actualPath -ine $ScrcpyPath) { return }

    $stopError = $null
    try { Stop-Process -Id $ProcessId -Force -ErrorAction Stop }
    catch { $stopError = $_.Exception.Message }
    try { Wait-Process -Id $ProcessId -Timeout 5 -ErrorAction Stop } catch { }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($process -and $process.ProcessName -eq 'scrcpy') {
        try { $actualPath = [string]$process.Path }
        catch { throw "Cannot confirm scrcpy process $ProcessId has stopped: $($_.Exception.Message)" }
        if (-not $actualPath) { throw "Cannot confirm scrcpy process $ProcessId has stopped." }
        if ($actualPath -ieq $ScrcpyPath) {
            if ($stopError) { throw "Could not stop scrcpy process ${ProcessId}: $stopError" }
            throw "scrcpy process $ProcessId is still running after the stop request."
        }
    }
}

function Complete-BridgeSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$ScrcpyPath
    )

    if ($ProcessId -gt 0) {
        try { Stop-BridgeProcess -ProcessId $ProcessId -ScrcpyPath $ScrcpyPath }
        catch {
            Write-Warning "Could not confirm scrcpy has stopped; controller isolation and recovery state were retained. Stop scrcpy manually, then run .\run.ps1 -Recover. $($_.Exception.Message)"
            return $false
        }
    }
    try {
        Restore-BridgeControllerVisibility -Config $Config -State $State
        Write-Host 'Bridge stopped. Controller visibility was restored on Windows.'
    } catch {
        Write-Warning "Controller visibility restoration needs attention. Run .\run.ps1 -Recover. $($_.Exception.Message)"
    }
    $true
}

function Start-BridgeSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$DeviceSerial,
        [Parameter(Mandatory)][string[]]$ControllerInstanceIds
    )

    $legacyRecoveryExists = $Config.PSObject.Properties['LegacyRecoveryPath'] -and (Test-Path -LiteralPath $Config.LegacyRecoveryPath)
    if ((Test-Path -LiteralPath $Config.RecoveryPath) -or $legacyRecoveryExists) {
        throw 'A previous session still has recovery state. Run .\run.ps1 -Recover before starting another session.'
    }
    $null = Test-BridgeTarget -Config $Config -DeviceSerial $DeviceSerial
    $scrcpyPath = Get-BridgeExecutablePath -Config $Config -Name 'scrcpy.exe'
    $help = Invoke-BridgeTool -FilePath $scrcpyPath -Arguments @('--help') -TimeoutSeconds 10
    if (($help.StdOut + $help.StdErr) -notmatch '(?m)--gamepad') { throw 'This scrcpy build does not advertise gamepad forwarding. No controller settings were changed.' }
    $inventory = @(Get-BridgeControllerInventory -Config $Config)
    $controller = $inventory | Where-Object { @($_.InstanceIds) -contains $ControllerInstanceIds[0] } | Select-Object -First 1
    if (-not $controller -or @($ControllerInstanceIds | Where-Object { $controller.InstanceIds -notcontains $_ }).Count -gt 0) {
        throw 'The selected controller paths are not present in the Windows game-controller inventory.'
    }
    if (-not (Test-HidHideReady -Config $Config)) { throw 'HidHide is not ready. Install the driver before starting a bridge session.' }

    $logPath = Join-Path $Config.LogRoot ("scrcpy-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $arguments = @('--serial', $DeviceSerial, '--gamepad=uhid', '--no-video', '--no-audio')
    $process = $null
    $state = $null
    try {
        # Hide the selected controller before scrcpy starts forwarding, so there
        # is no startup window where both Windows apps and the TV receive input.
        $state = Enable-BridgeControllerIsolation -Config $Config -ControllerInstanceIds $ControllerInstanceIds -ScrcpyPath $scrcpyPath -ProcessId 0
        $process = Start-Process -FilePath $scrcpyPath -ArgumentList ($arguments -join ' ') -PassThru -RedirectStandardOutput $logPath -RedirectStandardError ($logPath + '.err')
        $state.ProcessId = $process.Id
        $temporaryState = $Config.RecoveryPath + '.tmp'
        $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporaryState -Encoding UTF8
        Move-Item -LiteralPath $temporaryState -Destination $Config.RecoveryPath -Force
        Start-Sleep -Milliseconds 800
        if ($process.HasExited) { throw "scrcpy exited during startup (code $($process.ExitCode)). See $logPath" }
        Write-Host "Connected to $DeviceSerial. Controller input is now captured by the TV bridge. Press Q to stop."

        while (-not $process.HasExited) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Q) { break }
            }
            Start-Sleep -Milliseconds 100
        }
    } finally {
        if ($state) {
            $processId = if ($process) { [int]$process.Id } else { 0 }
            $null = Complete-BridgeSession -Config $Config -State $state -ProcessId $processId -ScrcpyPath $scrcpyPath
        }
    }
}

function Restore-InterruptedBridgeSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    $recoveryPath = $Config.RecoveryPath
    if (-not (Test-Path -LiteralPath $recoveryPath) -and $Config.PSObject.Properties['LegacyRecoveryPath'] -and (Test-Path -LiteralPath $Config.LegacyRecoveryPath)) {
        $recoveryPath = $Config.LegacyRecoveryPath
    }
    if (-not (Test-Path -LiteralPath $recoveryPath)) {
        Write-Host 'No interrupted controller-isolation state was found.'
        return
    }
    $state = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
    if ($state.ProcessId) {
        Stop-BridgeProcess -ProcessId ([int]$state.ProcessId) -ScrcpyPath ([string]$state.ScrcpyPath)
    }
    Restore-BridgeControllerVisibility -Config $Config -State $state
    if ($recoveryPath -ne $Config.RecoveryPath -and (Test-Path -LiteralPath $recoveryPath)) { Remove-Item -LiteralPath $recoveryPath -Force }
    Write-Host 'Interrupted session recovered; controller visibility is restored.'
}

Export-ModuleMember -Function Start-BridgeSession, Restore-InterruptedBridgeSession, Test-BridgeTarget, Get-BridgeExecutablePath
