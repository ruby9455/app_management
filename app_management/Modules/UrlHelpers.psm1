Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NetworkUrlPrefix {
    <#
    .SYNOPSIS
    Returns an HTTP URL prefix for the primary local IPv4 address, e.g. "http://192.168.1.10".

    .DESCRIPTION
    Prefers an IPv4 address on an interface with a default gateway. Filters out loopback (127.0.0.1)
    and APIPA (169.254.x.x). Falls back to 127.0.0.1 if no suitable address is found.
    #>
    [CmdletBinding()]
    param()

    try {
        $candidates = @()

        # Prefer interfaces with a default gateway
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4Address -and $_.IPv4DefaultGateway }
        if ($cfg) {
            foreach ($c in $cfg) {
                foreach ($addr in $c.IPv4Address) {
                    if ($addr.IPAddress) { $candidates += $addr.IPAddress }
                }
            }
        }

        # Fallback: any IPv4 address
        if (-not $candidates -or $candidates.Count -eq 0) {
            $all = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -and $_.IPAddress -notmatch '^(127\.|169\.254\.)' }
            if ($all) { $candidates += ($all | Select-Object -ExpandProperty IPAddress) }
        }

        # Filter and pick the first reasonable candidate
        $ip = ($candidates | Where-Object { $_ -notmatch '^(127\.|169\.254\.)' } | Select-Object -First 1)
        if (-not $ip) { $ip = '127.0.0.1' }
        return "http://$ip"
    } catch {
        return 'http://127.0.0.1'
    }
}

function Get-ExternalUrlPrefix {
    <#
    .SYNOPSIS
    Returns an HTTP URL prefix for the external/public IPv4 address if reachable, else falls back to network prefix.

    .DESCRIPTION
    Queries a couple of simple public IP echo services with short timeouts. If none respond,
    returns the same value as Get-NetworkUrlPrefix.
    #>
    [CmdletBinding()]
    param(
        [int]$TimeoutSec = 3
    )

    $services = @(
        'https://api.ipify.org?format=text',
        'https://ifconfig.me/ip'
    )
    foreach ($svc in $services) {
        try {
            $ip = Invoke-RestMethod -UseBasicParsing -Uri $svc -TimeoutSec $TimeoutSec -ErrorAction Stop
            if ($ip -and ($ip -match '^(?:\d{1,3}\.){3}\d{1,3}$')) {
                return "http://$ip"
            }
        } catch {
            continue
        }
    }

    # Fallback to local network URL prefix
    return (Get-NetworkUrlPrefix)
}

Export-ModuleMember -Function Get-NetworkUrlPrefix, Get-ExternalUrlPrefix
# Requires -Version 7.0
# UrlHelpers.psm1 - shared URL prefix detection utilities

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-scoped defaults; adjust for your environment
$script:DEFAULT_NETWORK_URL_FALLBACK  = 'http://10.17.62.232'
$script:DEFAULT_EXTERNAL_URL_FALLBACK = 'http://203.1.252.70'
$script:EXTERNAL_IP_TIMEOUT_SEC       = 5

function Get-NetworkUrlPrefix {
    try {
        # Prefer primary non-loopback IPv4 with manual/DHCP origin
        $networkAdapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -notlike "127.*" -and 
            $_.IPAddress -notlike "169.254.*" -and
            $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual"
        } | Sort-Object InterfaceIndex | Select-Object -First 1
        if ($networkAdapter) { return "http://$($networkAdapter.IPAddress)" }

        # Fallback: any non-loopback IPv4
        $fallbackAdapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*"
        } | Select-Object -First 1
        if ($fallbackAdapter) { return "http://$($fallbackAdapter.IPAddress)" }
    } catch {
        Write-Warning "Failed to detect network IP: $($_.Exception.Message)"
    }
    return $script:DEFAULT_NETWORK_URL_FALLBACK
}

function Get-ExternalUrlPrefix {
    try {
        $externalIP = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec $script:EXTERNAL_IP_TIMEOUT_SEC -ErrorAction Stop
        if ($externalIP -and $externalIP -match '^\d+\.\d+\.\d+\.\d+$') { return "http://$externalIP" }
    } catch {
        Write-Warning "Failed to detect external IP via ipify.org: $($_.Exception.Message)"
    }
    try {
        $externalIP = Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec $script:EXTERNAL_IP_TIMEOUT_SEC -ErrorAction Stop
        if ($externalIP -and $externalIP -match '^\d+\.\d+\.\d+\.\d+$') { return "http://$externalIP" }
    } catch {
        Write-Warning "Failed to detect external IP via ifconfig.me: $($_.Exception.Message)"
    }
    return $script:DEFAULT_EXTERNAL_URL_FALLBACK
}

# Returns an HTTP URL prefix using the local computer name, e.g. "http://SAH0241627"
function Get-GenericUrlPrefix {
    try {
        # Prefer COMPUTERNAME env var; fallback to DNS hostname
        $hostName = $env:COMPUTERNAME
        if ([string]::IsNullOrWhiteSpace($hostName)) {
            $hostName = [System.Net.Dns]::GetHostName()
        }
        if ([string]::IsNullOrWhiteSpace($hostName)) { return (Get-NetworkUrlPrefix) }
        return "http://$hostName"
    } catch {
        # Fallback to network or localhost
        return (Get-NetworkUrlPrefix)
    }
}

Export-ModuleMember -Function @(
    'Get-NetworkUrlPrefix',
    'Get-ExternalUrlPrefix',
    'Get-GenericUrlPrefix'
)
