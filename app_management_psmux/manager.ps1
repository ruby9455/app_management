<#
.SYNOPSIS
Interactive app manager for Windows using psmux (tmux on Windows).

.DESCRIPTION
Launch and manage Streamlit, Django, Dash, and Flask apps from apps.json.
Each app runs in a named psmux window that can be stopped/restarted.

.PARAMETER App
Start a specific app by name.

.PARAMETER All
Start all apps.

.PARAMETER DryRun
Show what would be executed without running.

.PARAMETER Attach
Attach to the psmux session.

.PARAMETER NoLanding
Skip auto-starting the landing page dashboard.

.EXAMPLE
.\manager.ps1                        # Interactive menu
.\manager.ps1 -App "My App"          # Start specific app
.\manager.ps1 -All                   # Start all apps
.\manager.ps1 -DryRun -All           # Preview what would run
.\manager.ps1 -Attach                # Attach to psmux session
.\manager.ps1 -NoLanding             # Start without dashboard

.NOTES
INTERACTIVE COMMANDS:
  Dashboard:
    D           Toggle landing page dashboard (start/stop)
  Manage apps:
    [number(s)] Start app(s) by index (e.g., 1,2,3) (0 for all)
    [name]      Start app by name
    s [num(s)]  Stop app(s) by index (e.g., 1,2,3) (0 for all)
    r [num(s)]  Restart app(s) by index (e.g., 1,2,3) (0 for all)
    u [num(s)]  Update app(s) from repo (e.g., 1,2,3) (0 for all)
  Edit apps.json:
    aa          Add a new app
    ap          Add a new process (custom command)
    e [num]     Edit by index
    d [num(s)]  Delete app(s) by index (e.g., 1,2,3)
  Psmux:
    l           List psmux windows
    t           Attach to psmux session
    t [num]     Attach and switch to app window
  Other:
    R           Refresh list
    q           Quit
#>

[CmdletBinding()]
param(
    [string]$App      = '',
    [switch]$All,
    [switch]$DryRun,
    [switch]$Attach,
    [switch]$NoLanding
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SCRIPT_DIR = $PSScriptRoot

# Mutable copy of NoLanding so the D toggle can re-enable the dashboard at runtime
$script:SkipLanding = $NoLanding.IsPresent

# Color variables (ANSI escape codes) - defined here so all functions in this
# script can reference them directly without crossing module scope boundaries.
$script:RED    = "`e[0;31m"
$script:GREEN  = "`e[0;32m"
$script:YELLOW = "`e[1;33m"
$script:BLUE   = "`e[0;34m"
$script:PURPLE = "`e[0;35m"
$script:CYAN   = "`e[0;36m"
$script:NC     = "`e[0m"

# Source helper libraries
$libDir = Join-Path $SCRIPT_DIR 'lib'
Import-Module -Force (Join-Path $libDir 'config.psm1')       -ErrorAction Stop
Import-Module -Force (Join-Path $libDir 'url_helpers.psm1')  -ErrorAction Stop
Import-Module -Force (Join-Path $libDir 'app_helpers.psm1')  -ErrorAction Stop
Import-Module -Force (Join-Path $libDir 'psmux_helpers.psm1') -ErrorAction Stop
Import-Module -Force (Join-Path $libDir 'json_helpers.psm1') -ErrorAction Stop

# ── Dependency check ──────────────────────────────────────────────────────────
function Test-Dependencies {
    $missing = @()
    if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) { $missing += 'psmux' }
    if (-not (Get-Command pwsh  -ErrorAction SilentlyContinue)) { $missing += 'pwsh' }
    if ($missing.Count -gt 0) {
        Write-Color $script:RED "Error: Missing required dependencies: $($missing -join ', ')"
        Write-Host "Install psmux from: https://github.com/nicowillis/psmux"
        exit 1
    }
}

# ── Load apps.json ────────────────────────────────────────────────────────────
$script:APPS_JSON  = $null   # array of PSCustomObjects
$script:APPS_COUNT = 0

