Set-StrictMode -Version Latest

function Show-BridgeBanner {
    Write-Host ''
    Write-Host '  AirPad' -ForegroundColor Cyan
    Write-Host '  Android TV controller bridge | ADB over Wi-Fi | scrcpy gamepad forwarding' -ForegroundColor DarkGray
    Write-Host '  PC controller must be paired over Bluetooth or use a wireless receiver.' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-AdbSetupInstructions {
    [CmdletBinding()]
    param([string]$State = 'Missing')
    $guidanceState = if ($State -eq 'unauthorized') { 'Unauthorized' } elseif ($State -eq 'offline') { 'Offline' } else { 'Missing' }
    foreach ($line in (Get-AdbSetupGuidance -State $guidanceState)) { Write-Host "  $line" -ForegroundColor Yellow }
}

function Read-BridgeSelection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Items,[Parameter(Mandatory)][string]$Prompt)
    if (-not $Items -or $Items.Count -eq 0) { return $null }
    for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $Items[$i]) }
    $inputValue = Read-Host $Prompt
    $number = 0
    if (-not [int]::TryParse($inputValue, [ref]$number) -or $number -lt 1 -or $number -gt $Items.Count) { return $null }
    $Items[$number - 1]
}

function Select-BridgeDevice {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    Write-Host 'Scanning for reachable Android TV ADB devices...' -ForegroundColor Cyan
    try { $devices = @(Find-AdbNetworkDevices -Config $Config) }
    catch { Write-Host "ADB scan failed: $($_.Exception.Message)" -ForegroundColor Red; return $null }
    if ($devices.Count -eq 0) {
        $all = @(Get-AdbDeviceInventory -Config $Config -ErrorAction SilentlyContinue)
        $state = if ($all.State -contains 'unauthorized') { 'unauthorized' } elseif ($all.State -contains 'offline') { 'offline' } else { 'missing' }
        Show-AdbSetupInstructions -State $state
        $manual = Read-Host 'If your TV shows ADB over Wi-Fi as IP:port, enter it to try that endpoint (or press Enter to rescan)'
        if ($manual -match '^(?:(?:\d{1,3}\.){3}\d{1,3}):\d{1,5}$') {
            $hostAddress = $manual.Split(':')[0]
            if (-not (Test-PrivateIPv4Address -Address $hostAddress)) { Write-Host 'Only private/local IPv4 targets are accepted.' -ForegroundColor Red; return $null }
            $null = Invoke-BridgeAdb -Config $Config -Arguments @('connect', $manual) -TimeoutSeconds 10
            $devices = @(Get-AdbDeviceInventory -Config $Config | Where-Object { $_.Serial -eq $manual -and $_.State -eq 'device' -and $_.Transport -eq 'Network' })
        }
    }
    if ($devices.Count -eq 0) { return $null }
    $labels = @($devices | ForEach-Object { "{0}  [{1}] {2}" -f $_.Serial, $_.State, $(if ($_.Model) { $_.Model } else { 'Android TV/box' }) })
    $chosenLabel = Read-BridgeSelection -Items $labels -Prompt 'Choose a TV number'
    if (-not $chosenLabel) { Write-Host 'No TV selected.'; return $null }
    $index = [array]::IndexOf($labels, [string]$chosenLabel)
    $chosen = $devices[$index]
    $answer = Read-Host "Connect to $($chosen.Serial)? (y/N)"
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Connection cancelled.'; return $null }
    $chosen
}

function Select-BridgeController {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    $controllers = @(Get-BridgeControllerInventory -Config $Config)
    if ($controllers.Count -eq 0) {
        Write-Host 'No Windows-recognized Bluetooth or wireless-receiver gamepad was detected.' -ForegroundColor Yellow
        Write-Host 'Pair the controller to Windows or connect its wireless receiver, then retry.'
        return $null
    }
    $labels = @($controllers | ForEach-Object { "{0}  ({1})" -f $_.Name, $_.InstanceId })
    $chosenLabel = Read-BridgeSelection -Items $labels -Prompt 'Choose a controller number'
    if (-not $chosenLabel) { return $null }
    $index = [array]::IndexOf($labels, [string]$chosenLabel)
    $controllers[$index]
}

function Start-BridgeMenu {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    Show-BridgeBanner
    while ($true) {
        Write-Host '[1] Scan and connect to Android TV'
        Write-Host '[2] Install/download dependencies'
        Write-Host '[3] Recover controller visibility'
        Write-Host '[4] Exit'
        $choice = Read-Host 'Select an option'
        switch ($choice) {
            '1' {
                $device = Select-BridgeDevice -Config $Config
                if (-not $device) { continue }
                $controller = Select-BridgeController -Config $Config
                if (-not $controller) { continue }
                $scrcpyPath = Get-BridgeExecutablePath -Config $Config -Name 'scrcpy.exe' -ErrorAction SilentlyContinue
                if (-not $scrcpyPath) { Write-Host 'Install dependencies first with option 2.' -ForegroundColor Yellow; continue }
                Write-Host 'During the session, HidHide will hide this controller from ordinary Windows apps.' -ForegroundColor Yellow
                Write-Host 'Stopping restores its prior visibility. A forced PowerShell exit may require option 3.' -ForegroundColor Yellow
                try { Start-BridgeSession -Config $Config -DeviceSerial $device.Serial -ControllerInstanceIds $controller.InstanceIds }
                catch { Write-Host "Could not start bridge: $($_.Exception.Message)" -ForegroundColor Red }
            }
            '2' { try { Install-BridgeDependencies -Config $Config -IncludeDriver } catch { Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red } }
            '3' { try { Restore-InterruptedBridgeSession -Config $Config } catch { Write-Host "Recovery failed: $($_.Exception.Message)" -ForegroundColor Red } }
            '4' { return }
            default { Write-Host 'Choose 1, 2, 3 or 4.' -ForegroundColor Yellow }
        }
        Write-Host ''
    }
}

Export-ModuleMember -Function Start-BridgeMenu, Show-AdbSetupInstructions, Read-BridgeSelection, Select-BridgeDevice, Select-BridgeController
