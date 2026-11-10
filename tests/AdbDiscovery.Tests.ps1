Import-Module (Join-Path $PSScriptRoot '../src/Modules/AdbDiscovery.psm1') -Force

Describe 'ADB discovery safety and guidance' {
    It 'accepts RFC1918 and link-local addresses only' {
        (Test-PrivateIPv4Address '192.168.1.20') | Should Be $true
        (Test-PrivateIPv4Address '10.0.0.10') | Should Be $true
        (Test-PrivateIPv4Address '172.31.0.2') | Should Be $true
        (Test-PrivateIPv4Address '8.8.8.8') | Should Be $false
        (Test-PrivateIPv4Address '172.32.0.2') | Should Be $false
    }

    It 'rejects preconnected public and invalid network ADB targets' {
        Mock Invoke-BridgeAdb { [pscustomobject]@{ ExitCode = 0; StdOut = "List of devices attached`n8.8.8.8:5555 device model:remote`n192.168.1.8:5555 device model:tv`n192.168.1.9:99999 device model:bad`n"; StdErr = '' } } -ModuleName AdbDiscovery
        $devices = @(Get-AdbDeviceInventory -Config ([pscustomobject]@{}))
        ($devices | Where-Object { $_.Serial -eq '8.8.8.8:5555' }).Transport | Should Be 'External'
        ($devices | Where-Object { $_.Serial -eq '192.168.1.9:99999' }).Transport | Should Be 'External'
        ($devices | Where-Object { $_.Serial -eq '192.168.1.8:5555' }).Transport | Should Be 'Network'
    }

    It 'does not claim it can pair or enable ADB remotely' {
        $guidance = Get-AdbSetupGuidance -State Missing
        ($guidance -join ' ') | Should Match 'cannot turn on or pair ADB remotely'
    }

    It 'explains authorization separately from missing devices' {
        $guidance = Get-AdbSetupGuidance -State Unauthorized
        ($guidance -join ' ') | Should Match 'accept the debugging authorization prompt'
    }
}