function Invoke-LoadAppsJson {
    try {
        $jsonPath = Get-AppsJsonPath -ScriptDir $SCRIPT_DIR
    } catch {
        $examplePath = Get-ExampleAppsJsonPath -ScriptDir $SCRIPT_DIR
        $targetPath  = Join-Path $SCRIPT_DIR 'apps.json'
        if ($examplePath) {
            Write-Color $script:YELLOW "apps.json not found. Creating from apps_example.json..."
            Copy-Item $examplePath $targetPath -Force
            Write-Color $script:GREEN "Created: $targetPath"
            Write-Color $script:CYAN "Please edit apps.json with your actual app configurations."
        } else {
            Write-Color $script:RED "Error: Could not find apps.json or apps_example.json"
            exit 1
        }
        $jsonPath = $targetPath
    }

    Write-Color $script:CYAN "Loading apps from: $jsonPath"
    $script:APPS_JSON  = @(Get-AppsFromJson -JsonFile $jsonPath)
    $script:APPS_COUNT = $script:APPS_JSON.Count

    if ($script:APPS_COUNT -eq 0) {
        Write-Color $script:YELLOW "No supported apps found in apps.json"
    } else {
        Write-Color $script:GREEN "Found $($script:APPS_COUNT) supported apps"
    }
}

# ── Landing page ──────────────────────────────────────────────────────────────
function Start-LandingPage {
    if ($script:SkipLanding -or -not $global:LANDING_PAGE_ENABLED) { return }

    if (Test-PortInUse -Port $global:LANDING_PAGE_PORT) {
        Write-Color $script:CYAN "Dashboard already running on port $($global:LANDING_PAGE_PORT)"
        return
    }

    if ($DryRun) {
        Write-Color $script:YELLOW "[DryRun] Would start landing page dashboard on port $($global:LANDING_PAGE_PORT)"
        return
    }

    $landingScript = Join-Path $SCRIPT_DIR 'landing_page.ps1'
    if (-not (Test-Path $landingScript)) {
        Write-Color $script:YELLOW "Warning: landing_page.ps1 not found"
        return
    }

    Write-Color $script:GREEN "Starting landing page dashboard on port $($global:LANDING_PAGE_PORT)..."

    $pwsh = (Get-Command pwsh).Source
    Start-Process -FilePath $pwsh `
        -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $landingScript, '-Port', $global:LANDING_PAGE_PORT) `
        -WindowStyle Hidden

    # Wait up to 5 seconds for the port to open
    $attempts = 20
    while ($attempts -gt 0) {
        if (Test-PortInUse -Port $global:LANDING_PAGE_PORT) {
            Write-Color $script:GREEN "Dashboard running at http://localhost:$($global:LANDING_PAGE_PORT)"
            return
        }
        Start-Sleep -Milliseconds 250
        $attempts--
    }
    Write-Color $script:YELLOW "Dashboard started but port $($global:LANDING_PAGE_PORT) is not yet listening. Check landing_page.ps1 for errors."
}

function Stop-LandingPage {
    if ($DryRun) { Write-Color $script:YELLOW "[DryRun] Would stop landing page dashboard"; return }
    if (Test-PortInUse -Port $global:LANDING_PAGE_PORT) {
        Write-Color $script:CYAN "Stopping landing page dashboard..."
        Stop-Port -Port $global:LANDING_PAGE_PORT
        Write-Color $script:GREEN "Dashboard stopped"
    } else {
        Write-Color $script:YELLOW "Dashboard was not running"
    }
}

function Test-LandingPageRunning {
    return (Test-PortInUse -Port $global:LANDING_PAGE_PORT)
}

# ── Safe property access (strict-mode safe) ───────────────────────────────────
function Get-AppPort {
    # Returns the Port value if the property exists and is a positive integer, else $null.
    param($AppObj)
    if ($AppObj -is [hashtable]) {
        if ($AppObj.ContainsKey('Port')) { $p = $AppObj['Port'] } else { return $null }
    } else {
        if ($AppObj.PSObject.Properties.Name -notcontains 'Port') { return $null }
        $p = $AppObj.Port
    }
    if ($null -eq $p -or [string]::IsNullOrWhiteSpace([string]$p)) { return $null }
    try { $i = [int]$p; if ($i -gt 0) { return $i } } catch { }
    return $null
}

function Get-AppField {
    param($AppObj, [string]$Field)
    if ($AppObj -is [hashtable]) {
        if ($AppObj.ContainsKey($Field)) { return $AppObj[$Field] } else { return $null }
    }
    if ($AppObj.PSObject.Properties.Name -contains $Field) { return $AppObj.$Field }
    return $null
}

# ── App status ────────────────────────────────────────────────────────────────
function Test-AppRunning {
    param($AppObj)
    if (Test-PsmuxWindowExists -AppName $AppObj.Name) { return $true }
    $port = Get-AppPort -AppObj $AppObj
    if ($port -and (Test-PortInUse -Port $port)) { return $true }
    return $false
}

