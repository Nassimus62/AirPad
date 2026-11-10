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
