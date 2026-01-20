# Simple smoke test for ConfigHelpers
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$modules = Join-Path $root 'Modules'
Import-Module -Force (Join-Path $modules 'AppHelpers.psm1')
Import-Module -Force (Join-Path $modules 'ConfigHelpers.psm1')

$scriptRoot = $root
$jsonPath = Get-AppsJsonFilePath -ScriptRoot $scriptRoot
$examplePath = Join-Path $scriptRoot 'apps_example.json'

# Initialize file doesn't throw
Initialize-AppsJsonFile -JsonFilePath $jsonPath -ExamplePath $examplePath

# Get should return array (possibly empty)
$apps = Get-AppsFromJson -JsonFilePath $jsonPath
if ($apps -eq $null) { throw 'Read-AppsFromJson returned null' }

# Initialize editable should set global:apps
$editable = Initialize-EditableApps -Apps $apps
if (-not (Get-Variable -Name apps -Scope Global -ErrorAction SilentlyContinue)) { throw 'global:apps not set' }

Write-Host 'ConfigHelpers smoke tests completed.'
