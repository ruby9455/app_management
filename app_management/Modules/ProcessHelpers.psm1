Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Process-related helpers extracted from run_apps_tab_html.ps1
# Depends on AppHelpers (Get-FieldValue, Set-FieldValue, Test-FieldHasValue, ConvertTo-Hashtable, Select-UniqueAppsByName),
# NetworkHelpers (Get-ListeningPidsForPort, Wait-ForPortToBeFree), and TerminalHelpers (Invoke-AppTabEnter, Stop-AppTabByTitle)

# Ensure field access helpers are available
try {
    if (-not (Get-Command -Name Get-FieldValue -ErrorAction SilentlyContinue)) {
        Import-Module -Force (Join-Path $PSScriptRoot 'AppHelpers.psm1') -ErrorAction Stop
    }
} catch {
    function Get-FieldValue {
        param(
            [Parameter(Mandatory=$true)][object]$Object,
            [Parameter(Mandatory=$true)][string]$Name
        )
        if ($null -eq $Object) { return $null }
        if ($Object -is [hashtable]) { if ($Object.ContainsKey($Name)) { return $Object[$Name] } else { return $null } }
        if ($Object.PSObject -and $Object.PSObject.Properties.Match($Name).Count -gt 0) { return $Object.$Name }
        return $null
    }
}

function Stop-AppByConfig {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )
    $name = Get-FieldValue -Object $App -Name 'Name'
    if (-not (Test-FieldHasValue -Object $App -Name 'Port')) {
        Write-Warning "Cannot stop '$name': no Port configured."
        return
    }
    $port = [int](Get-FieldValue -Object $App -Name 'Port')
    $pids = Get-ListeningPidsForPort -Port $port
    if ($null -eq $pids) { $pids = @() }
    if (@($pids).Count -eq 0) {
        Write-Host "No listening process found on port $port for '$name'."
        return
    }
    foreach ($processId in @($pids)) {
        try {
            $procName = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName
            Write-Host "Stopping '$name' PID $processId ($procName) on port $port..."
            Stop-Process -Id $processId -Force -ErrorAction Stop
            Write-Host "Stopped PID $processId."
        } catch {
            Write-Warning "Failed to stop PID ${processId}: $($_.Exception.Message)"
        }
    }
}

function Get-CurrentAppsList {
    # Prefer in-memory edits if available; relies on $global:apps populated by caller script
    $inMem = @($global:apps)
    if ($inMem.Count -gt 0) { return (Select-UniqueAppsByName -Apps $inMem | Sort-Object Name) }
    return (Select-UniqueAppsByName -Apps @($apps) | Sort-Object Name)
}

function Close-AllIdleAppTabs {
    param([switch]$DryRun)

    $appsList = Get-CurrentAppsList
    if (-not $appsList -or $appsList.Count -eq 0) {
        Write-Host "No supported apps found in apps list. Nothing to close."
        return
    }

    $idleApps = @()
    foreach ($app in $appsList) {
        $name = Get-FieldValue -Object $app -Name 'Name'
        if (-not (Test-FieldHasValue -Object $app -Name 'Port')) { continue }
        $port = [int](Get-FieldValue -Object $app -Name 'Port')
        $pids = Get-ListeningPidsForPort -Port $port
        if (-not $pids -or @($pids).Count -eq 0) { $idleApps += $app }
    }

    if ($idleApps.Count -eq 0) {
        Write-Host "No idle app tabs detected."
        return
    }

    Write-Host "Closing $($idleApps.Count) idle app tab(s)..."
    foreach ($app in $idleApps) {
        $title = Get-FieldValue -Object $app -Name 'Name'
        $portStr = Get-FieldValue -Object $app -Name 'Port'
        Write-Host "-> $title (Port $portStr)"
        Stop-AppTabByTitle -Title $title -DryRun:$DryRun
    }
}

function Update-App {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,
        [switch]$DryRun
    )
    $name = Get-FieldValue -Object $App -Name 'Name'
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

Export-ModuleMember -Function @(
    'Stop-AppByConfig',
    'Get-CurrentAppsList',
    'Close-AllIdleAppTabs',
    'Update-App'
)
