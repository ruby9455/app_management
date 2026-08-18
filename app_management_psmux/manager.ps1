<#
.SYNOPSIS
Manage Python web apps in named psmux windows on Windows.

.DESCRIPTION
The psmux equivalent of app_management_tmux.  It keeps all apps in one psmux
session, giving each app a named window that can be listed, selected, stopped,
restarted, or attached to.  This script intentionally uses PowerShell-native
commands and Windows virtual-environment paths.
#>
[CmdletBinding()]
param(
    [string]$AppName,
    [switch]$All,
    [switch]$DryRun,
    [switch]$Attach,
    [switch]$NoLanding,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modules = Join-Path $PSScriptRoot 'Modules'
Import-Module (Join-Path $modules 'PsmuxHelpers.psm1') -Force

$script:LandingPort = 1111
$script:LandingName = '_Dashboard'
$script:AppsPath = Join-Path $PSScriptRoot 'apps.json'
$script:ExampleAppsPath = Join-Path $PSScriptRoot 'apps_example.json'
$script:Apps = @()

function Show-Usage {
@"
Usage: .\manager.ps1 [options]

  -AppName NAME           Start a named app
  -All                    Start all apps
  -DryRun                 Print launch commands without changing state
  -Attach                 Attach to the app_manager psmux session
  -NoLanding              Do not start the dashboard (and stop an existing one)
  -Help                   Show this help

Interactive commands match the tmux edition:
  D                 Toggle dashboard
  1,2 or App Name   Start app(s), 0 for all
  s1,2 / s 1,2      Stop app(s), 0 for all
  r1,2 / r 1,2      Restart app(s), 0 for all
  u1,2 / u 1,2      Update app(s), 0 for all
  aa / ap           Add app / custom process
  e1 / d1,2         Edit / delete app(s) (space optional)
  l                 List psmux windows
  t / t1 / t 1      Attach / attach and select an app window
  R                 Refresh app list
  q                 Quit
"@ | Write-Host
}

function Get-Field { param([object]$App, [string]$Name) if ($App.PSObject.Properties.Name -contains $Name) { return $App.$Name }; return $null }
function Quote-Ps { param([string]$Value) return ($Value -replace "'", "''") }
function Test-PortInUse { param([int]$Port) return @((Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)).Count -gt 0 }
function Get-PortPids { param([int]$Port) return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique) }
function Wait-PortFree { param([int]$Port, [int]$Seconds = 5) $end = (Get-Date).AddSeconds($Seconds); while ((Get-Date) -lt $end) { if (-not (Test-PortInUse $Port)) { return $true }; Start-Sleep -Milliseconds 250 }; return -not (Test-PortInUse $Port) }

function Get-NetworkUrl {
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | Select-Object -First 1 -ExpandProperty IPAddress
        if ($ip) { return "http://$ip" }
    } catch {}
    return 'http://127.0.0.1'
}
function Get-ExternalUrl {
    try { $ip = Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 3 -ErrorAction Stop; if ($ip -match '^(?:\d{1,3}\.){3}\d{1,3}$') { return "http://$ip" } } catch {}
    return Get-NetworkUrl
}
function Get-GenericUrl { if ($env:COMPUTERNAME) { return "http://$env:COMPUTERNAME" }; return Get-NetworkUrl }

function Assert-Dependencies {
    $missing = @()
    try { $null = Get-PsmuxCommand } catch { $missing += 'psmux (or its tmux alias)' }
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { $missing += 'PowerShell 7 (pwsh)' }
    if (-not (Get-Command py -ErrorAction SilentlyContinue) -and -not (Get-Command python -ErrorAction SilentlyContinue)) { $missing += 'Python (py or python)' }
    if ($missing.Count) { throw "Missing required dependencies: $($missing -join ', ')" }
}

