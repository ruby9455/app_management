<#!
.SYNOPSIS
Launch Streamlit, Django, and Dash apps from apps.json, each in a new Windows Terminal tab (or new PowerShell window), with the tab titled as the app name.

.DESCRIPTION
Reads apps from apps.json (same folder as this script). For every app with Type == "Streamlit", "Django", "Dash", or "Flask",
opens a new Windows Terminal tab titled with the app Name and runs either:
  - uv:  uv run streamlit run <IndexPath> --server.port <Port> [--server.baseUrlPath <BasePath>]
  - pip: [activate venv if VenvPath provided]; streamlit run <IndexPath> --server.port <Port> [--server.baseUrlPath <BasePath>]
For Type == "Django":
    - uv:  uv run <manage.py> runserver [127.0.0.1:<Port>]
    - pip: [activate venv if VenvPath provided]; py <manage.py> runserver [127.0.0.1:<Port>]
For Type == "Dash":
  - uv:  uv run python <IndexPath> --server.port <Port>
  - pip: [activate venv if VenvPath provided]; python <IndexPath> --server.port <Port>
  IndexPath is required.
For Type == "Flask":
  - uv:  set FLASK_APP=<IndexPath> and FLASK_ENV=development; uv run flask run --host=0.0.0.0 --port <Port>
  - pip: [activate venv if VenvPath provided]; set FLASK_APP and FLASK_ENV; flask run --host=0.0.0.0 --port <Port>
Detection order: explicit app.PackageManager, otherwise pyproject.toml → uv, else pip. If Windows Terminal is not found, a new PowerShell window is opened instead.

.PARAMETER AppName
Optional. If provided, only launch the app whose Name matches (case-insensitive).

.
.PARAMETER DryRun
If set, prints what would be executed without launching any terminals or killing processes.

.PARAMETER AutoStart
If set with `-AppName`, starts the app immediately without showing the interactive menu.

.EXAMPLE
./run_apps_tab_html.ps1

.EXAMPLE
./run_apps_tab_html.ps1 -AppName "REDCap" -AutoStart
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AppName,
    [switch]$DryRun,
    [switch]$AutoStart
)

# Requires -Version 7.0
# Requires -Modules AppHelpers, TerminalHelpers, UrlHelpers, Dashboard, NetworkHelpers, LaunchHelpers

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import helper modules (relative to this script, under Modules)
try {
    $modulesRoot = Join-Path $PSScriptRoot 'Modules'
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'AppHelpers.psm1')
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'TerminalHelpers.psm1')
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'UrlHelpers.psm1')
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'Dashboard.psm1')
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'NetworkHelpers.psm1')
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'LaunchHelpers.psm1')
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'ProcessHelpers.psm1')
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'ConfigHelpers.psm1')
    # Ensure modules are loaded by name for subsequent calls
    if (-not (Get-Module -Name UrlHelpers)) { Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'UrlHelpers.psm1') }
    if (-not (Get-Module -Name Dashboard)) { Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'Dashboard.psm1') }
} catch {
    throw "Failed to import helper modules from '$modulesRoot'. Please run the script from the repo root or ensure the Modules folder exists. Error: $($_.Exception.Message)"
}

# =============================
# Configuration
# -----------------------------
# Central place to tune fallback URLs and timeouts used by URL detection.
$script:DEFAULT_NETWORK_URL_FALLBACK  = 'http://10.17.62.232'
$script:DEFAULT_EXTERNAL_URL_FALLBACK = 'http://203.1.252.70'
$script:EXTERNAL_IP_TIMEOUT_SEC       = 5

# URL helpers moved to UrlHelpers.psm1

# Resolve pwsh path
$pwshCmd = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue
if (-not $pwshCmd) {
    throw "'pwsh' was not found in PATH. Please ensure PowerShell 7+ is installed."
}
$pwshPath = $pwshCmd.Source

# Detect URL prefixes
$script:networkUrlPrefix = Get-NetworkUrlPrefix
$script:externalUrlPrefix = Get-ExternalUrlPrefix

