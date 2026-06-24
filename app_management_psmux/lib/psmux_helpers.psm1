# lib/psmux_helpers.psm1
# Mirrors tmux_helpers.sh - psmux session/window management for app management
#
# Source with: Import-Module (Join-Path $PSScriptRoot 'lib/psmux_helpers.psm1')

# ANSI color constants - module-scoped, used by functions within this module
$script:RED    = "`e[0;31m"
$script:GREEN  = "`e[0;32m"
$script:YELLOW = "`e[1;33m"
$script:BLUE   = "`e[0;34m"
$script:PURPLE = "`e[0;35m"
$script:CYAN   = "`e[0;36m"
$script:NC     = "`e[0m"

# Default session name (can be overridden by caller)
if (-not $global:PSMUX_SESSION_NAME) { $global:PSMUX_SESSION_NAME = 'app_manager' }

function Write-Color {
    param([string]$Color, [string]$Message)
    Write-Host "${Color}${Message}$($script:NC)"
}

function Test-PsmuxAvailable {
    return ($null -ne (Get-Command -Name psmux -ErrorAction SilentlyContinue))
}

function Test-InPsmux {
    return (-not [string]::IsNullOrEmpty($env:TMUX))
}

function Test-PsmuxSessionExists {
    try {
        & psmux has-session -t $global:PSMUX_SESSION_NAME 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Invoke-EnsurePsmuxSession {
    if (-not (Test-PsmuxSessionExists)) {
        & psmux new-session -d -s $global:PSMUX_SESSION_NAME -n '_placeholder' 2>&1 | Out-Null
        Write-Color $script:GREEN "Created psmux session: $global:PSMUX_SESSION_NAME"
    }
}

function Get-SanitizedWindowName {
    param([string]$Name)
    # Replace spaces and special chars with underscores, keep alphanumeric, underscore, hyphen
    $sanitized = $Name -replace '[ /:.]', '_' -replace '[^a-zA-Z0-9_\-]', ''
    return $sanitized.Substring(0, [Math]::Min($sanitized.Length, 50))
}

function Test-PsmuxWindowExists {
    param([string]$AppName)
    $winName = Get-SanitizedWindowName -Name $AppName
    if (-not (Test-PsmuxSessionExists)) { return $false }
    try {
        $windows = & psmux list-windows -t $global:PSMUX_SESSION_NAME -F '#{window_name}' 2>&1
        if ($LASTEXITCODE -ne 0) { return $false }
        return ($windows -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $winName }).Count -gt 0
    } catch { return $false }
}

function New-PsmuxWindow {
    param(
        [string]$AppName,
        [string]$WorkingDir,
        [string]$Command
    )
    $winName = Get-SanitizedWindowName -Name $AppName

    Invoke-EnsurePsmuxSession

    if (Test-PsmuxWindowExists -AppName $AppName) {
        Write-Color $script:YELLOW "Window '$AppName' already exists. Use restart to replace it."
        return $false
    }

    # Create window and run command; keep window open after exit for inspection
    $wrappedCmd = "Write-Host '=== Starting: $AppName ==='; Write-Host 'Directory: $WorkingDir'; Write-Host '---'; $Command; `$ret = `$LASTEXITCODE; Write-Host ''; Write-Host '=== App exited with code '`$ret' ==='; Write-Host 'Press Enter to close this window...'; Read-Host"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wrappedCmd))
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source ?? 'pwsh'

    & psmux new-window -t $global:PSMUX_SESSION_NAME -n $winName -c $WorkingDir -d 2>&1 | Out-Null
    & psmux send-keys -t "$($global:PSMUX_SESSION_NAME):$winName" "$pwsh -NoLogo -EncodedCommand $encoded" Enter 2>&1 | Out-Null

    # Only kill the placeholder window if it actually exists — psmux silently kills
    # window 0 when the target name is not found, which would destroy a real app window.
    if (Test-PsmuxWindowExists -AppName '_placeholder') {
        & psmux kill-window -t "$($global:PSMUX_SESSION_NAME):_placeholder" 2>&1 | Out-Null
    }

    return $true
}

function Send-PsmuxCtrlC {
    param([string]$AppName)
    $winName = Get-SanitizedWindowName -Name $AppName
    if (-not (Test-PsmuxWindowExists -AppName $AppName)) {
        Write-Color $script:YELLOW "Window '$AppName' not found"
        return $false
    }
    & psmux send-keys -t "$($global:PSMUX_SESSION_NAME):$winName" C-c 2>&1 | Out-Null
    return $true
}

function Remove-PsmuxWindow {
    param([string]$AppName)
    $winName = Get-SanitizedWindowName -Name $AppName
    if (-not (Test-PsmuxWindowExists -AppName $AppName)) {
        Write-Color $script:YELLOW "Window '$AppName' not found"
        return
    }
    & psmux kill-window -t "$($global:PSMUX_SESSION_NAME):$winName" 2>&1 | Out-Null
    Write-Color $script:GREEN "Killed window: $AppName"
}

