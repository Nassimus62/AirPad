Import-Module (Join-Path $PSScriptRoot '../src/Modules/Dependencies.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../src/Modules/AdbDiscovery.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../src/Modules/ControllerIsolation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../src/Modules/BridgeSession.psm1') -Force

Describe 'Bridge target validation' {
    It 'requires recovery before replacing prior session state' {
        $recovery = Join-Path $TestDrive 'recovery.json'
        Set-Content -LiteralPath $recovery -Value '{}'
        { Start-BridgeSession -Config ([pscustomobject]@{ RecoveryPath = $recovery }) -DeviceSerial '192.168.1.9:5555' -ControllerInstanceIds @('HID\\VID_0001') } | Should Throw
    }

    It 'requires recovery from the legacy app-data location before starting' {
        $recovery = Join-Path $TestDrive 'legacy-recovery.json'
        Set-Content -LiteralPath $recovery -Value '{}'
        $config = [pscustomobject]@{ RecoveryPath = (Join-Path $TestDrive 'new/recovery.json'); LegacyRecoveryPath = $recovery }
        { Start-BridgeSession -Config $config -DeviceSerial '192.168.1.9:5555' -ControllerInstanceIds @('HID\\VID_0001') } | Should Throw
    }

    It 'rejects non-network or unauthorized devices before controller isolation' {
        Mock Get-AdbDeviceInventory {
            @(
                [pscustomobject]@{ Serial = '192.168.1.9:5555'; State = 'unauthorized'; Transport = 'Network' },
                [pscustomobject]@{ Serial = 'USB123'; State = 'device'; Transport = 'Local/USB' }
            )
        } -ModuleName BridgeSession
        { Test-BridgeTarget -Config ([pscustomobject]@{}) -DeviceSerial '192.168.1.9:5555' } | Should Throw
        { Test-BridgeTarget -Config ([pscustomobject]@{}) -DeviceSerial 'USB123' } | Should Throw
    }
}

Describe 'Safe scrcpy teardown' {
    It 'retains isolation and recovery state when stopping scrcpy fails during recovery' {
        $recovery = Join-Path $TestDrive 'recovery-stop-failure.json'
        $state = [pscustomobject]@{
            ProcessId = 4321
            ScrcpyPath = 'C:\tools\scrcpy.exe'
            ControllerInstanceIds = @('HID\\VID_0001')
            DeviceStates = @()
            CloakWasOn = $true
            AppWasAllowed = $true
        }
        $state | ConvertTo-Json | Set-Content -LiteralPath $recovery
        $config = [pscustomobject]@{ RecoveryPath = $recovery }
        Mock Get-Process { [pscustomobject]@{ Id = 4321; ProcessName = 'scrcpy'; Path = 'C:\tools\scrcpy.exe' } } -ModuleName BridgeSession
        Mock Stop-Process { throw 'access denied' } -ModuleName BridgeSession
        Mock Wait-Process {} -ModuleName BridgeSession
        Mock Restore-BridgeControllerVisibility {} -ModuleName BridgeSession

        { Restore-InterruptedBridgeSession -Config $config } | Should Throw
        Assert-MockCalled Restore-BridgeControllerVisibility -Times 0 -ModuleName BridgeSession
        Test-Path -LiteralPath $recovery | Should Be $true
    }

    It 'retains isolation and recovery state when stopping scrcpy fails during normal teardown' {
        $recovery = Join-Path $TestDrive 'normal-stop-failure.json'
        Set-Content -LiteralPath $recovery -Value '{}'
        $config = [pscustomobject]@{ RecoveryPath = $recovery }
        $state = [pscustomobject]@{ ProcessId = 4321; ScrcpyPath = 'C:\tools\scrcpy.exe' }
        Mock Get-Process { [pscustomobject]@{ Id = 4321; ProcessName = 'scrcpy'; Path = 'C:\tools\scrcpy.exe' } } -ModuleName BridgeSession
        Mock Stop-Process { throw 'access denied' } -ModuleName BridgeSession
        Mock Wait-Process {} -ModuleName BridgeSession
        Mock Restore-BridgeControllerVisibility {} -ModuleName BridgeSession

        $global:AirPadTestConfig = $config
        $global:AirPadTestState = $state
        $result = InModuleScope BridgeSession {
            Complete-BridgeSession -Config $global:AirPadTestConfig -State $global:AirPadTestState -ProcessId 4321 -ScrcpyPath 'C:\tools\scrcpy.exe'
        }
        Remove-Variable AirPadTestConfig, AirPadTestState -Scope Global
        $result | Should Be $false
        Assert-MockCalled Restore-BridgeControllerVisibility -Times 0 -ModuleName BridgeSession
        Test-Path -LiteralPath $recovery | Should Be $true
    }
}