# ── Display ───────────────────────────────────────────────────────────────────
function Show-Apps {
    Write-Header "Available Apps"
    Write-TableHeader
    $index = 1
    foreach ($app in $script:APPS_JSON) {
        $name    = $app.Name
        $appType = Get-AppField $app 'Type'
        $appCmd  = Get-AppField $app 'CustomCommand'
        $type    = if ((-not $appType -or $appType -eq '') -and $appCmd) { 'Process' } else { if ($appType) { $appType } else { 'Unknown' } }
        $portVal = Get-AppPort -AppObj $app
        $port    = if ($portVal) { [string]$portVal } else { 'N/A' }
        $status  = if (Test-AppRunning -AppObj $app) { 'running' } else { 'stopped' }
        Write-AppInfo -Index $index -Name $name -Type $type -Port $port -Status $status
        $index++
    }
    Write-TableFooter
}

function Show-NetworkUrls {
    Write-Host ""
    Write-Color $script:CYAN "Detecting network configuration..."
    Write-Host "  Network URL:  $script:NETWORK_URL"
    Write-Host "  External URL: $script:EXTERNAL_URL"
    Write-Host "  Generic URL:  $script:GENERIC_URL"
    if (Test-LandingPageRunning) {
        Write-Color $script:GREEN "  Dashboard:    http://localhost:$($global:LANDING_PAGE_PORT) (running)"
    } else {
        Write-Color $script:YELLOW "  Dashboard:    Not running (press D to start)"
    }
}

# ── Start / Stop / Restart / Update ──────────────────────────────────────────
function Start-SingleApp {
    param($AppObj)
    $name      = $AppObj.Name
    $appPath   = $AppObj.AppPath
    $appType   = Get-AppField $AppObj 'Type'
    $port      = Get-AppPort -AppObj $AppObj
    $indexPath = Get-AppField $AppObj 'IndexPath'

    if (-not $name)    { Write-Color $script:RED "Error: App missing Name"; return }
    if (-not $appPath -or -not (Test-Path $appPath)) {
        Write-Color $script:RED "Error: AppPath not found: $appPath"; return
    }

    $isWebType = $appType -iin @('Streamlit', 'Flask', 'Dash')
    if ($isWebType -and $indexPath) {
        $fullIndex = if ([System.IO.Path]::IsPathRooted($indexPath)) { $indexPath } else { Join-Path $appPath $indexPath }
        if (-not (Test-Path $fullIndex)) {
            Write-Color $script:RED "Error: IndexPath not found: $fullIndex"; return
        }
    }

    $workingDir = (Resolve-Path $appPath).Path
    $appHt = ConvertTo-AppHashtable -App $AppObj

    try {
        $runCmd = Build-AppRunCommand -App $appHt -WorkingDir $workingDir
    } catch {
        Write-Color $script:RED "Error: Could not build run command for $name`: $($_.Exception.Message)"; return
    }

    if ($DryRun) {
        Write-Color $script:YELLOW "[DryRun] Would start '$name' in '$workingDir'"
        Write-Color $script:CYAN "  Command: $runCmd"
        return
    }

    if (Test-PsmuxWindowExists -AppName $name) {
        Write-Color $script:YELLOW "Warning: '$name' already has a psmux window"
        if (-not (Confirm-Action "Kill existing window and restart?")) {
            Write-Host "Skipping $name"; return
        }
        Remove-PsmuxWindow -AppName $name
        Start-Sleep -Seconds 1
    } elseif ($port -and (Test-PortInUse -Port $port)) {
        Write-Color $script:YELLOW "Warning: Port $port already in use"
        if (-not (Confirm-Action "Kill process on port $port and start?")) {
            Write-Host "Skipping $name"; return
        }
        Stop-Port -Port $port
        Wait-ForPortFree -Port $port -TimeoutSec 5 | Out-Null
    }

    Write-Color $script:GREEN "Starting '$name' in psmux..."
    New-PsmuxWindow -AppName $name -WorkingDir $workingDir -Command $runCmd | Out-Null
    Write-Color $script:GREEN "Launched '$name' in psmux window"
}

function Stop-SingleApp {
    param($AppObj)
    $name = $AppObj.Name
    $port = Get-AppPort -AppObj $AppObj

    if ($DryRun) { Write-Color $script:YELLOW "[DryRun] Would stop '$name'"; return }

    $stopped = $false
    if (Test-PsmuxWindowExists -AppName $name) {
        Write-Color $script:CYAN "Stopping '$name' psmux window..."
        Stop-PsmuxApp -AppName $name
        $stopped = $true
    }
    if ($port -and (Test-PortInUse -Port $port)) {
        Write-Color $script:CYAN "Killing process on port $port..."
        Stop-Port -Port $port
        $stopped = $true
    }
    if ($stopped) { Write-Color $script:GREEN "Stopped '$name'" }
    else          { Write-Color $script:YELLOW "'$name' was not running" }
}

