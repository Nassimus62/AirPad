Set-StrictMode -Version Latest

function Get-BridgeAdbPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    $available = Test-BridgeDependencies -Config $Config | Where-Object { $_.Name -eq 'ADB' -and $_.Available } | Select-Object -First 1
    if (-not $available) { throw 'ADB is missing. Run .\run.ps1 -InstallDependencies first.' }
    $available.Path
}

function Invoke-BridgeAdb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 20
    )
    $adb = Get-BridgeAdbPath -Config $Config
    Invoke-BridgeTool -FilePath $adb -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
}

function Get-AdbDeviceInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $result = Invoke-BridgeAdb -Config $Config -Arguments @('devices', '-l')
    if ($result.ExitCode -ne 0) { throw "ADB devices failed: $($result.StdErr)" }
    foreach ($line in ($result.StdOut -split "`r?`n")) {
        if ($line -match '^([^\s]+)\s+(device|offline|unauthorized)(?:\s+(.*))?$') {
            $serial = $Matches[1]
            $state = $Matches[2]
            $details = $Matches[3]
            $model = if ($details -match 'model:([^\s]+)') { $Matches[1] } else { $null }
            $transport = 'Local/USB'
            if ($serial -match '^(?<host>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d{1,5})$') {
                $portNumber = [int]$Matches.port
                if ((Test-PrivateIPv4Address -Address $Matches.host) -and $portNumber -ge 1 -and $portNumber -le 65535) { $transport = 'Network' }
                else { $transport = 'External' }
            } elseif ($serial -match ':\d+$') {
                # Hostnames and other endpoint forms are not accepted as trusted LAN targets.
                $transport = 'External'
            } elseif ($serial -match '^emulator-') { $transport = 'Emulator' }
            [pscustomobject]@{ Serial = $serial; State = $state; Model = $model; Transport = $transport }
        }
    }
}

function Test-PrivateIPv4Address {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Address)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return $false }
    $bytes = $parsed.GetAddressBytes()
    if ($bytes.Length -ne 4) { return $false }
    return (($bytes[0] -eq 10) -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or ($bytes[0] -eq 169 -and $bytes[1] -eq 254))
}

function Get-LocalAdbCandidates {
    [CmdletBinding()]
    param()
    $candidates = New-Object System.Collections.Generic.HashSet[string]
    $interfaces = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.AddressState -eq 'Preferred' -and $_.PrefixLength -ge 24 -and (Test-PrivateIPv4Address -Address $_.IPAddress) }
    foreach ($interface in $interfaces) {
        $bytes = [System.Net.IPAddress]::Parse($interface.IPAddress).GetAddressBytes()
        $prefix = [int]$interface.PrefixLength
        $mask = [uint32]([uint32]::MaxValue -shl (32 - $prefix))
        $ipNum = ([uint32]$bytes[0] -shl 24) -bor ([uint32]$bytes[1] -shl 16) -bor ([uint32]$bytes[2] -shl 8) -bor [uint32]$bytes[3]
        $network = $ipNum -band $mask
        $hostCount = [Math]::Min([Math]::Pow(2, 32 - $prefix), 256)
        for ($offset = 1; $offset -lt ($hostCount - 1); $offset++) {
            $candidateNumber = [uint32]($network + $offset)
            $candidate = '{0}.{1}.{2}.{3}' -f (($candidateNumber -shr 24) -band 255), (($candidateNumber -shr 16) -band 255), (($candidateNumber -shr 8) -band 255), ($candidateNumber -band 255)
            if ($candidate -ne $interface.IPAddress) { [void]$candidates.Add($candidate) }
        }
    }
    $candidates
}

function Find-AdbNetworkDevices {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $null = Invoke-BridgeAdb -Config $Config -Arguments @('start-server')
    $known = New-Object System.Collections.Generic.HashSet[string]
    $mdns = Invoke-BridgeAdb -Config $Config -Arguments @('mdns', 'services')
    foreach ($match in [regex]::Matches($mdns.StdOut, '(?<host>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d{1,5})')) {
        $hostAddress = $match.Groups['host'].Value
        $endpoint = $match.Value
        if ((Test-PrivateIPv4Address -Address $hostAddress) -and $endpoint -match ':(?:\d+)$') { [void]$known.Add($endpoint) }
    }

    # Legacy ADB-over-TCP devices may not advertise mDNS. Probe only the
    # directly connected private IPv4 subnet, only on the conventional ADB port.
    foreach ($address in (Get-LocalAdbCandidates)) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $pending = $client.BeginConnect($address, 5555, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne(120, $false) -and $client.Connected) { [void]$known.Add("${address}:5555") }
        } catch { } finally { $client.Close() }
    }

    foreach ($endpoint in $known) {
        $connected = Invoke-BridgeAdb -Config $Config -Arguments @('connect', $endpoint) -TimeoutSeconds 10
        if ($connected.ExitCode -ne 0) { Write-Verbose "ADB could not connect to ${endpoint}: $($connected.StdErr)" }
    }

    @(Get-AdbDeviceInventory -Config $Config | Where-Object { $_.Transport -eq 'Network' -and $_.State -eq 'device' })
}

function Get-AdbSetupGuidance {
    [CmdletBinding()]
    param([ValidateSet('Missing', 'Unauthorized', 'Offline')][string]$State = 'Missing')
    switch ($State) {
        'Unauthorized' { return @('ADB found a TV, but this PC is not authorized.', 'Unlock the TV and accept the debugging authorization prompt, then scan again.') }
        'Offline' { return @('ADB found a TV that is offline.', 'Check that the TV and PC are on the same Wi-Fi and scan again.') }
        default { return @('No reachable Android TV ADB device was found.', 'On the TV, enable Developer Options and ADB debugging. Enable Wireless debugging or ADB-over-network if your TV exposes that setting, then authorize this PC if prompted.', 'Keep the TV and PC on the same non-guest Wi-Fi. This app cannot turn on or pair ADB remotely.') }
    }
}

Export-ModuleMember -Function Get-AdbDeviceInventory, Find-AdbNetworkDevices, Get-AdbSetupGuidance, Test-PrivateIPv4Address, Get-LocalAdbCandidates, Invoke-BridgeAdb
