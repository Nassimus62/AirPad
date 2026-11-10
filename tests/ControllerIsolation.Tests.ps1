Import-Module (Join-Path $PSScriptRoot '../src/Modules/ControllerIsolation.psm1') -Force

Describe 'Controller isolation boundary' {
    It 'discovers a generic controller by gamepad HID usage, not its marketing name' {
        $json = '[{"friendlyName":"USB Input Device","devices":[{"present":true,"gamingDevice":true,"deviceInstancePath":"HID\\VID_0001&PID_0002\\ABC","baseContainerDeviceInstancePath":"USB\\VID_0001&PID_0002\\ABC","xusbDeviceInstancePath":""}]}]'
        Mock Invoke-HidHideCli { [pscustomobject]@{ ExitCode = 0; StdOut = '[{"friendlyName":"USB Input Device","devices":[{"present":true,"gamingDevice":true,"deviceInstancePath":"HID\\VID_0001&PID_0002\\ABC","baseContainerDeviceInstancePath":"USB\\VID_0001&PID_0002\\ABC","xusbDeviceInstancePath":""},{"present":true,"gamingDevice":true,"deviceInstancePath":"HID\\VID_0001&PID_0002\\ABC&MI_01","baseContainerDeviceInstancePath":"USB\\VID_0001&PID_0002\\ABC","xusbDeviceInstancePath":""}]}]'; StdErr = '' } } -ModuleName ControllerIsolation
        $controllers = @(Get-BridgeControllerInventory -Config ([pscustomobject]@{}))
        $controllers.Count | Should Be 1
        $controllers[0].Name | Should Be 'USB Input Device'
        ($controllers[0].InstanceIds -contains 'HID\VID_0001&PID_0002\ABC') | Should Be $true
        ($controllers[0].InstanceIds -contains 'USB\VID_0001&PID_0002\ABC') | Should Be $true
        ($controllers[0].InstanceIds -contains 'HID\VID_0001&PID_0002\ABC&MI_01') | Should Be $true
    }

    It 'does not claim controller isolation is available when HidHide is missing' {
        $config = [pscustomobject]@{ DependencyRoot = Join-Path $TestDrive 'missing'; DataRoot = $TestDrive }
        (Test-HidHideReady -Config $config) | Should Be $false
    }
}