function Restart-SingleApp {
    param($AppObj)
    $name = $AppObj.Name
    if ($DryRun) { Write-Color $script:YELLOW "[DryRun] Would restart '$name'"; return }
    Write-Color $script:CYAN "Restarting '$name'..."
    Stop-SingleApp -AppObj $AppObj
    $port = Get-AppPort -AppObj $AppObj
    if ($port) { Wait-ForPortFree -Port $port -TimeoutSec 5 | Out-Null }
    Start-SingleApp -AppObj $AppObj
}

function Update-SingleApp {
    param($AppObj)
    $name       = $AppObj.Name
    $appPath    = $AppObj.AppPath
    $pkgManager = $AppObj.PackageManager

    if ($DryRun) { Write-Color $script:YELLOW "[DryRun] Would update '$name'"; return }

    Write-Color $script:CYAN "===== Updating '$name' ====="
    Stop-SingleApp -AppObj $AppObj
    $port = Get-AppPort -AppObj $AppObj
    if ($port) { Wait-ForPortFree -Port $port -TimeoutSec 5 | Out-Null }

    # Git pull
    if (Test-Path (Join-Path $appPath '.git')) {
        Write-Color $script:CYAN "Pulling latest changes from git..."
        Push-Location $appPath
        try { git pull; Write-Color $script:GREEN "Git pull successful" }
        catch { Write-Color $script:YELLOW "Git pull failed or no changes" }
        finally { Pop-Location }
    } else {
        Write-Color $script:YELLOW "No git repository found in '$appPath'"
    }

    # Update venv
    if ([string]::IsNullOrWhiteSpace($pkgManager)) {
        $pkgManager = Get-DetectedPackageManager -ProjectDir $appPath
    }
    Write-Color $script:CYAN "Updating dependencies with $pkgManager..."
    Push-Location $appPath
    try {
        if ($pkgManager -ieq 'uv') {
            uv sync
            Write-Color $script:GREEN "Dependencies updated with uv sync"
        } else {
            $req = Find-Requirements -ProjectDir $appPath
            if ($req) {
                $venvPath = $AppObj.VenvPath
                if ([string]::IsNullOrWhiteSpace($venvPath)) { $venvPath = Find-Venv -ProjectDir $appPath }
                $pip = if ($venvPath -and (Test-Path (Join-Path $venvPath 'Scripts\pip.exe'))) {
                    Join-Path $venvPath 'Scripts\pip.exe'
                } else { 'pip' }
                & $pip install -r $req
                Write-Color $script:GREEN "Dependencies updated with pip"
            } else {
                Write-Color $script:YELLOW "No requirements file found"
            }
        }
    } catch { Write-Color $script:YELLOW "Failed to update dependencies: $($_.Exception.Message)" }
    finally { Pop-Location }

    Write-Color $script:CYAN "Starting '$name'..."
    Start-SingleApp -AppObj $AppObj
    Write-Color $script:GREEN "Update complete for '$name'"
}

# ── Selection helpers ─────────────────────────────────────────────────────────
function Get-AppsBySelection {
    param([string]$Selection)
    if ($Selection -eq '0') { return $script:APPS_JSON }

    $result = @()
    $items  = $Selection -split '\s*,\s*' | Where-Object { $_ -ne '' }
    foreach ($item in $items) {
        $item = $item.Trim()
        if ($item -eq '0') { return $script:APPS_JSON }
        if ($item -match '^\d+$') {
            $idx = [int]$item - 1
            if ($idx -ge 0 -and $idx -lt $script:APPS_JSON.Count) {
                $result += $script:APPS_JSON[$idx]
            } else {
                Write-Color $script:YELLOW "Warning: Could not find app at index $item"
            }
        } else {
            $match = $script:APPS_JSON | Where-Object { $_.Name -ieq $item }
            if ($match) { $result += $match }
            else { Write-Color $script:YELLOW "Warning: Could not find app: $item" }
        }
    }
    return $result
}

