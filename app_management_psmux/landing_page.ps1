<#
.SYNOPSIS
Host an HTML dashboard for all app URLs on port 1111.

.DESCRIPTION
Mirrors landing_page.sh from app_management_tmux.
Serves a live dashboard page via HTTP. On every request the HTML is regenerated
from apps.json so status indicators reflect the current state.

.PARAMETER Port
The port to host the web server on. Default is 1111.

.NOTES
NETWORK ACCESS:
  Without admin: binds to localhost only.
  With admin (or after running the one-time netsh command below): binds to all interfaces.

  One-time workaround (run once as Administrator):
    netsh http add urlacl url=http://+:1111/ user=DOMAIN\username

.EXAMPLE
.\landing_page.ps1
.\landing_page.ps1 -Port 8080
#>

[CmdletBinding()]
param(
    [int]$Port = 1111
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SCRIPT_DIR = $PSScriptRoot
$libDir     = Join-Path $SCRIPT_DIR 'lib'

Import-Module -Force (Join-Path $libDir 'url_helpers.psm1')  -ErrorAction Stop
Import-Module -Force (Join-Path $libDir 'app_helpers.psm1')  -ErrorAction Stop
Import-Module -Force (Join-Path $libDir 'config.psm1')       -ErrorAction Stop

$htmlFilePath = Join-Path $SCRIPT_DIR 'app_index.html'

# ── HTML generation ───────────────────────────────────────────────────────────
function New-DashboardHtml {
    $jsonFile = Join-Path $SCRIPT_DIR 'apps.json'
    if (-not (Test-Path $jsonFile)) { return "<html><body><p>apps.json not found at $jsonFile</p></body></html>" }

    $apps = @(Get-Content $jsonFile -Raw | ConvertFrom-Json)
    if ($apps.Count -eq 0) { return "<html><body><p>No apps found in apps.json.</p></body></html>" }

    $networkUrl  = Get-NetworkUrlPrefix
    $externalUrl = Get-ExternalUrlPrefix
    $genericUrl  = Get-GenericUrlPrefix

    $appsWithPorts = @($apps | Where-Object { $_.Port -and [int]$_.Port -gt 0 })
    if ($appsWithPorts.Count -eq 0) { return "<html><body><p>No apps with valid ports.</p></body></html>" }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>App Management Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 15px; box-shadow: 0 20px 40px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%); color: white; padding: 30px; text-align: center; }
        .header h1 { margin: 0; font-size: 2.5em; font-weight: 300; }
        .header p { margin: 10px 0 0 0; opacity: 0.9; font-size: 1.1em; }
        .apps-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); gap: 20px; padding: 30px; }
        .app-card { background: #f8f9fa; border-radius: 10px; padding: 20px; border-left: 4px solid #4facfe; transition: transform 0.2s, box-shadow 0.2s; }
        .app-card:hover { transform: translateY(-2px); box-shadow: 0 10px 25px rgba(0,0,0,0.1); }
        .app-name { font-size: 1.3em; font-weight: 600; color: #2c3e50; margin-bottom: 10px; }
        .app-type { background: #e3f2fd; color: #1976d2; padding: 4px 8px; border-radius: 15px; font-size: 0.8em; display: inline-block; margin-bottom: 15px; }
        .status-indicator { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-left: 10px; vertical-align: middle; }
        .status-running { background: #2ecc71; box-shadow: 0 0 8px rgba(46,204,113,0.6); }
        .status-stopped { background: #e74c3c; box-shadow: 0 0 8px rgba(231,76,60,0.6); }
        .url-section { margin-bottom: 15px; }
        .url-label { font-weight: 600; color: #555; margin-bottom: 5px; font-size: 0.9em; }
        .url-container { display: flex; align-items: center; gap: 8px; margin-bottom: 5px; }
        .url-link { background: white; border: 1px solid #ddd; border-radius: 5px; padding: 8px 12px; flex: 1; text-decoration: none; color: #2c3e50; transition: background-color 0.2s; word-break: break-all; }
        .url-link:hover { background: #f0f8ff; border-color: #4facfe; }
        .copy-btn { background: #667eea; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; font-size: 0.85em; white-space: nowrap; }
        .copy-btn:hover { background: #5568d3; }
        .copy-btn.copied { background: #2ecc71; }
        .footer { background: #f8f9fa; padding: 20px; text-align: center; color: #666; border-top: 1px solid #eee; }
        .refresh-btn { background: #4facfe; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; font-size: 1em; margin-bottom: 20px; }
    </style>
    <script>
        function copyToClipboard(url, btn) {
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(url).then(() => showCopied(btn)).catch(() => fallbackCopy(url, btn));
            } else { fallbackCopy(url, btn); }
        }
        function fallbackCopy(url, btn) {
            const ta = document.createElement('textarea'); ta.value = url;
            ta.style.position = 'fixed'; ta.style.left = '-9999px'; document.body.appendChild(ta);
            ta.focus(); ta.select();
            try { document.execCommand('copy') ? showCopied(btn) : showFailed(btn); } catch { showFailed(btn); }
            document.body.removeChild(ta);
        }
        function showCopied(btn) { const t = btn.textContent; btn.textContent = '✓ Copied!'; btn.classList.add('copied'); setTimeout(() => { btn.textContent = t; btn.classList.remove('copied'); }, 2000); }
        function showFailed(btn) { btn.textContent = '✗ Failed'; setTimeout(() => { btn.textContent = '📋 Copy'; }, 2000); }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 App Management Dashboard</h1>
            <p>Access all your applications from one place</p>
            <button class="refresh-btn" onclick="location.reload()">🔄 Refresh</button>
        </div>
        <div class="apps-grid">
"@

    foreach ($app in $appsWithPorts) {
        $port        = $app.Port
        $appName     = $app.Name
        $appType     = $app.Type
        $portInUse   = Test-PortInUse -Port $port
        $statusClass = if ($portInUse) { 'status-running' } else { 'status-stopped' }
        $statusText  = if ($portInUse) { 'Running' } else { 'Stopped' }
        $localUrl    = "http://localhost:$port"
        $networkUrlA = if ($appType -ieq 'Django') { "http://127.0.0.1:$port" } else { "${networkUrl}:$port" }
        $extUrl      = "${externalUrl}:$port"
        $genUrl      = "${genericUrl}:$port"

        $html += @"
            <div class="app-card">
                <div class="app-name">$appName<span class="status-indicator $statusClass" title="$statusText"></span></div>
                <div class="app-type">$appType</div>
                <div class="url-section"><div class="url-label">🏠 Local URL</div>
                    <div class="url-container"><a href="$localUrl" target="_blank" class="url-link">$localUrl</a><button class="copy-btn" onclick="copyToClipboard('$localUrl',this)">📋 Copy</button></div></div>
                <div class="url-section"><div class="url-label">🌐 Network URL</div>
                    <div class="url-container"><a href="$networkUrlA" target="_blank" class="url-link">$networkUrlA</a><button class="copy-btn" onclick="copyToClipboard('$networkUrlA',this)">📋 Copy</button></div></div>
                <div class="url-section"><div class="url-label">🔗 Generic URL</div>
                    <div class="url-container"><a href="$genUrl" target="_blank" class="url-link">$genUrl</a><button class="copy-btn" onclick="copyToClipboard('$genUrl',this)">📋 Copy</button></div></div>
                <div class="url-section"><div class="url-label">🌍 External URL</div>
                    <div class="url-container"><a href="$extUrl" target="_blank" class="url-link">$extUrl</a><button class="copy-btn" onclick="copyToClipboard('$extUrl',this)">📋 Copy</button></div></div>
            </div>
"@
    }

    $html += @"
        </div>
        <div class="footer">
            <p>Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Network: $networkUrl | Generic: $genericUrl | External: $externalUrl</p>
        </div>
    </div>
</body>
</html>
"@
    return $html
}

# ── HTTP server ───────────────────────────────────────────────────────────────
$networkUrl  = Get-NetworkUrlPrefix
$externalUrl = Get-ExternalUrlPrefix
$genericUrl  = Get-GenericUrlPrefix

Write-Host "Detecting network configuration..."
Write-Host "  Network URL:  $networkUrl"
Write-Host "  External URL: $externalUrl"
Write-Host "  Generic URL:  $genericUrl"
Write-Host ""

# Generate initial HTML
$initialHtml = New-DashboardHtml
$initialHtml | Out-File -FilePath $htmlFilePath -Encoding UTF8 -Force
Write-Host "Dashboard generated at: $htmlFilePath"

Add-Type -AssemblyName System.Net.Http

function Get-FreeTcpPort {
    $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $tcp.Start(); $p = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port; $tcp.Stop(); return $p
}

$candidatePorts = @($Port) + @(1112..1125) + @(Get-FreeTcpPort) | Select-Object -Unique
$bindAddresses  = @('+', 'localhost')

$listener      = $null
$selectedPort  = $Port
$actualBind    = $null
$started       = $false

foreach ($bindAddr in $bindAddresses) {
    foreach ($p in $candidatePorts) {
        try {
            $listener = [System.Net.HttpListener]::new()
            $listener.Prefixes.Add("http://${bindAddr}:$p/")
            $listener.Start()
            $selectedPort = $p; $actualBind = $bindAddr; $started = $true; break
        } catch {
            try { $listener.Close() } catch { }
            $listener = $null
        }
    }
    if ($started) { break }
}

if (-not $started) { throw "Unable to start HTTP server; all candidate ports failed." }

if ($actualBind -eq 'localhost') {
    Write-Warning "Server bound to localhost only. Network URLs will not work."
    Write-Warning "To enable network access, run PowerShell as Administrator."
}

Write-Host ""
Write-Host "Starting HTTP server on port $selectedPort"
Write-Host ""
Write-Host "Access the dashboard at:"
Write-Host "  Network:   ${networkUrl}:$selectedPort"
Write-Host "  External:  ${externalUrl}:$selectedPort"
Write-Host "  Local:     http://localhost:$selectedPort"
Write-Host ""
Write-Host "Server running (PID: $PID)"
Write-Host "Press Enter to stop the server"

$requestHandler = {
    param($context, $htmlFilePath, $SCRIPT_DIR)
    $request  = $context.Request
    $response = $context.Response
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - $($request.HttpMethod) $($request.Url.PathAndQuery)"

    if ($request.Url.PathAndQuery -eq '/' -or $request.Url.PathAndQuery -eq '/index.html') {
        $libDir = Join-Path $SCRIPT_DIR 'lib'
        Import-Module -Force (Join-Path $libDir 'url_helpers.psm1')  -ErrorAction SilentlyContinue
        Import-Module -Force (Join-Path $libDir 'app_helpers.psm1')  -ErrorAction SilentlyContinue
        Import-Module -Force (Join-Path $libDir 'config.psm1')       -ErrorAction SilentlyContinue

        $jsonFile = Join-Path $SCRIPT_DIR 'apps.json'
        if (Test-Path $jsonFile) {
            $apps        = @(Get-Content $jsonFile -Raw | ConvertFrom-Json)
            $networkUrl  = Get-NetworkUrlPrefix
            $externalUrl = Get-ExternalUrlPrefix
            $genericUrl  = Get-GenericUrlPrefix
            $appsWithPorts = @($apps | Where-Object { $_.Port -and [int]$_.Port -gt 0 })

            # Inline minimal HTML generation for the request handler scope
            $htmlContent = & {
                if ($appsWithPorts.Count -eq 0) { return "<html><body><p>No apps with valid ports.</p></body></html>" }
                $h = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>App Dashboard</title></head><body>"
                $h += "<h1>App Management Dashboard</h1><p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p><ul>"
                foreach ($app in $appsWithPorts) {
                    $port = $app.Port; $name = $app.Name
                    $running = (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) -ne $null
                    $status = if ($running) { '🟢 Running' } else { '🔴 Stopped' }
                    $h += "<li><strong>$name</strong> $status &mdash; <a href='http://localhost:$port'>localhost:$port</a> | <a href='${networkUrl}:$port'>${networkUrl}:$port</a></li>"
                }
                $h += "</ul></body></html>"
                return $h
            }
        } else {
            $htmlContent = "<html><body><p>apps.json not found</p></body></html>"
        }

        $htmlContent | Out-File -FilePath $htmlFilePath -Encoding UTF8 -Force
        $response.ContentType   = 'text/html; charset=utf-8'
        $response.StatusCode    = 200
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
    } else {
        $response.StatusCode = 404
        $buffer = [System.Text.Encoding]::UTF8.GetBytes('404 - Not Found')
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
    }
    $response.OutputStream.Close()
}

try {
    while ($listener.IsListening) {
        $contextTask = $listener.GetContextAsync()
        while (-not $contextTask.IsCompleted) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Enter) {
                    Write-Host ""; Write-Host "Shutting down server..."
                    $listener.Stop(); break
                }
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $listener.IsListening) { break }
        if ($contextTask.IsCompleted -and -not $contextTask.IsFaulted) {
            & $requestHandler $contextTask.Result $htmlFilePath $SCRIPT_DIR
        }
    }
} catch {
    if ($_.Exception.Message -notlike '*stopped*' -and $_.Exception.Message -notlike '*closed*') {
        Write-Error "Server error: $($_.Exception.Message)"
    }
} finally {
    if ($null -ne $listener) {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
    Write-Host "Server stopped"
}
