Import-Module (Join-Path $PSScriptRoot '../src/Modules/ConsoleUi.psm1') -Force

Describe 'Console selection' {
    It 'returns no selection for an invalid menu index' {
        Mock Read-Host { '0' } -ModuleName ConsoleUi
        $result = Read-BridgeSelection -Items @('TV A', 'TV B') -Prompt 'TV'
        $result | Should Be $null
    }

    It 'returns the selected item for a valid menu index' {
        Mock Read-Host { '2' } -ModuleName ConsoleUi
        $result = Read-BridgeSelection -Items @('TV A', 'TV B') -Prompt 'TV'
        $result | Should Be 'TV B'
    }
}
