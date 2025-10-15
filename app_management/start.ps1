<#
.SYNOPSIS
  Launch Windows Terminal with two panes and run the two app-management scripts.

USAGE
  Save this file into the `app_management` folder and run from PowerShell:
    .\start_both.ps1

REQUIREMENTS
  - Windows Terminal (`wt.exe`) must be installed and in PATH.
  - PowerShell execution policy may need to allow script execution (see notes).
#>

# Resolve scripts next to this wrapper, but tolerate different layouts.
param(
  [ValidateSet('Right','Down')]
  [string]$Split = 'Right'
)
function Find-ScriptPath {
  param([string]$name)

  # Candidate roots: script folder, parent, grandparent, current working dir
  $roots = @(
    $PSScriptRoot,
    (Split-Path -Parent $PSScriptRoot),
    (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    (Get-Location).ProviderPath
  ) | Where-Object { $_ -ne $null } | Select-Object -Unique

  foreach ($r in $roots) {
    $candidate = Join-Path $r $name
    if (Test-Path $candidate) {
      return (Resolve-Path $candidate).ProviderPath
    }
  }

  return $null
}

$script1 = Find-ScriptPath 'run_apps_tab_html.ps1'
$script2 = Find-ScriptPath 'generate_landing_page.ps1'

if (-not $script1) {
  Write-Error "Cannot find 'run_apps_tab_html.ps1'. Checked: $PSScriptRoot, parent folders, and current directory."
  exit 1
}
if (-not $script2) {
  Write-Error "Cannot find 'generate_landing_page.ps1'. Checked: $PSScriptRoot, parent folders, and current directory."
  exit 1
}

Write-Output "Resolved script paths:`n  run_apps_tab_html: $script1`n  generate_app_index: $script2"

# Sanity checks
if (-not (Test-Path $script1)) {
  Write-Error "Resolved path for run_apps_tab_html does not exist: $script1"
  exit 1
}
if (-not (Test-Path $script2)) {
  Write-Error "Resolved path for generate_app_index does not exist: $script2"
  exit 1
}

# Show where pwsh and wt come from
function Get-PwshPath {
  # 1) Prefer whatever 'pwsh' resolves to on PATH
  $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) {
    return $cmd.Source
  }
  # 2) Try common install locations
  $candidates = @(
    (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
    (Join-Path $env:ProgramFiles 'PowerShell\7-preview\pwsh.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7\pwsh.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\pwsh.exe')
  )
  foreach ($p in $candidates) {
    if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
  }
  return $null
}

$pwshPath = Get-PwshPath
if (-not $pwshPath) {
  Write-Error "pwsh not found in PATH or common install locations. Install PowerShell 7+ or adjust this script to use Windows PowerShell."
  exit 1
}
Write-Output "pwsh resolved to: $pwshPath"

$wtCmd = Get-Command wt -ErrorAction SilentlyContinue
if ($wtCmd) {
  Write-Output "wt resolved to: $($wtCmd.Source)"
} else {
  Write-Error "Windows Terminal 'wt' not found in PATH."
  exit 1
}

# Prefer PowerShell Core (pwsh). Ensure pwsh is available and use it for both panes.
# $pwshCmd was resolved above (with fallbacks); if missing we already exited.

# Build the argument string for wt. This opens a new window/tab and then creates a split pane.
# Change -H to -V if you prefer vertical split orientation.
# Use the absolute path to pwsh.exe to avoid PATH differences between your current shell and Windows Terminal.
$shellExePath = $pwshPath
$shellExe = '"' + $shellExePath + '"'
# Use 'new-tab' so wt treats the first action as a new tab, then split-pane for the second.
# Use '-File "path"' to avoid command-line parsing issues with -Command and quoting.
$splitFlag = if ($Split -eq 'Right') { '-V' } else { '-H' } # -V = vertical (side by side), -H = horizontal (stacked)
# Build wt arguments as an array and request an existing window (-w 0) so Windows Terminal
# will open the tab in an existing window instead of creating a new window.
$wtArgs = @(
  '-w', '0',
  'new-tab', '--', $shellExePath, '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script1,
  ';',
  'split-pane', $splitFlag, '--', $shellExePath, '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script2
)

$wtArgsString = ($wtArgs -join ' ')
Write-Output "Full wt argument string: $wtArgsString"

# Print exact pwsh invocation strings for clarity
$pane1 = "`"$shellExePath`" -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$script1`""
$pane2 = "`"$shellExePath`" -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$script2`""
Write-Output "Pane1 invocation: $pane1"
Write-Output "Pane2 invocation: $pane2"
Write-Output "Split orientation: $Split ($splitFlag)"

# Use full path to wt when possible
$wtExePath = $wtCmd.Source

Write-Output "Launching: $wtExePath $wtArgsString"

Write-Output "Launching Windows Terminal..."
# -NoNewWindow cannot be used with -WindowStyle; remove it so wt launches correctly
Start-Process -FilePath $wtExePath -ArgumentList $wtArgs -WindowStyle Normal

Write-Output "If nothing appears, ensure Windows Terminal (wt.exe) is installed and on PATH."