function Initialize-AppsFile {
    if (-not (Test-Path $script:AppsPath)) {
        if (Test-Path $script:ExampleAppsPath) { Copy-Item $script:ExampleAppsPath $script:AppsPath } else { '[]' | Set-Content $script:AppsPath }
        Write-Host "Created $script:AppsPath. Edit it to configure your apps." -ForegroundColor Yellow
    }
}
function Load-Apps {
    Initialize-AppsFile
    $raw = Get-Content $script:AppsPath -Raw | ConvertFrom-Json
    $seen = @{}
    $script:Apps = @($raw | Where-Object {
        $type = Get-Field $_ 'Type'; $command = Get-Field $_ 'CustomCommand'
        ($type -in @('Streamlit', 'Django', 'Flask', 'Dash')) -or -not [string]::IsNullOrWhiteSpace([string]$command)
    } | Where-Object {
        $name = [string](Get-Field $_ 'Name')
        if ([string]::IsNullOrWhiteSpace($name) -or $seen.ContainsKey($name.ToLowerInvariant())) { return $false }
        $seen[$name.ToLowerInvariant()] = $true; return $true
    })
    Write-Host "Found $($script:Apps.Count) supported app(s)." -ForegroundColor Green
}
function Save-Apps {
    $answer = Read-Host 'Save changes to apps.json? [y/N]'
    if ($answer -match '^(?i:y|yes)$') { ConvertTo-Json -InputObject @($script:Apps) -Depth 10 | Set-Content $script:AppsPath -Encoding utf8; Load-Apps }
}

function Find-Apps {
    param([string]$Selection)
    if ($Selection -eq '0' -or $Selection -ieq 'all') { return @($script:Apps) }
    # $Matches is an automatic PowerShell variable populated by -match.  Using
    # that name for the result collection turns it into a hashtable as soon as
    # a numeric selection matches the expression below.
    $selectedApps = @()
    foreach ($item in ($Selection -split '\s*,\s*')) {
        if ($item -match '^\d+$' -and [int]$item -ge 1 -and [int]$item -le $script:Apps.Count) { $selectedApps += $script:Apps[[int]$item - 1]; continue }
        $app = $script:Apps | Where-Object { (Get-Field $_ 'Name') -ieq $item } | Select-Object -First 1
        if ($app) { $selectedApps += $app } else { Write-Warning "Unknown app/index: $item" }
    }
    return @($selectedApps)
}
function Show-Apps {
    Write-Host "`n #  Name                           Type        Port   Status" -ForegroundColor Cyan
    Write-Host '--- ------------------------------ ----------- ------ -------' -ForegroundColor DarkCyan
    for ($i = 0; $i -lt $script:Apps.Count; $i++) {
        $app = $script:Apps[$i]; $name = [string](Get-Field $app 'Name'); $type = Get-Field $app 'Type'; $port = Get-Field $app 'Port'
        $running = (Test-PsmuxWindow $name) -or ($port -and [int]$port -gt 0 -and (Test-PortInUse ([int]$port)))
        $status = if ($running) { 'running' } else { 'stopped' }; $colour = if ($running) { 'Green' } else { 'Red' }
        Write-Host ('{0,2}  {1,-30} {2,-11} {3,-6} ' -f ($i + 1), $name, $type, $(if ($port) { $port } else { 'N/A' })) -NoNewline
        Write-Host $status -ForegroundColor $colour
    }
}

function Show-Commands {
    Write-Host "`nCommands:" -ForegroundColor Cyan
    Write-Host '  D                 Toggle dashboard'
    Write-Host '  1,2 or App Name   Start app(s), 0 for all'
    Write-Host '  s1,2 / s 1,2      Stop app(s), 0 for all'
    Write-Host '  r1,2 / r 1,2      Restart app(s), 0 for all'
    Write-Host '  u1,2 / u 1,2      Update app(s), 0 for all'
    Write-Host '  aa / ap           Add app / custom process'
    Write-Host '  e1 / d1,2         Edit / delete app(s) (space optional)'
    Write-Host '  l                 List psmux windows'
    Write-Host '  t / t1 / t 1      Attach / attach and select an app window'
    Write-Host '  R                 Refresh app list'
    Write-Host '  h / q             Help / quit'
}

