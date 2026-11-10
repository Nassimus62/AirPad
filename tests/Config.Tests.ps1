Import-Module (Join-Path $PSScriptRoot '../src/Modules/Config.psm1') -Force

Describe 'Get-BridgeConfig' {
    It 'roots the project at the checked-out folder and keeps runtime data under LocalAppData' {
        $config = Get-BridgeConfig
        $config.Root | Should Be (Split-Path -Parent $PSScriptRoot)
        (Test-Path -LiteralPath (Join-Path $config.Root 'src/AirPad.ps1')) | Should Be $true
        $config.DataRoot | Should Be (Join-Path $env:LOCALAPPDATA 'AirPad')
        $config.LegacyRecoveryPath | Should Be (Join-Path $env:LOCALAPPDATA 'AndroidTvControllerBridge/state/recovery.json')
        (Test-Path -LiteralPath $config.ManifestPath) | Should Be $true
    }

    It 'pins the scrcpy release and checksum' {
        $config = Get-BridgeConfig
        $config.Manifest.scrcpy.version | Should Be '5.0.1'
        $config.Manifest.scrcpy.sha256 | Should Match '^[a-f0-9]{64}$'
    }
}