Write-Host "Detected Network URL prefix: $script:networkUrlPrefix"
Write-Host "Detected External URL prefix: $script:externalUrlPrefix"

## Load apps.json via ConfigHelpers
$jsonFilePath = Get-AppsJsonFilePath -ScriptRoot $PSScriptRoot
$examplePath = Join-Path $PSScriptRoot 'apps_example.json'
Write-Host "Reading apps from: $jsonFilePath"
Initialize-AppsJsonFile -JsonFilePath $jsonFilePath -ExamplePath $examplePath
$apps = Get-AppsFromJson -JsonFilePath $jsonFilePath

if ($AppName) {
    $apps = $apps | Where-Object { $_.Name -ieq $AppName }
    if (-not $apps -or $apps.Count -eq 0) {
        throw "App '$AppName' not found or not a Streamlit app in apps.json."
    }
}

if (-not $apps -or $apps.Count -eq 0) {
    Write-Host "No supported apps found in apps.json. Opening menu so you can add one."
}

## Save global apps back to JSON (interactive) via ConfigHelpers
function Update-Json {
    $result = Save-AppsInteractive -JsonFilePath $jsonFilePath -EditableApps $global:apps
    if ($null -ne $result -and $null -ne $result.Apps) {
        $script:apps = $result.Apps
        $global:apps = $result.EditableApps
    }
}

# Sync $apps (read-only list) and $global:apps (mutable list for CRUD)
Initialize-EditableApps -Apps $apps | Out-Null

## Update-AppRepo and Update-Venv are provided by AppHelpers.psm1

# Update an app (repo + venv + restart)
function Update-App {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )
    
    $name = $App.Name
    Write-Host "===== Update App '$name' ====="
    
    # Stop the app first
    Stop-AppByConfig -App $App
    # If the app has a port, wait briefly for it to free up
    if (Test-FieldHasValue -Object $App -Name 'Port') {
        $null = Wait-ForPortToBeFree -Port ([int](Get-FieldValue -Object $App -Name 'Port')) -TimeoutSeconds 10
    }

    # Update repo
    Update-AppRepo -App $App
    
    # Update virtual environment
    Update-Venv -App $App
    
    # Ensure the port is still free after updates (just in case background tasks spawned)
    if (Test-FieldHasValue -Object $App -Name 'Port') {
        $null = Wait-ForPortToBeFree -Port ([int](Get-FieldValue -Object $App -Name 'Port')) -TimeoutSeconds 10
    }

    # Give Windows Terminal time to display the "Press ENTER to continue" prompt
    Start-Sleep -Milliseconds 300

    # Bring the existing tab to the foreground and send Enter to trigger restart in-place
    Write-Host "Triggering restart in existing tab for '$name'..."
    if (-not $DryRun) { Invoke-AppTabEnter -Title $name }
    # Best-effort: a second Enter shortly after, in case the first hit a transient state
    Start-Sleep -Milliseconds 200
    if (-not $DryRun) { Invoke-AppTabEnter -Title $name }
}

# Show apps and helper to select by name or index (uses current list)
function Show-AppsTab {
    Write-Host "===== All available apps ====="
    $sorted = Get-CurrentAppsList
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $name = Get-FieldValue -Object $sorted[$i] -Name 'Name'
        Write-Host ("{0}: {1}" -f ($i+1), $name)
    }
    return $sorted
}

# Generate HTML dashboard
function Generate-HtmlDashboard {
    Write-Host "===== Generating HTML Dashboard ====="
    $currentApps = Get-CurrentAppsList
    $networkUrlPrefix = Get-NetworkUrlPrefix
    $externalUrlPrefix = Get-ExternalUrlPrefix
    Write-Host "Detected Network URL prefix: $networkUrlPrefix"
    Write-Host "Detected External URL prefix: $externalUrlPrefix"
    $html = New-AppDashboardHtml -Apps $currentApps -NetworkUrlPrefix $networkUrlPrefix -ExternalUrlPrefix $externalUrlPrefix
    $htmlFilePath = "$PSScriptRoot\app_index.html"
    $html | Out-File -FilePath $htmlFilePath -Encoding UTF8
    Write-Host "HTML dashboard saved to: $htmlFilePath"
    Write-Host "You can open this file in your browser or serve it with any web server."
    Write-Host "To serve it with Python: python -m http.server 1234"
    Write-Host "To serve it with PowerShell: .\generate_app_index.ps1"
    return $htmlFilePath
}

