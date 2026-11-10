[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Recover,
    [switch]$InstallDependencies
)

$ErrorActionPreference = 'Stop'
$moduleRoot = Join-Path $PSScriptRoot 'Modules'
foreach ($name in @('Config', 'Dependencies', 'AdbDiscovery', 'ControllerIsolation', 'BridgeSession', 'ConsoleUi')) {
    Import-Module (Join-Path $moduleRoot "$name.psm1") -Force
}

$config = Get-BridgeConfig

if ($Help) {
    Write-Host 'AirPad - Android TV controller bridge'
    Write-Host 'Usage: .\run.ps1 [-Help] [-InstallDependencies] [-Recover]'
    Write-Host 'Start with .\run.ps1 to open the interactive PowerShell menu.'
    exit 0
}

if ($InstallDependencies) {
    Install-BridgeDependencies -Config $config -IncludeDriver
    exit 0
}

if ($Recover) {
    Restore-InterruptedBridgeSession -Config $config
    exit 0
}

Start-BridgeMenu -Config $config
