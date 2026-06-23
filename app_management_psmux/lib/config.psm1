# lib/config.psm1
# Mirrors config.sh - configuration and app loading helpers

# Defaults (can be overridden before importing)
$script:DEFAULT_NETWORK_URL_FALLBACK  = 'http://10.17.62.232'
$script:DEFAULT_EXTERNAL_URL_FALLBACK = 'http://203.1.252.70'
$script:EXTERNAL_IP_TIMEOUT_SEC       = 5

if (-not $global:PSMUX_SESSION_NAME)      { $global:PSMUX_SESSION_NAME      = 'app_manager' }
if (-not $global:LANDING_PAGE_ENABLED)    { $global:LANDING_PAGE_ENABLED    = $true }
if (-not $global:LANDING_PAGE_PORT)       { $global:LANDING_PAGE_PORT       = 1111 }
if (-not $global:LANDING_PAGE_WINDOW_NAME){ $global:LANDING_PAGE_WINDOW_NAME = '_Dashboard' }

function Get-AppsJsonPath {
    param([string]$ScriptDir = '.')
    $candidates = @(
        (Join-Path $ScriptDir 'apps.json'),
        (Join-Path (Split-Path $ScriptDir) 'apps.json'),
        (Join-Path (Get-Location) 'apps.json')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    throw "apps.json not found"
}

function Get-ExampleAppsJsonPath {
    param([string]$ScriptDir = '.')
    $candidates = @(
        (Join-Path $ScriptDir 'apps_example.json'),
        (Join-Path (Split-Path $ScriptDir) 'apps_example.json'),
        (Join-Path (Get-Location) 'apps_example.json')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Get-AppsFromJson {
    param([string]$JsonFile)
    $raw = Get-Content $JsonFile -Raw | ConvertFrom-Json
    $supported = @('Streamlit', 'Django', 'Dash', 'Flask')
    $filtered = @($raw | Where-Object {
        $_ -and (
            ($_.Type -and ($supported -contains $_.Type)) -or
            ($_.CustomCommand -and -not [string]::IsNullOrWhiteSpace($_.CustomCommand))
        )
    })
    # Dedupe by name (case-insensitive), keep first occurrence
    $seen = @{}
    $unique = @()
    foreach ($a in $filtered) {
        $key = $a.Name.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $unique += $a }
    }
    return $unique
}

function ConvertTo-AppHashtable {
    param($App)
    if ($App -is [hashtable]) { return $App }
    $ht = [ordered]@{}
    foreach ($p in $App.PSObject.Properties) { $ht[$p.Name] = $p.Value }
    return $ht
}

function Confirm-Action {
    param([string]$Message = 'Are you sure?')
    $response = Read-Host "$Message [y/N]"
    return ($response -imatch '^(y|yes)$')
}

Export-ModuleMember -Function @(
    'Get-AppsJsonPath',
    'Get-ExampleAppsJsonPath',
    'Get-AppsFromJson',
    'ConvertTo-AppHashtable',
    'Confirm-Action'
)