# ── Add / Edit / Delete ───────────────────────────────────────────────────────
function Add-NewApp {
    $jsonFile = Join-Path $SCRIPT_DIR 'apps.json'
    Write-Header "Add New App"

    $appPath = Read-Host "Enter app path (absolute path)"
    if ([string]::IsNullOrWhiteSpace($appPath) -or $appPath -ieq 'back') { Write-Host "Cancelled."; return }
    $appPath = $appPath -replace '^~', $env:USERPROFILE
    if (-not (Test-Path $appPath)) { Write-Color $script:RED "Error: Directory does not exist: $appPath"; return }
    $appPath = (Resolve-Path $appPath).Path

    $defaultName = Split-Path $appPath -Leaf
    $appName = Read-Host "Enter app name [$defaultName]"
    if ([string]::IsNullOrWhiteSpace($appName)) { $appName = $defaultName }

    if (Test-AppNameExists -JsonFile $jsonFile -AppName $appName) {
        Write-Color $script:RED "Error: An app named '$appName' already exists"; return
    }

    $detectedType = Get-DetectedAppType -ProjectDir $appPath
    Write-Color $script:CYAN "Detected type: $detectedType"

    if ($detectedType -eq 'Unknown') {
        Write-Host "Select app type:  1) Streamlit  2) Django  3) Flask  4) Dash"
        $choice = Read-Host "Enter choice [1-4]"
        $appType = switch ($choice) { '1'{'Streamlit'} '2'{'Django'} '3'{'Flask'} '4'{'Dash'} default{'Streamlit'} }
    } else {
        $ans = Read-Host "Use detected type '$detectedType'? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($ans) -or $ans -imatch '^(y|yes)$') {
            $appType = $detectedType
        } else {
            Write-Host "Select app type:  1) Streamlit  2) Django  3) Flask  4) Dash"
            $choice = Read-Host "Enter choice [1-4]"
            $appType = switch ($choice) { '1'{'Streamlit'} '2'{'Django'} '3'{'Flask'} '4'{'Dash'} default{$detectedType} }
        }
    }

    $pkgManager = Get-DetectedPackageManager -ProjectDir $appPath
    Write-Color $script:CYAN "Detected package manager: $pkgManager"

    $venvPath = Find-Venv -ProjectDir $appPath
    if ($venvPath) { Write-Color $script:CYAN "Found venv: $venvPath" }

    $indexPath = ''
    if ($appType -iin @('Streamlit', 'Flask', 'Dash')) {
        Write-Color $script:CYAN "Select the main/index Python file:"
        $indexPath = Select-IndexFile -ProjectDir $appPath
    }

    $port = Read-PortNumber

    $newApp = Build-AppJson -Name $appName -AppType $appType -Port $port -AppPath $appPath `
        -IndexPath $indexPath -VenvPath $venvPath -PkgManager $pkgManager

    Write-Host ""
    Write-Color $script:CYAN "New app configuration:"
    $newApp | ConvertTo-Json -Depth 5 | Write-Host
    Write-Host ""

    if (Confirm-Action "Save this app?") {
        Add-AppToJson -JsonFile $jsonFile -AppObj $newApp
        Write-Color $script:GREEN "App '$appName' added successfully!"
    } else { Write-Host "Cancelled." }
}

function Add-NewProcess {
    $jsonFile = Join-Path $SCRIPT_DIR 'apps.json'
    Write-Header "Add New Process (Custom Command)"
    Write-Host "Examples:"
    Write-Host "  - Django mgmt cmd: continuous_cache_update"
    Write-Host "  - Python module:   python -m app.db.backup.local_cache_scheduler"
    Write-Host "  - Any script:      python scripts/my_task.py"
    Write-Host ""

    $appPath = Read-Host "Enter working directory path (absolute path)"
    if ([string]::IsNullOrWhiteSpace($appPath) -or $appPath -ieq 'back') { Write-Host "Cancelled."; return }
    $appPath = $appPath -replace '^~', $env:USERPROFILE
    if (-not (Test-Path $appPath)) { Write-Color $script:RED "Error: Directory does not exist: $appPath"; return }
    $appPath = (Resolve-Path $appPath).Path

    $defaultName = Split-Path $appPath -Leaf
    $appName = Read-Host "Enter process name [$defaultName]"
    if ([string]::IsNullOrWhiteSpace($appName)) { $appName = $defaultName }

    if (Test-AppNameExists -JsonFile $jsonFile -AppName $appName) {
        Write-Color $script:RED "Error: A process/app named '$appName' already exists"; return
    }

    $customCmd = Read-Host "Enter command to run"
    if ([string]::IsNullOrWhiteSpace($customCmd)) { Write-Color $script:RED "Error: Command is required"; return }

    $pkgManager = Get-DetectedPackageManager -ProjectDir $appPath
    Write-Color $script:CYAN "Detected package manager: $pkgManager"

    $venvPath = Find-Venv -ProjectDir $appPath
    if ($venvPath) { Write-Color $script:CYAN "Found venv: $venvPath" }

    $newProcess = Build-ProcessJson -Name $appName -AppPath $appPath -CustomCommand $customCmd `
        -VenvPath $venvPath -PkgManager $pkgManager

    Write-Host ""
    Write-Color $script:CYAN "New process configuration:"
    $newProcess | ConvertTo-Json -Depth 5 | Write-Host
    Write-Host ""

    if (Confirm-Action "Save this process?") {
        Add-AppToJson -JsonFile $jsonFile -AppObj $newProcess
        Write-Color $script:GREEN "Process '$appName' added successfully!"
    } else { Write-Host "Cancelled." }
}