function Get-RunCommand {
    param([object]$App, [string]$WorkingDirectory)
    $type = [string](Get-Field $App 'Type'); $index = Get-Field $App 'IndexPath'; $port = Get-Field $App 'Port'; $custom = Get-Field $App 'CustomCommand'
    $manager = [string](Get-Field $App 'PackageManager'); if ([string]::IsNullOrWhiteSpace($manager)) { $manager = if (Test-Path (Join-Path $WorkingDirectory 'pyproject.toml')) { 'uv' } else { 'pip' } }
    $venvPrefix = ''
    if ($manager -ine 'uv') {
        $venv = Get-Field $App 'VenvPath'; if (-not $venv) { $venv = Join-Path $WorkingDirectory '.venv' }
        $activate = Join-Path $venv 'Scripts\Activate.ps1'
        if (Test-Path $activate) { $venvPrefix = "& '$(Quote-Ps $activate)'; " } else { $venvPrefix = "py -m venv .venv; & '.\.venv\Scripts\Activate.ps1'; " }
    }
    if ($custom) {
        if ($type -ieq 'Django' -and $custom -notmatch '[\\/]' -and $custom -notmatch '^(?i:py|python|uv)\b') {
            $manage = Get-ChildItem $WorkingDirectory -Filter manage.py -File -Recurse -Depth 3 | Select-Object -First 1
            if ($manage) {
                $command = if ($manager -ieq 'uv') { "uv run python '$(Quote-Ps $manage.FullName)' $custom" } else { "$venvPrefix`py '$(Quote-Ps $manage.FullName)' $custom" }
                return $command
            }
        }
        $command = if ($manager -ieq 'uv' -and $custom -notmatch '^(?i:uv)\b') { "uv run $custom" } else { "$venvPrefix$custom" }
        return $command
    }
    switch ($type.ToLowerInvariant()) {
        'streamlit' { if (-not $index -or -not $port) { throw "Streamlit app requires IndexPath and Port." }; $base = Get-Field $App 'BasePath'; $baseArg = if ($base) { " --server.baseUrlPath '$(Quote-Ps $base)'" } else { '' }; $command = if ($manager -ieq 'uv') { "uv run streamlit run '$(Quote-Ps $index)' --server.port $port$baseArg" } else { "$venvPrefix`streamlit run '$(Quote-Ps $index)' --server.port $port$baseArg" }; return $command }
        'django' { $manage = Get-ChildItem $WorkingDirectory -Filter manage.py -File -Recurse -Depth 3 | Select-Object -First 1; if (-not $manage) { throw 'Django app requires manage.py.' }; $portArg = if ($port) { " $port" } else { '' }; $command = if ($manager -ieq 'uv') { "uv run python '$(Quote-Ps $manage.FullName)' runserver$portArg" } else { "$venvPrefix`py '$(Quote-Ps $manage.FullName)' runserver$portArg" }; return $command }
        'flask' { if (-not $index -or -not $port) { throw "Flask app requires IndexPath and Port." }; $env = "`$env:FLASK_APP='$(Quote-Ps $index)'; `$env:FLASK_ENV='development'; "; $command = if ($manager -ieq 'uv') { "${env}uv run flask run --host=0.0.0.0 --port $port" } else { "$venvPrefix${env}flask run --host=0.0.0.0 --port $port" }; return $command }
        'dash' { if (-not $index) { throw 'Dash app requires IndexPath.' }; $portArg = if ($port) { " --server.port $port" } else { '' }; $command = if ($manager -ieq 'uv') { "uv run python '$(Quote-Ps $index)'$portArg" } else { "$venvPrefix`python '$(Quote-Ps $index)'$portArg" }; return $command }
        default { throw "Unsupported app type '$type'." }
    }
}

