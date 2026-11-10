Set-StrictMode -Version Latest

function Get-HidHideCliPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    $dependency = Test-BridgeDependencies -Config $Config | Where-Object { $_.Name -eq 'HidHide CLI' -and $_.Available } | Select-Object -First 1
    if (-not $dependency) { throw 'HidHide is not installed. Run .\run.ps1 -InstallDependencies and approve its setup.' }
    $dependency.Path
}

function Invoke-HidHideCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$RequireElevation
    )
    $cli = Get-HidHideCliPath -Config $Config
    if ($RequireElevation) {
        $quoted = @($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
        try {
            $process = Start-Process -FilePath $cli -ArgumentList $quoted -Verb RunAs -Wait -PassThru -ErrorAction Stop
        } catch { throw "HidHide configuration needs administrator approval. Operation cancelled: $($_.Exception.Message)" }
        if ($process.ExitCode -ne 0) { throw "HidHideCLI failed with exit code $($process.ExitCode)." }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = ''; StdErr = '' }
    }
    Invoke-BridgeTool -FilePath $cli -Arguments $Arguments -TimeoutSeconds 15
}

function Get-HidHideLines {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config,[Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-HidHideCli -Config $Config -Arguments $Arguments
    if ($result.ExitCode -ne 0) { throw "HidHideCLI read failed: $($result.StdErr)" }
    @($result.StdOut -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^[-=]+$' })
}

function Get-BridgeControllerInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
        throw 'Get-PnpDevice is unavailable. Use Windows 10/11 with the PnpDevice module.'
    }
    # HidHide's gaming inventory uses HID usage information instead of device
    # names, so generic/third-party controllers are not lost to name heuristics.
    $result = Invoke-HidHideCli -Config $Config -Arguments @('--dev-gaming')
    if ($result.ExitCode -ne 0) { throw "Could not enumerate game controllers: $($result.StdErr)" }
    try { $containers = @($result.StdOut | ConvertFrom-Json -ErrorAction Stop) }
    catch { throw "HidHide returned invalid gaming-device JSON: $($_.Exception.Message)" }

    $inventory = New-Object System.Collections.Generic.List[object]
    foreach ($container in $containers) {
        $paths = New-Object System.Collections.Generic.List[string]
        foreach ($device in @($container.devices)) {
            if (-not $device.present -or -not $device.gamingDevice) { continue }
            foreach ($propertyName in @('deviceInstancePath', 'xusbDeviceInstancePath', 'baseContainerDeviceInstancePath')) {
                $property = $device.PSObject.Properties[$propertyName]
                if ($property -and $property.Value -and -not $paths.Contains([string]$property.Value)) {
                    $paths.Add([string]$property.Value)
                }
            }
        }
        if ($paths.Count -eq 0) { continue }
        $inventory.Add([pscustomobject]@{
            InstanceId = $paths[0]
            InstanceIds = @($paths.ToArray())
            Name = [string]$container.friendlyName
            Class = 'HID game controller'
            Status = 'OK'
        })
    }
    @($inventory | Sort-Object InstanceId -Unique)
}

function Test-HidHideReady {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    try {
        $null = Get-HidHideCliPath -Config $Config
        $driver = Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)HidHide' -and $_.State -eq 'Running' } | Select-Object -First 1
        [bool]$driver
    } catch { $false }
}

function Get-HidHideSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    $deviceLines = Get-HidHideLines -Config $Config -Arguments @('--dev-list')
    $hiddenDevices = @($deviceLines | ForEach-Object {
        if ($_ -match '^--dev-hide\s+"(?<path>.*)"\s*$') { $Matches.path }
    } | Where-Object { $_ })
    $appLines = Get-HidHideLines -Config $Config -Arguments @('--app-list')
    $allowedApps = @($appLines | ForEach-Object {
        if ($_ -match '^--app-reg\s+"(?<path>.*)"\s*$') { $Matches.path }
    } | Where-Object { $_ })
    $stateResult = Invoke-HidHideCli -Config $Config -Arguments @('--cloak-state')
    if ($stateResult.ExitCode -ne 0) { throw "Could not read HidHide cloak state: $($stateResult.StdErr)" }
    $stateText = $stateResult.StdOut.Trim()
    if ($stateText -eq '--cloak-on') { $isOn = $true }
    elseif ($stateText -eq '--cloak-off') { $isOn = $false }
    else { throw "Unrecognized HidHide cloak state output: $stateText" }
    [pscustomobject]@{ HiddenDevices = $hiddenDevices; AllowedApps = $allowedApps; CloakWasOn = [bool]$isOn }
}

