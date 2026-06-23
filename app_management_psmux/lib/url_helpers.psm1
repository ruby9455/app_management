# lib/url_helpers.psm1
# Mirrors url_helpers.sh - URL prefix detection utilities for Windows

function Get-NetworkUrlPrefix {
    try {
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4Address -and $_.IPv4DefaultGateway }
        if ($cfg) {
            foreach ($c in @($cfg)) {
                foreach ($addr in @($c.IPv4Address)) {
                    $ip = $addr.IPAddress
                    if ($ip -and $ip -notmatch '^(127\.|169\.254\.)') { return "http://$ip" }
                }
            }
        }
        $all = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
            Select-Object -First 1
        if ($all) { return "http://$($all.IPAddress)" }
    } catch { }
    return 'http://127.0.0.1'
}

function Get-ExternalUrlPrefix {
    param([int]$TimeoutSec = 5)
    $services = @('https://api.ipify.org?format=text', 'https://ifconfig.me/ip')
    foreach ($svc in $services) {
        try {
            $ip = Invoke-RestMethod -UseBasicParsing -Uri $svc -TimeoutSec $TimeoutSec -ErrorAction Stop
            if ($ip -match '^(?:\d{1,3}\.){3}\d{1,3}$') { return "http://$ip" }
        } catch { continue }
    }
    return (Get-NetworkUrlPrefix)
}

function Get-GenericUrlPrefix {
    try {
        $host = $env:COMPUTERNAME
        if ([string]::IsNullOrWhiteSpace($host)) { $host = [System.Net.Dns]::GetHostName() }
        if (-not [string]::IsNullOrWhiteSpace($host)) { return "http://$host" }
    } catch { }
    return (Get-NetworkUrlPrefix)
}

function Build-AppUrl {
    param([string]$BaseUrl, [string]$Port, [string]$BasePath = '')
    $url = "${BaseUrl}:${Port}"
    if (-not [string]::IsNullOrWhiteSpace($BasePath)) {
        $url = "$url/$($BasePath.TrimStart('/'))"
    }
    return $url
}

Export-ModuleMember -Function @(
    'Get-NetworkUrlPrefix',
    'Get-ExternalUrlPrefix',
    'Get-GenericUrlPrefix',
    'Build-AppUrl'
)
