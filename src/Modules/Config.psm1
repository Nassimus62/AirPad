Set-StrictMode -Version Latest

function Get-BridgeConfig {
    [CmdletBinding()]
    param()

    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $dataRoot = Join-Path $env:LOCALAPPDATA 'AirPad'
    $legacyRecoveryPath = Join-Path $env:LOCALAPPDATA 'AndroidTvControllerBridge/state/recovery.json'
    $manifestPath = Join-Path $root 'config/dependencies.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    [pscustomobject]@{
        Root = $root
        DataRoot = $dataRoot
        DependencyRoot = Join-Path $dataRoot 'dependencies'
        StateRoot = Join-Path $dataRoot 'state'
        LogRoot = Join-Path $dataRoot 'logs'
        ManifestPath = $manifestPath
        Manifest = $manifest
        RecoveryPath = Join-Path $dataRoot 'state/recovery.json'
        LegacyRecoveryPath = $legacyRecoveryPath
        ScrcpyAllowlistPath = Join-Path $dataRoot 'dependencies/scrcpy/scrcpy.exe'
    }
}

Export-ModuleMember -Function Get-BridgeConfig
