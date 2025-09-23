# Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulesRoot = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'Modules'
Import-Module -Force (Join-Path $modulesRoot 'LaunchHelpers.psm1')
Import-Module -Force (Join-Path $modulesRoot 'TerminalHelpers.psm1')

function Assert-NotNullOrEmpty($value, $message){ if ([string]::IsNullOrEmpty([string]$value)) { throw $message } }
function Assert-True($cond, $message){ if (-not $cond) { throw $message } }

Write-Host 'Test: New-EncodedPwshCommand returns a base64 string'
$cmd = New-EncodedPwshCommand -WorkingDir $PSScriptRoot -WindowTitle 'Test' -RunCmd 'Write-Host "Hello"'
Assert-NotNullOrEmpty $cmd 'Expected a non-empty encoded command'

Write-Host 'Test: Get-PackageContext returns expected properties'
$tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP (New-Guid)) -Force
try {
	$ctx = Get-PackageContext -App ([pscustomobject]@{}) -WorkingDir $tmp.FullName
	Assert-True ($ctx.PSObject.Properties.Name -contains 'PackageManager') 'Missing PackageManager'
	Assert-True ($ctx.PSObject.Properties.Name -contains 'VenvActivate') 'Missing VenvActivate'
	Assert-True ($ctx.PSObject.Properties.Name -contains 'Bootstrap') 'Missing Bootstrap'
} finally { Remove-Item -Recurse -Force $tmp.FullName }

Write-Host 'Test: Start-AppsList DryRun does not throw'
$pwshPath = (Get-Command pwsh).Source
$dummy = [pscustomobject]@{ Name = 'Dummy'; Type='Streamlit'; AppPath = $PSScriptRoot; IndexPath = 'Test-LaunchHelpers.ps1'; Port = 12345 }
Start-AppsList -AppList @($dummy) -PwshPath $pwshPath -DryRun

Write-Host 'LaunchHelpers tests completed.' -ForegroundColor Green