function Enable-BridgeControllerIsolation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string[]]$ControllerInstanceIds,
        [Parameter(Mandatory)][string]$ScrcpyPath,
        [Parameter(Mandatory)][int]$ProcessId
    )

    if (-not (Test-HidHideReady -Config $Config)) { throw 'HidHide driver is missing or not running. Install/configure HidHide first.' }
    if (Test-Path -LiteralPath $Config.RecoveryPath) { throw 'Existing recovery state must be restored before changing HidHide settings.' }
    $snapshot = Get-HidHideSnapshot -Config $Config
    $state = [pscustomobject]@{
        CreatedAt = (Get-Date).ToString('o')
        ControllerInstanceIds = @($ControllerInstanceIds)
        ScrcpyPath = $ScrcpyPath
        ProcessId = $ProcessId
        DeviceStates = @()
        AppWasAllowed = @($snapshot.AllowedApps | Where-Object { $_ -ieq $ScrcpyPath }).Count -gt 0
        CloakWasOn = $snapshot.CloakWasOn
    }
    # Snapshot each selected path before changing any HidHide setting.
    $state.DeviceStates = @($ControllerInstanceIds | ForEach-Object {
        $instancePath = [string]$_
        [pscustomobject]@{ InstanceId = $instancePath; WasHidden = @($snapshot.HiddenDevices | Where-Object { $_ -eq $instancePath }).Count -gt 0 }
    })
    $preexistingHidden = @($snapshot.HiddenDevices)
    $selectedPaths = @($ControllerInstanceIds)
    if (-not $state.CloakWasOn -and @($preexistingHidden | Where-Object { $selectedPaths -notcontains $_ }).Count -gt 0) {
        throw 'HidHide already has other devices configured while cloaking is off. Refusing to turn cloaking on because it could hide unrelated devices.'
    }
    $parent = Split-Path -Parent $Config.RecoveryPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporaryState = $Config.RecoveryPath + '.tmp'
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporaryState -Encoding UTF8
    Move-Item -LiteralPath $temporaryState -Destination $Config.RecoveryPath -Force
    try {
        if (-not $state.AppWasAllowed) { $null = Invoke-HidHideCli -Config $Config -Arguments @('--app-reg', $ScrcpyPath) -RequireElevation }
        foreach ($deviceState in $state.DeviceStates) {
            if (-not $deviceState.WasHidden) { $null = Invoke-HidHideCli -Config $Config -Arguments @('--dev-hide', [string]$deviceState.InstanceId) -RequireElevation }
        }
        if (-not $state.CloakWasOn) { $null = Invoke-HidHideCli -Config $Config -Arguments @('--cloak-on') -RequireElevation }
        $state
    } catch {
        try { Restore-BridgeControllerVisibility -Config $Config -State $state } catch { Write-Warning "Isolation rollback failed; run .\run.ps1 -Recover. $($_.Exception.Message)" }
        throw
    }
}

function Restore-BridgeControllerVisibility {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config,[Parameter(Mandatory)]$State)

    $errors = New-Object System.Collections.Generic.List[string]
    if (-not $State.CloakWasOn) {
        try { $null = Invoke-HidHideCli -Config $Config -Arguments @('--cloak-off') -RequireElevation } catch { $errors.Add($_.Exception.Message) }
    }
    $deviceStates = @($State.DeviceStates)
    if (-not $deviceStates -and $State.ControllerInstanceId) {
        $deviceStates = @([pscustomobject]@{ InstanceId = [string]$State.ControllerInstanceId; WasHidden = [bool]$State.DeviceWasHidden })
    }
    foreach ($deviceState in $deviceStates) {
        if (-not $deviceState.WasHidden) {
            try { $null = Invoke-HidHideCli -Config $Config -Arguments @('--dev-unhide', [string]$deviceState.InstanceId) -RequireElevation } catch { $errors.Add($_.Exception.Message) }
        }
    }
    if (-not $State.AppWasAllowed) {
        try { $null = Invoke-HidHideCli -Config $Config -Arguments @('--app-unreg', [string]$State.ScrcpyPath) -RequireElevation } catch { $errors.Add($_.Exception.Message) }
    }
    if ($errors.Count -gt 0) { throw ('Could not fully restore HidHide settings: ' + ($errors -join '; ')) }
    if (Test-Path -LiteralPath $Config.RecoveryPath) { Remove-Item -LiteralPath $Config.RecoveryPath -Force }
}

Export-ModuleMember -Function Get-BridgeControllerInventory, Test-HidHideReady, Get-HidHideSnapshot, Enable-BridgeControllerIsolation, Restore-BridgeControllerVisibility, Invoke-HidHideCli
