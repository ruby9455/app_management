# Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PsmuxCommand = $null
$script:SessionName = if ($env:APP_MANAGER_PSMUX_SESSION) { $env:APP_MANAGER_PSMUX_SESSION } else { 'app_manager' }

function Get-PsmuxCommand {
    if ($script:PsmuxCommand) { return $script:PsmuxCommand }

    # Prefer the explicitly named executable.  psmux also ships a tmux alias, so
    # accepting it makes this work with either command the user has configured.
    foreach ($candidate in @('psmux', 'tmux')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            $script:PsmuxCommand = $command.Source
            return $script:PsmuxCommand
        }
    }
    throw "psmux was not found on PATH. Install it, or expose its tmux alias on PATH."
}

function Invoke-Psmux {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & (Get-PsmuxCommand) @Arguments
}

function Get-PsmuxSessionName { return $script:SessionName }

function ConvertTo-PsmuxWindowName {
    param([Parameter(Mandatory)][string]$Name)
    $sanitized = $Name -replace '[ /:.]+', '_' -replace '[^A-Za-z0-9_-]', ''
    if ([string]::IsNullOrWhiteSpace($sanitized)) { return 'app' }
    return $sanitized
}

function Test-PsmuxSession {
    & (Get-PsmuxCommand) has-session -t $script:SessionName 2>$null
    return $LASTEXITCODE -eq 0
}

function Initialize-PsmuxSession {
    if (Test-PsmuxSession) {
        $existingWindows = @(& (Get-PsmuxCommand) list-windows -t $script:SessionName -F '#{window_id}' 2>$null)
        if ($existingWindows.Count -gt 0) { return }

        # psmux can retain a zero-window session after a bad target operation.
        # It cannot add a new window to that ghost session, so remove it first.
        Invoke-Psmux -Arguments @('kill-session', '-t', $script:SessionName)
        if (Test-PsmuxSession) {
            $sessions = @(& (Get-PsmuxCommand) list-sessions -F '#{session_name}' 2>$null)
            if ($sessions.Count -eq 1 -and $sessions[0] -eq $script:SessionName) {
                Invoke-Psmux -Arguments @('kill-server')
            } else {
                throw "psmux session '$script:SessionName' has no windows and could not be removed. Other sessions are active, so run 'psmux kill-session -t $script:SessionName' before retrying."
            }
        }
    }

    if (-not (Test-PsmuxSession)) {
        Invoke-Psmux -Arguments @('new-session', '-d', '-s', $script:SessionName, '-n', '_placeholder')
        if ($LASTEXITCODE -ne 0) { throw "Unable to create psmux session '$script:SessionName'." }
        Write-Host "Created psmux session: $script:SessionName" -ForegroundColor Green
    }
}

function Get-PsmuxWindowId {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-PsmuxSession)) { return $null }
    $windowName = ConvertTo-PsmuxWindowName $Name
    $windows = @(& (Get-PsmuxCommand) list-windows -t $script:SessionName -F '#{window_id}|#{window_name}' 2>$null)
    foreach ($window in $windows) {
        $parts = $window -split '\|', 2
        if ($parts.Count -eq 2 -and $parts[1] -eq $windowName) { return $parts[0] }
    }
    return $null
}

function Test-PsmuxWindow {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-PsmuxWindowId $Name)
}

function New-PsmuxEncodedCommand {
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$RunCommand
    )
    $escapedDirectory = $WorkingDirectory -replace "'", "''"
    $escapedTitle = $Title -replace "'", "''"
    $commandText = @"
Set-Location -LiteralPath '$escapedDirectory'
`$host.UI.RawUI.WindowTitle = '$escapedTitle'
Write-Host '=== Starting: $escapedTitle ===' -ForegroundColor Cyan
Write-Host 'Directory: $escapedDirectory'
try {
    $RunCommand
    `$exitCode = if (`$null -eq `$LASTEXITCODE) { 0 } else { `$LASTEXITCODE }
    Write-Host "`n=== Process exited with code `$exitCode ===" -ForegroundColor Yellow
} catch {
    Write-Error `$_
}
Read-Host 'Press Enter to close this window'
"@
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($commandText))
}

