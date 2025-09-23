# Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulesRoot = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'Modules'
Import-Module -Force (Join-Path $modulesRoot 'TerminalHelpers.psm1')

Write-Host 'Test: Get-WindowsTerminalPath returns object with Available/Path'
$info = Get-WindowsTerminalPath
if ($null -eq $info -or $null -eq $info.Available) { throw 'Get-WindowsTerminalPath did not return expected object' }
Write-Host ("Windows Terminal available: {0}" -f $info.Available)

Write-Host 'Test: New-WindowsTerminalTab returns boolean and does not throw when WT missing'
$result = $false
try {
    $result = New-WindowsTerminalTab -Title 'TestTab' -StartingDirectory $PSScriptRoot -EncodedCommand 'VwA=' -PwshPath (Get-Command pwsh).Source
} catch {
    throw "New-WindowsTerminalTab threw unexpectedly: $($_.Exception.Message)"
}
Write-Host ("New-WindowsTerminalTab returned: {0}" -f $result)

Write-Host 'TerminalHelpers smoke tests completed.' -ForegroundColor Green
