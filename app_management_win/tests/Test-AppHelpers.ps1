# Requires -Version 7.0
# Minimal tests for AppHelpers functions

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulesRoot = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'Modules'
Import-Module -Force (Join-Path $modulesRoot 'AppHelpers.psm1')

function Assert-Equal($expected, $actual, $message) {
    if ($expected -ne $actual) {
        throw "Assert-Equal failed: $message`nExpected: $expected`nActual:   $actual"
    }
}

Write-Host 'Test: Normalize-AppsList filters unsupported types and dedupes by Name'
$apps = @(
    [pscustomobject]@{ Name='App1'; Type='Streamlit' },
    [pscustomobject]@{ Name='APP1'; Type='Streamlit' },
    [pscustomobject]@{ Name='Other'; Type='OtherType' }
)
$result = ConvertTo-NormalizedAppsList -Apps $apps
Assert-Equal 1 $result.Count 'Expected only one Streamlit app after dedupe and filtering'
Assert-Equal 'App1' $result[0].Name 'Expected first unique Name preserved'

Write-Host 'Test: Get-PackageManager returns uv when pyproject.toml is present'
$tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP (New-Guid)) -Force
try {
    $pyproj = Join-Path $tmp.FullName 'pyproject.toml'
    Set-Content -Path $pyproj -Value "[project]\nname = 'demo'"
    $pm = Get-PackageManager -ProjectDirectory $tmp.FullName
    Assert-Equal 'uv' $pm 'Expected uv when pyproject.toml exists'
} finally {
    Remove-Item -Recurse -Force $tmp.FullName
}

Write-Host 'Test: Get-PackageManager returns pip when pyproject.toml is absent'
$tmp2 = New-Item -ItemType Directory -Path (Join-Path $env:TEMP (New-Guid)) -Force
try {
    $pm2 = Get-PackageManager -ProjectDirectory $tmp2.FullName
    Assert-Equal 'pip' $pm2 'Expected pip when pyproject.toml is missing'
} finally {
    Remove-Item -Recurse -Force $tmp2.FullName
}

Write-Host 'All tests passed.' -ForegroundColor Green
