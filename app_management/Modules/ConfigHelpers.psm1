Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ConfigHelpers.psm1 - centralize apps.json pathing, load/save, and in-memory state prep
# Depends on AppHelpers for ConvertTo-NormalizedAppsList and ConvertTo-Hashtable, Select-UniqueAppsByName

function Get-AppsJsonFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ScriptRoot
    )
    return (Join-Path $ScriptRoot 'apps.json')
}

function Initialize-AppsJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$JsonFilePath,
        [Parameter(Mandatory=$true)][string]$ExamplePath
    )
    if (-not (Test-Path $JsonFilePath)) {
        try {
            if (Test-Path $ExamplePath) {
                Copy-Item -Path $ExamplePath -Destination $JsonFilePath -Force
                Write-Host "Created apps.json from template: $ExamplePath"
            } else {
                '[]' | Out-File -FilePath $JsonFilePath -Encoding UTF8 -Force
                Write-Host "Created empty apps.json at: $JsonFilePath"
            }
        } catch {
            throw "Failed to create apps.json at ${JsonFilePath}: $($_.Exception.Message)"
        }
    }
}

function Get-AppsFromJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$JsonFilePath
    )
    $apps = Get-Content $JsonFilePath | ConvertFrom-Json
    return (ConvertTo-NormalizedAppsList -Apps $apps)
}

function Initialize-EditableApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][array]$Apps
    )
    $editable = @()
    foreach ($a in $Apps) { $editable += (ConvertTo-Hashtable -Object $a) }
    $editable = Select-UniqueAppsByName -Apps $editable
    $global:apps = $editable
    return $editable
}

function Save-AppsInteractive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$JsonFilePath,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][array]$EditableApps
    )
    $saveResponse = Read-Host ">>> Would you like to save the updated apps list to the JSON file? (y/n)"
    if ($saveResponse -ieq "yes" -or $saveResponse -ieq "y") {
        try {
            $EditableApps | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFilePath -Encoding UTF8
            Write-Host "Apps list saved successfully to $JsonFilePath."
            # reload from file (read-only view)
            $apps = Read-AppsFromJson -JsonFilePath $JsonFilePath
            # refresh editable list (deduped)
            $editable = Initialize-EditableApps -Apps $apps
            return [pscustomobject]@{ Apps = $apps; EditableApps = $editable }
        } catch {
            Write-Host "Failed to save file: $($_.Exception.Message)"
            return [pscustomobject]@{ Apps = $null; EditableApps = $EditableApps }
        }
    }
    return [pscustomobject]@{ Apps = $null; EditableApps = $EditableApps }
}

Export-ModuleMember -Function @(
    'Get-AppsJsonFilePath',
    'Initialize-AppsJsonFile',
    'Get-AppsFromJson',
    'Initialize-EditableApps',
    'Save-AppsInteractive'
)
