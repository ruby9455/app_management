$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulesRoot = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'Modules'
Import-Module -Force (Join-Path $modulesRoot 'NetworkHelpers.psm1')

function Assert-IsArray($value, $message) {
    if ($null -eq $value -or ($value.GetType().Name -ne 'Object[]' -and -not ($value -is [array]))) {
        throw "Assert-IsArray failed: $message"
    }
}

function Assert-IsBool($value, $message) {
    if ($null -eq $value -or $value.GetType().Name -ne 'Boolean') {
        throw "Assert-IsBool failed: $message"
    }
}

Write-Host 'Test: Get-ListeningPidsForPort returns without error and yields list-like output when available'
$result = $null
try { $result = Get-ListeningPidsForPort -Port 1 } catch { throw "Get-ListeningPidsForPort threw unexpectedly: $($_.Exception.Message)" }
if ($null -ne $result) { Assert-IsArray $result 'Expected list-like output from Get-ListeningPidsForPort' }

Write-Host 'Test: Wait-ForPortToBeFree returns boolean quickly for high port'
$ok = Wait-ForPortToBeFree -Port 65000 -TimeoutSeconds 1 -PollIntervalMs 100
Assert-IsBool $ok 'Expected a boolean from Wait-ForPortToBeFree'

Write-Host 'NetworkHelpers tests completed.' -ForegroundColor Green