function Stop-App {
    param([object]$App)
    $name = [string](Get-Field $App 'Name'); $port = Get-Field $App 'Port'; $stopped = $false
    if (Test-PsmuxWindow $name) { if ($DryRun) { Write-Host "[Dry run] Would stop '$name'." } else { Stop-PsmuxWindow $name }; $stopped = $true }
    if ($port -and [int]$port -gt 0 -and (Test-PortInUse ([int]$port))) {
        if ($DryRun) { Write-Host "[Dry run] Would stop process on port $port." } else { Get-PortPids ([int]$port) | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue } }
        $stopped = $true
    }
    if ($stopped) { Write-Host "Stopped '$name'." -ForegroundColor Green } else { Write-Host "'$name' was not running." -ForegroundColor Yellow }
}
function Start-App {
    param([object]$App)
    $name = [string](Get-Field $App 'Name'); $path = [string](Get-Field $App 'AppPath'); $type = Get-Field $App 'Type'; $index = Get-Field $App 'IndexPath'; $port = Get-Field $App 'Port'
    if (-not $name -or -not $path -or -not (Test-Path $path)) { Write-Warning "Skipping '$name': AppPath not found: $path"; return }
    if ($type -in @('Streamlit','Flask','Dash') -and $index) {
        $indexFullPath = if ([IO.Path]::IsPathRooted([string]$index)) { [string]$index } else { Join-Path $path $index }
        if (-not (Test-Path $indexFullPath)) { Write-Warning "Skipping '$name': IndexPath not found: $indexFullPath"; return }
    }
    if (Test-PsmuxWindow $name) { $answer = Read-Host "'$name' already has a psmux window. Restart it? [y/N]"; if ($answer -notmatch '^(?i:y|yes)$') { return }; if (-not $DryRun) { Stop-PsmuxWindow $name } }
    elseif ($port -and [int]$port -gt 0 -and (Test-PortInUse ([int]$port))) { $answer = Read-Host "Port $port is in use. Stop it and start '$name'? [y/N]"; if ($answer -notmatch '^(?i:y|yes)$') { return }; if (-not $DryRun) { Get-PortPids ([int]$port) | ForEach-Object { Stop-Process -Id $_ -Force }; Wait-PortFree ([int]$port) | Out-Null } }
    $working = (Resolve-Path $path).Path; $run = Get-RunCommand $App $working
    if ($DryRun) { Write-Host "[Dry run] ${name}: $run" -ForegroundColor Yellow; return }
    New-PsmuxWindow -Name $name -WorkingDirectory $working -EncodedCommand (New-PsmuxEncodedCommand $working $name $run)
    Write-Host "Started '$name' in psmux." -ForegroundColor Green
}
function Restart-App { param([object]$App) Stop-App $App; $port = Get-Field $App 'Port'; if ($port) { Wait-PortFree ([int]$port) | Out-Null }; Start-App $App }
function Update-App {
    param([object]$App)
    $name = Get-Field $App 'Name'; $path = Get-Field $App 'AppPath'; if (-not (Test-Path $path)) { Write-Warning "AppPath not found: $path"; return }
    if ($DryRun) { Write-Host "[Dry run] Would update '$name'."; return }
    Stop-App $App; Push-Location $path
    try { git pull; $manager = Get-Field $App 'PackageManager'; if (-not $manager) { $manager = if (Test-Path '.\pyproject.toml') { 'uv' } else { 'pip' } }; if ($manager -ieq 'uv') { uv sync } else { $requirements = Get-ChildItem -Filter requirements.txt -Recurse | Select-Object -First 1; if ($requirements) { py -m pip install -r $requirements.FullName } } } finally { Pop-Location }
    Start-App $App
}

function Start-Dashboard {
    if (Test-PsmuxWindow $script:LandingName) { if (Test-PortInUse $script:LandingPort) { Write-Host 'Dashboard already running.' -ForegroundColor Cyan; return }; Stop-PsmuxWindow $script:LandingName }
    if (Test-PortInUse $script:LandingPort) { Write-Host "Dashboard port $script:LandingPort is already in use." -ForegroundColor Yellow; return }
    if ($DryRun) { Write-Host "[Dry run] Would start dashboard on port $script:LandingPort."; return }
    $scriptPath = Quote-Ps (Join-Path $PSScriptRoot 'landing_page.ps1'); $run = "& '$scriptPath' -Port $script:LandingPort"
    New-PsmuxWindow -Name $script:LandingName -WorkingDirectory $PSScriptRoot -EncodedCommand (New-PsmuxEncodedCommand $PSScriptRoot 'Dashboard' $run)
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (Test-PortInUse $script:LandingPort) { Write-Host "Dashboard started at http://localhost:$script:LandingPort" -ForegroundColor Green; return }
        Start-Sleep -Milliseconds 250
    }
    Write-Warning "Dashboard window started, but port $script:LandingPort is not listening. Select the _Dashboard psmux window to inspect its error output."
}
function Stop-Dashboard { if (Test-PsmuxWindow $script:LandingName) { if (-not $DryRun) { Stop-PsmuxWindow $script:LandingName }; Write-Host 'Dashboard stopped.' -ForegroundColor Green } }

