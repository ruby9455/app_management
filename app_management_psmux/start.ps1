<#
.SYNOPSIS
Launch a psmux session with manager and landing page windows.

.DESCRIPTION
Mirrors start.sh from app_management_tmux.
Creates a psmux session 'app_manager' with two windows:
  - manager:      runs manager.ps1 (interactive menu)
  - landing_page: runs landing_page.ps1 (HTTP dashboard)

.EXAMPLE
.\start.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-ScriptPath {
    param([string]$Name)
    $roots = @(
        $PSScriptRoot,
        (Split-Path -Parent $PSScriptRoot),
        (Get-Location).ProviderPath
    ) | Where-Object { $_ } | Select-Object -Unique
    foreach ($r in $roots) {
        $c = Join-Path $r $Name
        if (Test-Path $c) { return (Resolve-Path $c).ProviderPath }
    }
    return $null
}

$script1 = Find-ScriptPath 'manager.ps1'
$script2 = Find-ScriptPath 'landing_page.ps1'

if (-not $script1) { Write-Error "Cannot find 'manager.ps1'.";      exit 1 }
if (-not $script2) { Write-Error "Cannot find 'landing_page.ps1'."; exit 1 }

# Resolve pwsh
$pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwshPath) {
    foreach ($p in @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:LOCALAPPDATA\Programs\PowerShell\7\pwsh.exe"
    )) { if (Test-Path $p) { $pwshPath = $p; break } }
}
if (-not $pwshPath) { Write-Error "pwsh not found. Install PowerShell 7+."; exit 1 }
Write-Host "pwsh: $pwshPath"

# Check psmux
if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) {
    Write-Error "psmux not found in PATH. Install psmux before running this script."
    exit 1
}

$session = 'app_manager'

# Kill existing session if present
$null = & psmux has-session -t $session 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Killing existing psmux session '$session'..."
    & psmux kill-session -t $session 2>&1 | Out-Null
}

Write-Host "Creating psmux session '$session'..."
& psmux new-session -d -s $session -n 'manager' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create psmux session '$session'."; exit 1 }

# Window 1: manager
$managerCmd = "$pwshPath -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$script1`""
& psmux send-keys -t "${session}:manager" $managerCmd Enter 2>&1 | Out-Null
Write-Host "Started manager in psmux window 'manager'."

# Window 2: landing_page
& psmux new-window -t $session -n 'landing_page' -c $PSScriptRoot -d 2>&1 | Out-Null
$landingCmd = "$pwshPath -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$script2`""
& psmux send-keys -t "${session}:landing_page" $landingCmd Enter 2>&1 | Out-Null
Write-Host "Started landing_page in psmux window 'landing_page'."

& psmux select-window -t "${session}:manager" 2>&1 | Out-Null

Write-Host ""
Write-Host "psmux session '$session' is running."
Write-Host "To attach:        psmux attach -t $session"
Write-Host "Switch windows:   Ctrl+B then n/p or window index"
Write-Host ""
Write-Host "Attaching to psmux session..."
& psmux attach -t $session