function New-PsmuxWindow {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$EncodedCommand
    )
    Initialize-PsmuxSession
    if (Test-PsmuxWindow $Name) { throw "psmux window '$Name' already exists." }
    $windowName = ConvertTo-PsmuxWindowName $Name
    # psmux 3.3.x rebuilds the child command line and does not preserve the
    # spaces in an absolute path such as C:\Program Files\PowerShell\7\pwsh.exe.
    # Dependency validation already guarantees that pwsh is on PATH, so use the
    # command name here.
    $null = Get-Command pwsh -ErrorAction Stop
    $pwsh = 'pwsh'
    # psmux requires `--` before the command and its arguments. Without the
    # separator it creates the window with its default shell instead of running
    # the encoded app command, and the detached window can immediately exit.
    Invoke-Psmux -Arguments @('new-window', '-d', '-t', $script:SessionName, '-n', $windowName, '-c', $WorkingDirectory, '--', $pwsh, '-NoLogo', '-EncodedCommand', $EncodedCommand)
    if ($LASTEXITCODE -ne 0) { throw "Unable to create psmux window '$Name'." }
    if (-not (Test-PsmuxWindow $Name)) { throw "psmux created the command but app window '$Name' exited immediately." }
    $placeholderId = Get-PsmuxWindowId '_placeholder'
    if ($placeholderId) { Invoke-Psmux -Arguments @('kill-window', '-t', $placeholderId) }
}

function Stop-PsmuxWindow {
    param([Parameter(Mandatory)][string]$Name)
    $windowId = Get-PsmuxWindowId $Name
    if (-not $windowId) { return }
    Invoke-Psmux -Arguments @('send-keys', '-t', $windowId, 'C-c')
    Start-Sleep -Seconds 1
    $remainingIds = @(& (Get-PsmuxCommand) list-windows -t $script:SessionName -F '#{window_id}' 2>$null)
    if ($remainingIds -contains $windowId) { Invoke-Psmux -Arguments @('kill-window', '-t', $windowId) }
}

function Show-PsmuxWindows {
    if (-not (Test-PsmuxSession)) { Write-Host 'No psmux session found.' -ForegroundColor Yellow; return }
    Write-Host "psmux windows in session '$script:SessionName`:" -ForegroundColor Cyan
    Invoke-Psmux -Arguments @('list-windows', '-t', $script:SessionName, '-F', '  #{window_index}: #{window_name} (#{window_panes} pane(s))')
}

function Connect-PsmuxSession {
    if (-not (Test-PsmuxSession)) { Write-Host 'No psmux session found. Start an app first.' -ForegroundColor Yellow; return }
    Invoke-Psmux -Arguments @('attach-session', '-t', $script:SessionName)
}

function Select-PsmuxWindow {
    param([Parameter(Mandatory)][string]$Name)
    $windowId = Get-PsmuxWindowId $Name
    if (-not $windowId) { throw "psmux window '$Name' was not found." }
    Invoke-Psmux -Arguments @('select-window', '-t', $windowId)
}

function Stop-AllPsmuxWindows {
    if (-not (Test-PsmuxSession)) { Write-Host 'No psmux session found.' -ForegroundColor Yellow; return }
    $windows = @(& (Get-PsmuxCommand) list-windows -t $script:SessionName -F '#{window_id}|#{window_name}' 2>$null)
    foreach ($window in $windows) {
        $parts = $window -split '\|', 2
        if ($parts.Count -eq 2 -and $parts[1] -ne '_placeholder') { Invoke-Psmux -Arguments @('send-keys', '-t', $parts[0], 'C-c') }
    }
    Start-Sleep -Seconds 1
    Invoke-Psmux -Arguments @('kill-session', '-t', $script:SessionName)
    Write-Host 'Stopped all psmux windows and removed the session.' -ForegroundColor Green
}

Export-ModuleMember -Function @(
    'Get-PsmuxCommand', 'Invoke-Psmux', 'Get-PsmuxSessionName', 'ConvertTo-PsmuxWindowName',
    'Test-PsmuxSession', 'Initialize-PsmuxSession', 'Test-PsmuxWindow', 'New-PsmuxEncodedCommand',
    'New-PsmuxWindow', 'Stop-PsmuxWindow', 'Show-PsmuxWindows', 'Connect-PsmuxSession',
    'Select-PsmuxWindow', 'Stop-AllPsmuxWindows'
)
