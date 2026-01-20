Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
Network-related helper functions for process/port introspection.

.DESCRIPTION
Provides small, reusable utilities to detect which processes are listening on a given TCP port
and to wait until a port becomes free. Centralizing these helpers improves reuse and testability.
#>

function Get-ListeningPidsForPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1,65535)]
        [int]$Port
    )

    $conns = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if (-not $conns) { return @() }
    $pids = $conns | Select-Object -ExpandProperty OwningProcess -Unique
    return @($pids)
}

function Wait-ForPortToBeFree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1,65535)]
        [int]$Port,
        [int]$TimeoutSeconds = 10,
        [int]$PollIntervalMs = 250
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $pids = Get-ListeningPidsForPort -Port $Port
        if (-not $pids -or @($pids).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds $PollIntervalMs
    }
    return $false
}

function Test-PortInUse {
    <#
    .SYNOPSIS
    Determines if a TCP port has an active listener (is in use).

    .DESCRIPTION
    Checks if the specified port has any active TCP connections listening on it.
    Used for both port assignment validation and dashboard status indicators.

    .PARAMETER Port
    The TCP port number to check (1-65535).

    .OUTPUTS
    [bool] - $true if port is in use, $false if available.

    .EXAMPLE
    if (Test-PortInUse -Port 8501) { Write-Host "Port 8501 is in use" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1,65535)]
        [int]$Port
    )

    try {
        $pids = Get-ListeningPidsForPort -Port $Port
        return @($pids).Count -gt 0
    } catch {
        return $false
    }
}

Export-ModuleMember -Function @(
    'Get-ListeningPidsForPort',
    'Wait-ForPortToBeFree',
    'Test-PortInUse'
)