function Add-App {
    $path = Read-Host 'App directory (or back)'; if ($path -ieq 'back') { return }; if (-not (Test-Path $path)) { Write-Warning 'Directory not found.'; return }
    $name = Read-Host "Name [$(Split-Path $path -Leaf)]"; if (-not $name) { $name = Split-Path $path -Leaf }; if ($script:Apps | Where-Object { (Get-Field $_ 'Name') -ieq $name }) { Write-Warning 'Name already exists.'; return }
    $type = Read-Host 'Type (Streamlit/Django/Flask/Dash)'; $port = Read-Host 'Port'; $index = if ($type -in @('Streamlit','Flask','Dash')) { Read-Host 'IndexPath (e.g. app.py)' } else { $null }
    $manager = if (Test-Path (Join-Path $path 'pyproject.toml')) { 'uv' } else { 'pip' }; $venv = Join-Path $path '.venv'
    $app = [pscustomobject]@{ Name=$name; Type=$type; AppPath=$path; IndexPath=$index; Port=if ($port) { [int]$port } else { $null }; PackageManager=$manager; VenvPath=$venv }
    $script:Apps += $app; Save-Apps
}
function Add-Process {
    $path = Read-Host 'Working directory (or back)'; if ($path -ieq 'back') { return }; if (-not (Test-Path $path)) { Write-Warning 'Directory not found.'; return }
    $name = Read-Host "Name [$(Split-Path $path -Leaf)]"; if (-not $name) { $name = Split-Path $path -Leaf }; $command = Read-Host 'Command to run'; if (-not $command) { return }
    $manager = if (Test-Path (Join-Path $path 'pyproject.toml')) { 'uv' } else { 'pip' }; $script:Apps += [pscustomobject]@{ Name=$name; AppPath=$path; CustomCommand=$command; PackageManager=$manager }; Save-Apps
}
function Edit-App {
    param([object]$App)
    foreach ($field in @('Name','Type','AppPath','IndexPath','Port','VenvPath','PackageManager','BasePath','CustomCommand')) { $old = Get-Field $App $field; $new = Read-Host "$field [$old]"; if ($new) { if ($field -eq 'Port') { $App.$field = [int]$new } elseif ($App.PSObject.Properties.Name -contains $field) { $App.$field = $new } else { $App | Add-Member -NotePropertyName $field -NotePropertyValue $new } } }
    Save-Apps
}
function Remove-Apps { param([object[]]$AppsToRemove) $names = @($AppsToRemove | ForEach-Object { [string](Get-Field $_ 'Name') }); $script:Apps = @($script:Apps | Where-Object { $names -notcontains [string](Get-Field $_ 'Name') }); Save-Apps }

function Show-Menu {
    while ($true) {
        Show-Apps
        Show-Commands
        $input = (Read-Host "`nEnter selection").Trim()
        if (-not $input) { continue }
        switch -Regex ($input) {
            '^(?i:q)$' { return }
            '^(?i:h|help)$' { Show-Usage }
            '^(?i:d)$' { if (Test-PsmuxWindow $script:LandingName) { Stop-Dashboard } else { Start-Dashboard } }
            '^(?i:l)$' { Show-PsmuxWindows }
            '^(?i:t)$' { Connect-PsmuxSession }
            '^(?i:t\s*(.+))$' { $app = Find-Apps $matches[1] | Select-Object -First 1; if ($app) { Select-PsmuxWindow (Get-Field $app 'Name'); Connect-PsmuxSession } }
            '^(?i:r)$' { Load-Apps }
            '^(?i:aa)$' { Add-App }
            '^(?i:ap)$' { Add-Process }
            '^(?i:s\s*(.+))$' { Find-Apps $matches[1] | ForEach-Object { Stop-App $_ } }
            '^(?i:r\s*(.+))$' { Find-Apps $matches[1] | ForEach-Object { Restart-App $_ } }
            '^(?i:u\s*(.+))$' { Find-Apps $matches[1] | ForEach-Object { Update-App $_ } }
            '^(?i:e\s*(.+))$' { $app = Find-Apps $matches[1] | Select-Object -First 1; if ($app) { Edit-App $app } }
            '^(?i:d\s*(.+))$' { Remove-Apps (Find-Apps $matches[1]) }
            default { Find-Apps $input | ForEach-Object { Start-App $_ } }
        }
        Read-Host 'Press Enter to continue' | Out-Null
    }
}

if ($Help) { Show-Usage; exit 0 }
Assert-Dependencies
if ($Attach) { Connect-PsmuxSession; exit 0 }
Write-Host "Network:  $(Get-NetworkUrl)"; Write-Host "External: $(Get-ExternalUrl)"; Write-Host "Generic:  $(Get-GenericUrl)"
Load-Apps
if ($NoLanding) { Stop-Dashboard } else { Start-Dashboard }
if ($All) { $script:Apps | ForEach-Object { Start-App $_ } }
elseif ($AppName) { $selectedApps = @(Find-Apps $AppName); if (-not $selectedApps.Count) { throw "App '$AppName' was not found." }; $selectedApps | ForEach-Object { Start-App $_ } }
else { Show-Menu }