function Stop-PsmuxApp {
    param([string]$AppName, [bool]$KeepWindow = $false)
    if (-not (Test-PsmuxWindowExists -AppName $AppName)) { return }
    Send-PsmuxCtrlC -AppName $AppName
    Start-Sleep -Seconds 1
    if (-not $KeepWindow) { Remove-PsmuxWindow -AppName $AppName }
}

function Restart-PsmuxApp {
    param([string]$AppName, [string]$WorkingDir, [string]$Command)
    if (Test-PsmuxWindowExists -AppName $AppName) {
        Stop-PsmuxApp -AppName $AppName -KeepWindow $false
        Start-Sleep -Seconds 1
    }
    New-PsmuxWindow -AppName $AppName -WorkingDir $WorkingDir -Command $Command
}

function Get-PsmuxWindowList {
    if (-not (Test-PsmuxSessionExists)) {
        Write-Color $script:YELLOW "No psmux session found"
        return
    }
    Write-Color $script:CYAN "psmux windows in session '$global:PSMUX_SESSION_NAME':"
    & psmux list-windows -t $global:PSMUX_SESSION_NAME -F '  #{window_index}: #{window_name} (#{window_panes} pane(s))' 2>&1
}

function Get-RunningWindowNames {
    if (-not (Test-PsmuxSessionExists)) { return @() }
    $windows = & psmux list-windows -t $global:PSMUX_SESSION_NAME -F '#{window_name}' 2>&1
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($windows -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne '_placeholder' })
}

function Remove-AllPsmuxWindows {
    if (-not (Test-PsmuxSessionExists)) {
        Write-Color $script:YELLOW "No psmux session found"
        return
    }
    $windows = Get-RunningWindowNames
    foreach ($w in $windows) {
        & psmux send-keys -t "$($global:PSMUX_SESSION_NAME):$w" C-c 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 1
    & psmux kill-session -t $global:PSMUX_SESSION_NAME 2>&1 | Out-Null
    Write-Color $script:GREEN "Killed all windows and session"
}

function Connect-PsmuxSession {
    param([string]$WindowName = '')
    if (-not (Test-PsmuxSessionExists)) {
        Write-Color $script:YELLOW "No psmux session found. Start some apps first."
        return
    }
    $target = if ($WindowName) { "$($global:PSMUX_SESSION_NAME):$WindowName" } else { $global:PSMUX_SESSION_NAME }
    if (Test-InPsmux) {
        & psmux switch-client -t $target 2>&1 | Out-Null
    } else {
        & psmux attach-session -t $target 2>&1 | Out-Null
    }
}

function Select-PsmuxWindow {
    param([string]$AppName)
    $winName = Get-SanitizedWindowName -Name $AppName
    if (-not (Test-PsmuxWindowExists -AppName $AppName)) {
        Write-Color $script:YELLOW "Window '$AppName' not found"
        return $null
    }
    & psmux select-window -t "$($global:PSMUX_SESSION_NAME):$winName" 2>&1 | Out-Null
    return $winName
}

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Color $script:CYAN "═══════════════════════════════════════════════════════════"
    Write-Color $script:CYAN "  $Text"
    Write-Color $script:CYAN "═══════════════════════════════════════════════════════════"
    Write-Host ""
}

function Write-AppInfo {
    param([int]$Index, [string]$Name, [string]$Type, [string]$Port, [string]$Status)
    $statusColor = if ($Status -eq 'running') { $script:GREEN } else { $script:RED }
    $statusIcon  = if ($Status -eq 'running') { '●' } else { '○' }
    $portDisplay = if ($Port) { $Port } else { 'N/A' }
    Write-Host ("$($script:BLUE){0,3}$($script:NC) │ {1,-30} │ {2,-10} │ {3,-6} │ ${statusColor}${statusIcon} ${Status}$($script:NC)" -f $Index, $Name, $Type, $portDisplay)
}

function Write-TableHeader {
    Write-Color $script:PURPLE "────┬────────────────────────────────┬────────────┬────────┬──────────"
    Write-Host ("$($script:PURPLE)  # │ {0,-30} │ {1,-10} │ {2,-6} │ Status$($script:NC)" -f 'Name', 'Type', 'Port')
    Write-Color $script:PURPLE "────┼────────────────────────────────┼────────────┼────────┼──────────"
}

function Write-TableFooter {
    Write-Color $script:PURPLE "────┴────────────────────────────────┴────────────┴────────┴──────────"
}

Export-ModuleMember -Function @(
    'Write-Color',
    'Test-PsmuxAvailable',
    'Test-InPsmux',
    'Test-PsmuxSessionExists',
    'Invoke-EnsurePsmuxSession',
    'Get-SanitizedWindowName',
    'Test-PsmuxWindowExists',
    'New-PsmuxWindow',
    'Send-PsmuxCtrlC',
    'Remove-PsmuxWindow',
    'Stop-PsmuxApp',
    'Restart-PsmuxApp',
    'Get-PsmuxWindowList',
    'Get-RunningWindowNames',
    'Remove-AllPsmuxWindows',
    'Connect-PsmuxSession',
    'Select-PsmuxWindow',
    'Write-Header',
    'Write-AppInfo',
    'Write-TableHeader',
    'Write-TableFooter'
)