function Edit-App {
    param([string]$Target)
    $jsonFile = Join-Path $SCRIPT_DIR 'apps.json'
    if ($Target -notmatch '^\d+$') { Write-Color $script:YELLOW "Usage: e <number>"; return }
    $idx = [int]$Target - 1
    if ($idx -lt 0 -or $idx -ge $script:APPS_JSON.Count) { Write-Color $script:RED "Invalid index: $Target"; return }

    $appObj = $script:APPS_JSON[$idx]
    $appHt  = ConvertTo-AppHashtable -App $appObj
    $isProcess = -not [string]::IsNullOrWhiteSpace($appHt['CustomCommand'])

    if ($isProcess) {
        Write-Header "Edit Process: $($appHt['Name'])"
        Write-Host "Current configuration:"; $appHt | ConvertTo-Json -Depth 5 | Write-Host; Write-Host ""

        $newName = Read-Host "Name [$($appHt['Name'])]"
        if ([string]::IsNullOrWhiteSpace($newName)) { $newName = $appHt['Name'] }
        $newPath = Read-Host "AppPath [$($appHt['AppPath'])]"
        if ([string]::IsNullOrWhiteSpace($newPath)) { $newPath = $appHt['AppPath'] }
        $newCmd  = Read-Host "CustomCommand [$($appHt['CustomCommand'])]"
        if ([string]::IsNullOrWhiteSpace($newCmd))  { $newCmd  = $appHt['CustomCommand'] }
        $newVenv = Read-Host "VenvPath [$($appHt['VenvPath'])]"
        if ([string]::IsNullOrWhiteSpace($newVenv)) { $newVenv = $appHt['VenvPath'] }
        $newPm   = Read-Host "PackageManager [$($appHt['PackageManager'])]"
        if ([string]::IsNullOrWhiteSpace($newPm))   { $newPm   = $appHt['PackageManager'] }

        $updated = Build-ProcessJson -Name $newName -AppPath $newPath -CustomCommand $newCmd -VenvPath $newVenv -PkgManager $newPm
        Write-Host ""; Write-Color $script:CYAN "Updated configuration:"; $updated | ConvertTo-Json -Depth 5 | Write-Host; Write-Host ""
        if (Confirm-Action "Save changes?") {
            Update-AppInJson -JsonFile $jsonFile -AppName $appHt['Name'] -NewApp $updated
            Write-Color $script:GREEN "Process '$newName' updated successfully!"
        } else { Write-Host "Cancelled." }
    } else {
        Write-Header "Edit App: $($appHt['Name'])"
        Write-Host "Current configuration:"; $appHt | ConvertTo-Json -Depth 5 | Write-Host; Write-Host ""

        $newName  = Read-Host "Name [$($appHt['Name'])]"
        if ([string]::IsNullOrWhiteSpace($newName))  { $newName  = $appHt['Name'] }
        $newType  = Read-Host "Type [$($appHt['Type'])]"
        if ([string]::IsNullOrWhiteSpace($newType))  { $newType  = $appHt['Type'] }
        $newPortS = Read-Host "Port [$($appHt['Port'])]"
        $newPort  = if ([string]::IsNullOrWhiteSpace($newPortS)) { [int]$appHt['Port'] } else { [int]$newPortS }
        $newPath  = Read-Host "AppPath [$($appHt['AppPath'])]"
        if ([string]::IsNullOrWhiteSpace($newPath))  { $newPath  = $appHt['AppPath'] }

        $newIndex = ''
        if ($newType -iin @('Streamlit', 'Flask', 'Dash')) {
            $newIndex = Read-Host "IndexPath [$($appHt['IndexPath'])]"
            if ([string]::IsNullOrWhiteSpace($newIndex)) { $newIndex = $appHt['IndexPath'] }
        }
        $newVenv  = Read-Host "VenvPath [$($appHt['VenvPath'])]"
        if ([string]::IsNullOrWhiteSpace($newVenv))  { $newVenv  = $appHt['VenvPath'] }
        $newPm    = Read-Host "PackageManager [$($appHt['PackageManager'])]"
        if ([string]::IsNullOrWhiteSpace($newPm))    { $newPm    = $appHt['PackageManager'] }
        $newNginx = Read-Host "NginxPath (leave empty if none) [$($appHt['NginxPath'])]"
        if ([string]::IsNullOrWhiteSpace($newNginx)) { $newNginx = $appHt['NginxPath'] }

        $updated = Build-AppJson -Name $newName -AppType $newType -Port $newPort -AppPath $newPath `
            -IndexPath $newIndex -VenvPath $newVenv -PkgManager $newPm -NginxPath $newNginx
        Write-Host ""; Write-Color $script:CYAN "Updated configuration:"; $updated | ConvertTo-Json -Depth 5 | Write-Host; Write-Host ""
        if (Confirm-Action "Save changes?") {
            Update-AppInJson -JsonFile $jsonFile -AppName $appHt['Name'] -NewApp $updated
            Write-Color $script:GREEN "App '$newName' updated successfully!"
        } else { Write-Host "Cancelled." }
    }
}

function Remove-App {
    param([string]$Target)
    $jsonFile = Join-Path $SCRIPT_DIR 'apps.json'
    if ($Target -notmatch '^\d+$') { Write-Color $script:YELLOW "Usage: d <number>"; return }
    $idx = [int]$Target - 1
    if ($idx -lt 0 -or $idx -ge $script:APPS_JSON.Count) { Write-Color $script:RED "Invalid index: $Target"; return }

    $appObj  = $script:APPS_JSON[$idx]
    $appName = $appObj.Name
    Write-Color $script:YELLOW "About to delete app: $appName"
    $appObj | ConvertTo-Json -Depth 5 | Write-Host
    Write-Host ""

    if (Confirm-Action "Are you sure you want to delete this app?") {
        if (Test-PsmuxWindowExists -AppName $appName) { Stop-PsmuxApp -AppName $appName }
        Remove-AppFromJson -JsonFile $jsonFile -AppName $appName
        Write-Color $script:GREEN "App '$appName' deleted successfully!"
    } else { Write-Host "Cancelled." }
}

# ── Interactive menu ──────────────────────────────────────────────────────────
function Show-InteractiveMenu {
    while ($true) {
        Invoke-LoadAppsJson
        Show-NetworkUrls
        Show-Apps

        Write-Host ""
        Write-Color $script:CYAN "Commands:"
        Write-Host "  Dashboard"
        Write-Host "    D           - Toggle dashboard (start/stop)"
        Write-Host "  Manage apps"
        Write-Host "    [number(s)] - Start app(s) by index (e.g., 1,2,3) (0 for all)"
        Write-Host "    [name]      - Start app by name"
        Write-Host "    s [num(s)]  - Stop app(s) by index (e.g., 1,2,3) (0 for all)"
        Write-Host "    r [num(s)]  - Restart app(s) by index (e.g., 1,2,3) (0 for all)"
        Write-Host "    u [num(s)]  - Update app(s) from repo (e.g., 1,2,3) (0 for all)"
        Write-Host "  Edit apps.json"
        Write-Host "    aa          - Add a new app"
        Write-Host "    ap          - Add a new process (custom command)"
        Write-Host "    e [num]     - Edit by index"
        Write-Host "    d [num(s)]  - Delete app(s) by index (e.g., 1,2,3)"
        Write-Host "  Psmux"
        Write-Host "    l           - List psmux windows"
        Write-Host "    t           - Attach to psmux session"
        Write-Host "    t [num]     - Attach and switch to app window"
        Write-Host "  Other"
        Write-Host "    R           - Refresh list"
        Write-Host "    q           - Quit"
        Write-Host ""

        $input = Read-Host "Enter selection"

        # Case-sensitive commands first
        if ($input -ceq 'D') {
            if (Test-LandingPageRunning) { Stop-LandingPage }
            else { $script:SkipLanding = $false; Start-LandingPage }
            Write-Host ""; Write-Host "Press Enter to continue..."; Read-Host | Out-Null
            continue
        }
        if ($input -ceq 'R') { continue }

        $inputLower = $input.ToLower().Trim()

        switch -Regex ($inputLower) {
            '^(q|quit|exit)$' {
                Write-Host "Goodbye!"
                exit 0
            }
            '^(aa|add)$' {
                Add-NewApp
                break
            }
            '^(ap|process)$' {
                Add-NewProcess
                break
            }
            '^(l|list)$' {
                Get-PsmuxWindowList
                break
            }
            '^t$' {
                Write-Color $script:CYAN "Attaching to psmux session... (Ctrl+B, D to detach)"
                Start-Sleep -Seconds 1
                Connect-PsmuxSession
                break
            }
            '^t[\s]*(\d+)$' {
                $attachIdx = [int]($Matches[1]) - 1
                if ($attachIdx -ge 0 -and $attachIdx -lt $script:APPS_JSON.Count) {
                    $appName = $script:APPS_JSON[$attachIdx].Name
                    $winName = Select-PsmuxWindow -AppName $appName
                    if ($winName) {
                        Write-Color $script:CYAN "Attaching to psmux session... (Ctrl+B, D to detach)"
                        Start-Sleep -Seconds 1
                        Connect-PsmuxSession -WindowName $winName
                    } else {
                        Write-Color $script:YELLOW "Window for '$appName' is not running"
                    }
                } else {
                    Write-Color $script:RED "Invalid index"
                }
                break
            }
            '^s$' {
                Write-Color $script:YELLOW "Usage: s <number(s)> (e.g., s1  s1,2,3  s0 for all)"
                break
            }
            '^s[\s]*(.+)$' {
                $sel = $Matches[1].Trim()
                if ($sel -eq '0') {
                    foreach ($a in $script:APPS_JSON) { Stop-SingleApp -AppObj $a }
                } else {
                    foreach ($a in (Get-AppsBySelection -Selection $sel)) { Stop-SingleApp -AppObj $a }
                }
                break
            }
            '^r[\s]*(.+)$' {
                $sel = $Matches[1].Trim()
                foreach ($a in (Get-AppsBySelection -Selection $sel)) { Restart-SingleApp -AppObj $a }
                break
            }
            '^u[\s]*(.+)$' {
                $sel = $Matches[1].Trim()
                foreach ($a in (Get-AppsBySelection -Selection $sel)) { Update-SingleApp -AppObj $a }
                break
            }
            '^e[\s]*(\d+)$' {
                Edit-App -Target $Matches[1]
                break
            }
            '^d[\s]*([\d,\s]+)$' {
                $Matches[1] -split '\s*,\s*' | Where-Object { $_ } | ForEach-Object { Remove-App -Target $_.Trim() }
                break
            }
            default {
                if (-not [string]::IsNullOrWhiteSpace($input)) {
                    foreach ($a in (Get-AppsBySelection -Selection $input)) {
                        Start-SingleApp -AppObj $a
                        Start-Sleep -Milliseconds 500
                    }
                }
            }
        }

        Write-Host ""
        Write-Host "Press Enter to continue..."
        Read-Host | Out-Null
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────
function Main {
    if ($Attach) {
        Connect-PsmuxSession
        exit 0
    }

    Write-Header "App Manager for Windows (psmux)"

    Test-Dependencies

    Write-Color $script:CYAN "Detecting network configuration..."
    $script:NETWORK_URL = Get-NetworkUrlPrefix
    $script:EXTERNAL_URL = Get-ExternalUrlPrefix
    $script:GENERIC_URL  = Get-GenericUrlPrefix
    Write-Host "  Network URL:  $script:NETWORK_URL"
    Write-Host "  External URL: $script:EXTERNAL_URL"
    Write-Host "  Generic URL:  $script:GENERIC_URL"
    Write-Host ""

    Invoke-LoadAppsJson

    # Handle landing page
    if ($script:SkipLanding) {
        if (Test-LandingPageRunning) { Stop-LandingPage }
    } elseif ($global:LANDING_PAGE_ENABLED) {
        Start-LandingPage
    }

    $autoStart = $All -or (-not [string]::IsNullOrWhiteSpace($App))

    if ($autoStart) {
        if ($All) {
            Write-Color $script:CYAN "Starting all apps..."
            foreach ($a in $script:APPS_JSON) { Start-SingleApp -AppObj $a; Start-Sleep -Milliseconds 500 }
        } elseif ($App) {
            Write-Color $script:CYAN "Starting app: $App"
            foreach ($a in (Get-AppsBySelection -Selection $App)) { Start-SingleApp -AppObj $a }
        }
    } else {
        Show-InteractiveMenu
    }
}

Main
