<#
.SYNOPSIS
Serve the app dashboard on port 1111 (or a supplied port).

.DESCRIPTION
The dashboard is regenerated for each request from apps.json, so app status and
links stay current while the psmux dashboard window remains running.
#>
[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port = 1111)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Field { param([object]$App, [string]$Name) if ($App.PSObject.Properties.Name -contains $Name) { return $App.$Name }; return $null }
function Html { param([string]$Text) return [System.Net.WebUtility]::HtmlEncode($Text) }
function Test-PortInUse { param([int]$TestPort) return @((Get-NetTCPConnection -State Listen -LocalPort $TestPort -ErrorAction SilentlyContinue)).Count -gt 0 }
function Get-NetworkUrl {
    try { $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | Select-Object -First 1 -ExpandProperty IPAddress; if ($ip) { return "http://$ip" } } catch {}
    return 'http://127.0.0.1'
}
function Get-ExternalUrl { try { $ip = Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 3 -ErrorAction Stop; if ($ip -match '^(?:\d{1,3}\.){3}\d{1,3}$') { return "http://$ip" } } catch {}; return Get-NetworkUrl }
function Get-GenericUrl { if ($env:COMPUTERNAME) { return "http://$env:COMPUTERNAME" }; return Get-NetworkUrl }

function New-DashboardHtml {
    $appsPath = Join-Path $PSScriptRoot 'apps.json'
    $apps = if (Test-Path $appsPath) { @(Get-Content $appsPath -Raw | ConvertFrom-Json) } else { @() }
    $network = Get-NetworkUrl; $external = Get-ExternalUrl; $generic = Get-GenericUrl
    $cards = foreach ($app in $apps) {
        $port = Get-Field $app 'Port'; if (-not $port -or [int]$port -le 0) { continue }
        $name = [string](Get-Field $app 'Name'); $type = [string](Get-Field $app 'Type'); $basePath = Get-Field $app 'BasePath'; $suffix = if ($basePath) { "/$basePath" } else { '' }
        $running = Test-PortInUse ([int]$port); $status = if ($running) { 'Running' } else { 'Stopped' }; $statusClass = if ($running) { 'up' } else { 'down' }
        $urls = @(
            @{ Label='Local'; Url="http://localhost:$port$suffix" },
            @{ Label='Network'; Url="$network`:$port$suffix" },
            @{ Label='Generic'; Url="$generic`:$port$suffix" },
            @{ Label='External'; Url="$external`:$port$suffix" }
        )
        $links = foreach ($item in $urls) { "<p><strong>$(Html $item.Label):</strong> <a href='$(Html $item.Url)' target='_blank'>$(Html $item.Url)</a></p>" }
        "<article><h2>$(Html $name) <span class='$statusClass'>$status</span></h2><div class='type'>$(Html $type)</div>$($links -join [Environment]::NewLine)</article>"
    }
@"
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>App Management Dashboard</title><style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:2rem;background:#f3f6fb;color:#1d2939}.wrap{max-width:1100px;margin:auto}h1{margin-bottom:.2rem}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:1rem}article{background:white;border-radius:10px;padding:1.2rem;box-shadow:0 2px 10px #0001}h2{margin:0 0:.5rem}.type{color:#52606d;margin-bottom:1rem}.up,.down{font-size:.75rem;padding:.25rem .45rem;border-radius:1rem;color:white}.up{background:#16a34a}.down{background:#dc2626}a{color:#2563eb;word-break:break-word}p{margin:.55rem 0}</style></head>
<body><main class="wrap"><h1>App Management Dashboard</h1><p>Updated on each refresh. <button onclick="location.reload()">Refresh</button></p><section class="grid">$($cards -join [Environment]::NewLine)</section></main></body></html>
"@
}

# The wildcard host requires a Windows HTTP URL ACL reservation and makes the
# default manager fail for a standard (non-admin) user.  The dashboard is a
# local control page, so bind to localhost without requiring machine setup.
$prefix = "http://localhost:$Port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
try {
    $listener.Start()
} catch {
    throw "Could not listen on $prefix. Ensure the port is free. $($_.Exception.Message)"
}
Write-Host "Dashboard running at http://localhost:$Port (press Ctrl+C or close this psmux window to stop)." -ForegroundColor Green
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $response = $context.Response
        if ($context.Request.Url.AbsolutePath -in @('/', '/index.html')) {
            $content = New-DashboardHtml
            $bytes = [Text.Encoding]::UTF8.GetBytes($content)
            $response.StatusCode = 200; $response.ContentType = 'text/html; charset=utf-8'; $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $bytes = [Text.Encoding]::UTF8.GetBytes('404 - Not Found')
            $response.StatusCode = 404; $response.ContentType = 'text/plain'; $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        $response.Close()
    }
} finally { if ($listener.IsListening) { $listener.Stop() }; $listener.Close() }