function Get-AppByNameOrIndexTab {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputValue,
        [Parameter(Mandatory = $true)]
        [array]$AppList
    )
    if ($InputValue -match '^\d+$') {
        $idx = [int]$InputValue - 1
        if ($idx -ge 0 -and $idx -lt $AppList.Count) { return $AppList[$idx] }
        Write-Host "Invalid index. Please enter a number between 1 and $($AppList.Count)."
        return $null
    } else {
        $app = $AppList | Where-Object { (Get-FieldValue -Object $_ -Name 'Name') -ieq $InputValue }
        if ($null -eq $app) { Write-Host "App '$InputValue' not found."; return $null }
        return $app
    }
}

## Launch helpers are now provided by LaunchHelpers.psm1

function Show-MainMenu {
    while ($true) {
        Write-Output "=============================="
        Write-Output "Select an option:"
        Write-Output "1. Start all apps"
        Write-Output "2. Restart an app"
        Write-Output "3. Start an app"
        Write-Output "4. Stop an app"
        Write-Output "5. Update an app from repo"
        Write-Output "6. Add a new app to apps.json"
        Write-Output "7. Update an app in apps.json"
        Write-Output "8. Remove an app from apps.json"
        Write-Output "9. Save the apps list to apps.json"
        Write-Output "10. Generate/Update HTML Dashboard"
        Write-Output "0. Close all idle app tabs"
        Write-Output "=============================="
        $option = Read-Host "Enter option"

        switch ($option) {
            1 {
                $listAll = Get-CurrentAppsList
                Start-AppsList -AppList $listAll -PwshPath $pwshPath -DryRun:$DryRun
            }
            2 {
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to restart (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -ne $appSel) {
                    # Stop the app's running process and wait for the port to be free
                    Stop-AppByConfig -App $appSel
                    if (Test-FieldHasValue -Object $appSel -Name 'Port') {
                        $null = Wait-ForPortToBeFree -Port ([int](Get-FieldValue -Object $appSel -Name 'Port')) -TimeoutSeconds 10
                    }
                    Start-Sleep -Milliseconds 300
                    # Trigger restart in the same tab by sending Enter
                    $targetName = Get-FieldValue -Object $appSel -Name 'Name'
                    Invoke-AppTabEnter -Title $targetName
                }
            }
            3 {
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to start (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -ne $appSel) {
                    Start-AppsList -AppList @($appSel) -PwshPath $pwshPath -DryRun:$DryRun
                }
            }
            4 {
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to stop (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -ne $appSel) {
                    Stop-AppByConfig -App $appSel
                }
            }
            5 {
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to update (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -ne $appSel) {
                    Update-App -App $appSel -DryRun:$DryRun
                }
            }
            6 {
                # Add app
                Write-Host "===== Add App Setting ====="
                $appPath = Read-Host ">>> Enter app path (or 'back' to cancel)"
                if ($appPath -ieq 'back') { continue }
                $defaultName = Split-Path -Path $appPath -Leaf
                $appName = Read-Host "Default app name: $defaultName (press Enter to keep or enter new)"
                if (-not $appName) { $appName = $defaultName }
                # Guard: prevent duplicate names (case-insensitive)
                $exists = ($global:apps | Where-Object { (Get-FieldValue -Object $_ -Name 'Name') -ieq $appName })
                if ($exists) {
                    Write-Host "An app named '$appName' already exists. Please choose a different name."
                    break
                }

                $appType = Get-AppType -ProjectDirectory $appPath
                if (-not $appType -or $appType -eq 'Unknown Application Type') {
                    $appType = Read-Host ">>> Enter app type, Streamlit/Django/Flask/Dash (s/d/f/da)"
                }
                $packageManager = Get-PackageManager -ProjectDirectory $appPath
                Write-Host "Detected package manager: $packageManager"

                $venvDirectory = Find-Venv -ProjectDirectory $appPath
                if ($venvDirectory) {
                    $venvPath = Join-Path -Path $appPath -ChildPath $venvDirectory
                } else {
                    $pyprojectFile = Join-Path $appPath "pyproject.toml"
                    if (Test-Path $pyprojectFile) {
                        Write-Host "No venv detected. Found pyproject.toml; running 'uv sync'..."
                        Push-Location $appPath; uv sync; Pop-Location
                        $venvDirectory = Find-Venv -ProjectDirectory $appPath
                        if ($venvDirectory) { $venvPath = Join-Path -Path $appPath -ChildPath $venvDirectory } else { $venvPath = "" }
                    } else {
                        $venvPath = Get-VenvDirectory
                    }
                }

                $indexPath = $null
                if ($appType -ieq "streamlit" -or $appType -ieq "flask" -or $appType -ieq "dash") {
                    $indexPath = Get-IndexPyFile -ProjectDirectory $appPath
                }

                $newApp = [hashtable]@{
                    Name = $appName
                    Type = $appType
                    PackageManager = $packageManager
                    VenvPath = $venvPath
                    AppPath = $appPath
                    IndexPath = $indexPath
                    Port = Get-PortNumber
                }

                if (-not $global:apps) { $global:apps = @(@($newApp)) } else { $global:apps += $newApp }
                Write-Output "App '$appName' added successfully."
                Update-Json
            }
            7 {
                # Update app settings
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to update settings (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -eq $appSel) { continue }

                $app = ConvertTo-Hashtable -Object $appSel
                $nameForIndex = Get-FieldValue -Object $appSel -Name 'Name'
                $updated = $false

                $currName = Get-FieldValue -Object $app -Name 'Name'
                Write-Host "Current app name: $currName"
                $newAppName = Read-Host ">>> Enter app name (press Enter to keep)"
                if ($newAppName -and $newAppName -cne $currName) { Set-FieldValue -Object $app -Name 'Name' -Value $newAppName; $updated = $true }

                $appPathVal = Get-FieldValue -Object $app -Name 'AppPath'
                $detectedType = Get-AppType -ProjectDirectory $appPathVal
                $currType = Get-FieldValue -Object $app -Name 'Type'
                Write-Host "Current type: $currType | Detected: $detectedType"
                if ($detectedType -and $detectedType -ne 'Unknown Application Type' -and $detectedType -ne $currType) {
                    $ans = Read-Host ">>> Update type to '$detectedType'? (y/n)"
                    if ($ans -match '^(?i:y|yes)$') { Set-FieldValue -Object $app -Name 'Type' -Value $detectedType; $updated = $true }
                }
                $manualType = Read-Host ">>> Or manually enter type Streamlit/Django/Flask/Dash (press Enter to keep)"
                if ($manualType) { Set-FieldValue -Object $app -Name 'Type' -Value $manualType; $updated = $true }

                $detectedPM = Get-PackageManager -ProjectDirectory $appPathVal
                $currPM = Get-FieldValue -Object $app -Name 'PackageManager'
                $currentPM = if ($currPM) { $currPM } else { 'Not set' }
                Write-Host "Current package manager: $currentPM | Detected: $detectedPM"
                if (-not $currPM) { Set-FieldValue -Object $app -Name 'PackageManager' -Value $detectedPM; $updated = $true }
                elseif ($detectedPM -ne $currPM) {
                    $ans = Read-Host ">>> Update package manager to '$detectedPM'? (y/n)"
                    if ($ans -match '^(?i:y|yes)$') { Set-FieldValue -Object $app -Name 'PackageManager' -Value $detectedPM; $updated = $true }
                }

                $currAppPath = Get-FieldValue -Object $app -Name 'AppPath'
                Write-Host "Current app path: $currAppPath"
                $newPath = Read-Host ">>> Enter app path (press Enter to keep)"
                if ($newPath) { Set-FieldValue -Object $app -Name 'AppPath' -Value $newPath; $updated = $true }

                $typeVal = Get-FieldValue -Object $app -Name 'Type'
                if ($typeVal -ieq 'streamlit' -or $typeVal -ieq 'flask' -or $typeVal -ieq 'dash') {
                    $currIndex = Get-FieldValue -Object $app -Name 'IndexPath'
                    Write-Host "Current index path: $currIndex"
                    $newIndex = Read-Host ">>> Enter index path (press Enter to keep)"
                    if ($newIndex) { Set-FieldValue -Object $app -Name 'IndexPath' -Value $newIndex; $updated = $true }
                } elseif ($typeVal -ieq 'django') {
                    $hasIndex = Get-FieldValue -Object $app -Name 'IndexPath'
                    if ($hasIndex) {
                        if ($app -is [hashtable]) { $null = $app.Remove('IndexPath') } else { $app.PSObject.Properties.Remove('IndexPath') }
                        $updated = $true
                    }
                }

                $currVenv = Get-FieldValue -Object $app -Name 'VenvPath'
                Write-Host "Current venv path: $currVenv"
                $chgVenv = Read-Host ">>> Update venv path? (y/n)"
                if ($chgVenv -match '^(?i:y|yes)$') {
                    $newVenv = Get-VenvDirectory
                    if ($newVenv) { Set-FieldValue -Object $app -Name 'VenvPath' -Value $newVenv; $updated = $true }
                }

                $currPort = Get-FieldValue -Object $app -Name 'Port'
                Write-Host "Current port: $currPort"
                $chgPort = Read-Host ">>> Update port? (y/n)"
                if ($chgPort -match '^(?i:y|yes)$') {
                    $newPort = Get-PortNumber
                    if ($newPort) { Set-FieldValue -Object $app -Name 'Port' -Value $newPort; $updated = $true }
                }

                if ($updated) {
                    # Update the correct entry by original object identity when possible, fallback to name match
                    $replaced = $false
                    for ($i = 0; $i -lt $global:apps.Count; $i++) {
                        if ((Get-FieldValue -Object $global:apps[$i] -Name 'Name') -ieq $nameForIndex) { $global:apps[$i] = $app; $replaced = $true; break }
                    }
                    if (-not $replaced) {
                        # If not found by name (renamed), replace by new name or append
                        for ($i = 0; $i -lt $global:apps.Count; $i++) {
                            $currAppName = Get-FieldValue -Object $app -Name 'Name'
                            if ((Get-FieldValue -Object $global:apps[$i] -Name 'Name') -ieq $currAppName) { $global:apps[$i] = $app; $replaced = $true; break }
                        }
                        if (-not $replaced) { $global:apps += $app }
                    }
                    Write-Host "App '$nameForIndex' updated successfully."
                    Update-Json
                } else { Write-Host "No changes made." }
            }
            8 {
                # Remove app
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to remove (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -eq $appSel) { continue }
                $name = Get-FieldValue -Object $appSel -Name 'Name'
                $global:apps = $global:apps | Where-Object { (Get-FieldValue -Object $_ -Name 'Name') -ine $name }
                Write-Host "App '$name' removed successfully."
                Update-Json
            }
            9 {
                Update-Json
            }
            10 {
                Generate-HtmlDashboard
            }
            0 {
                Close-AllIdleAppTabs
            }
            Default { Write-Output "Invalid option. Try again." }
        }
    }
    return
}

# Interactive menu if no parameters supplied
$invokedWithParams = $PSBoundParameters.ContainsKey('AppName')
if (-not $invokedWithParams) {
    Show-MainMenu
} elseif ($AutoStart) {
    Start-AppsList -AppList $apps -PwshPath $pwshPath -DryRun:$DryRun
} else {
    # If AppName was passed without AutoStart, show the menu filtered to the one app
    Show-MainMenu
}
