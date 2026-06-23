<#
.SYNOPSIS
Host an HTML dashboard for all app URLs on port 1111.

.DESCRIPTION
Mirrors landing_page.sh from app_management_tmux.
Serves a live dashboard page via .NET HttpListener. HTML is regenerated on
every request so status indicators always reflect the current state.

.PARAMETER Port
The port to host the web server on. Default is 1111.

.NOTES
NETWORK ACCESS:
  Without admin: binds to localhost only.
  With admin (or after the one-time netsh command below): binds to all interfaces.

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

$ErrorActionPreference = 'Stop'

$SCRIPT_DIR = $PSScriptRoot
$libDir     = Join-Path $SCRIPT_DIR 'lib'

Import-Module -Force (Join-Path $libDir 'url_helpers.psm1') -ErrorAction Stop
Import-Module -Force (Join-Path $libDir 'app_helpers.psm1') -ErrorAction Stop

$htmlFilePath = Join-Path $SCRIPT_DIR 'app_index.html'

# ── HTML generation (mirrors generate_dashboard_html in dashboard.sh) ─────────
function New-DashboardHtml {
    param(
        [string]$NetworkUrl  = 'http://localhost',
        [string]$ExternalUrl = 'http://localhost'
    )

    $jsonFile = Join-Path $SCRIPT_DIR 'apps.json'
    if (-not (Test-Path $jsonFile)) {
        return "<html><body><p>apps.json not found at $jsonFile</p></body></html>"
    }

    $apps = @(Get-Content $jsonFile -Raw | ConvertFrom-Json)

    # Filter to apps with a valid port (safe - no strict mode property access)
    $appsWithPorts = @($apps | Where-Object {
        $p = $null
        if ($_.PSObject.Properties.Name -contains 'Port') { $p = $_.Port }
        $p -and -not [string]::IsNullOrWhiteSpace([string]$p) -and [int]$p -gt 0
    })

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>App Management Dashboard</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 { margin: 0; font-size: 2.5em; font-weight: 300; }
        .header p  { margin: 10px 0 0 0; opacity: 0.9; font-size: 1.1em; }
        .apps-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            padding: 30px;
        }
        .app-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            border-left: 4px solid #11998e;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .app-card:hover { transform: translateY(-2px); box-shadow: 0 10px 25px rgba(0,0,0,0.1); }
        .app-name { font-size: 1.3em; font-weight: 600; color: #2c3e50; margin-bottom: 10px; }
        .app-type {
            background: #e3f2fd;
            color: #1976d2;
            padding: 4px 8px;
            border-radius: 15px;
            font-size: 0.8em;
            display: inline-block;
            margin-bottom: 15px;
        }
        .app-type.streamlit { background: #ffebee; color: #c62828; }
        .app-type.django    { background: #e8f5e9; color: #2e7d32; }
        .app-type.flask     { background: #fff3e0; color: #ef6c00; }
        .app-type.dash      { background: #e3f2fd; color: #1565c0; }
        .app-type.process   { background: #f3e5f5; color: #6a1b9a; }
        .url-section { margin-bottom: 15px; }
        .url-label { font-weight: 600; color: #555; margin-bottom: 5px; font-size: 0.9em; }
        .url-container { display: flex; align-items: center; gap: 8px; margin-bottom: 5px; }
        .url-link {
            flex: 1;
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 8px 12px;
            text-decoration: none;
            color: #2c3e50;
            transition: background-color 0.2s;
            word-break: break-all;
            display: block;
        }
        .url-link:hover { background: #f0f8ff; border-color: #11998e; }
        .copy-btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.85em;
            transition: background 0.2s;
            white-space: nowrap;
        }
        .copy-btn:hover  { background: #5568d3; }
        .copy-btn:active { background: #4454b8; }
        .copy-btn.copied { background: #2ecc71; }
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666;
            border-top: 1px solid #eee;
        }
        .refresh-btn {
            background: #11998e;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 1em;
            margin-bottom: 20px;
        }
        .refresh-btn:hover { background: #0e7a6f; }
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-running { background: #2ecc71; }
        .status-stopped { background: #e74c3c; }
    </style>
    <script>
        function copyToClipboard(url, button) {
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(url).then(() => showCopySuccess(button))
                    .catch(() => fallbackCopy(url, button));
            } else {
                fallbackCopy(url, button);
            }
        }
        function fallbackCopy(url, button) {
            const ta = document.createElement('textarea');
            ta.value = url;
            ta.style.position = 'fixed'; ta.style.left = '-9999px'; ta.style.top = '-9999px';
            document.body.appendChild(ta); ta.focus(); ta.select();
            try {
                document.execCommand('copy') ? showCopySuccess(button) : showCopyFailed(button);
            } catch { showCopyFailed(button); }
            document.body.removeChild(ta);
        }
        function showCopySuccess(button) {
            const orig = button.textContent;
            button.textContent = '✓ Copied!'; button.classList.add('copied');
            setTimeout(() => { button.textContent = orig; button.classList.remove('copied'); }, 2000);
        }
        function showCopyFailed(button) {
            button.textContent = '✗ Failed';
            setTimeout(() => { button.textContent = '📋 Copy'; }, 2000);
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🪟 App Management Dashboard</h1>
            <p>Windows Server with psmux</p>
        </div>
        <div style="text-align: center; padding-top: 20px;">
            <button class="refresh-btn" onclick="location.reload()">🔄 Refresh</button>
        </div>
        <div class="apps-grid">
"@

    foreach ($app in $appsWithPorts) {
        $port      = [int]$app.Port
        $name      = $app.Name
        $appType   = if ($app.PSObject.Properties.Name -contains 'Type' -and $app.Type) { $app.Type } else { 'Process' }
        $nginxPath = if ($app.PSObject.Properties.Name -contains 'NginxPath') { $app.NginxPath } else { '' }
        $basePath  = if ($app.PSObject.Properties.Name -contains 'BasePath')  { $app.BasePath  } else { '' }

        $typeClass   = $appType.ToLower()
        $portInUse   = Test-PortInUse -Port $port
        $statusClass = if ($portInUse) { 'status-running' } else { 'status-stopped' }
        $statusText  = if ($portInUse) { 'Running' } else { 'Stopped' }

        # Build URLs — nginx-proxied apps use path-based URL (no port)
        if (-not [string]::IsNullOrWhiteSpace($nginxPath)) {
            $localhostUrl  = "http://localhost/$($nginxPath.TrimStart('/'))/"
            $networkAppUrl = "$NetworkUrl/$($nginxPath.TrimStart('/'))/"
            $externalAppUrl = "$ExternalUrl/$($nginxPath.TrimStart('/'))/"
        } else {
            $pathSuffix = if (-not [string]::IsNullOrWhiteSpace($basePath)) { "/$($basePath.TrimStart('/'))" } else { '' }
            $localhostUrl   = "http://localhost:$port$pathSuffix"
            $networkAppUrl  = "${NetworkUrl}:$port$pathSuffix"
            $externalAppUrl = "${ExternalUrl}:$port$pathSuffix"
        }

        $html += @"
            <div class="app-card">
                <div class="app-name">
                    $name
                    <span class="status-indicator $statusClass" title="$statusText"></span>
                </div>
                <span class="app-type $typeClass">$appType</span>
                <div class="url-section">
                    <div class="url-label">🏠 Localhost:</div>
                    <div class="url-container">
                        <a href="$localhostUrl" target="_blank" class="url-link">$localhostUrl</a>
                        <button class="copy-btn" onclick="copyToClipboard('$localhostUrl', this)">📋 Copy</button>
                    </div>
                </div>
                <div class="url-section">
                    <div class="url-label">🌐 Network:</div>
                    <div class="url-container">
                        <a href="$networkAppUrl" target="_blank" class="url-link">$networkAppUrl</a>
                        <button class="copy-btn" onclick="copyToClipboard('$networkAppUrl', this)">📋 Copy</button>
                    </div>
                </div>
                <div class="url-section">
                    <div class="url-label">🌍 External:</div>
                    <div class="url-container">
                        <a href="$externalAppUrl" target="_blank" class="url-link">$externalAppUrl</a>
                        <button class="copy-btn" onclick="copyToClipboard('$externalAppUrl', this)">📋 Copy</button>
                    </div>
                </div>
            </div>
"@
    }

    $html += @"
        </div>
        <div class="footer">
            <p>Generated by App Management Windows • Powered by psmux | $timestamp</p>
        </div>
    </div>
</body>
</html>
"@
    return $html
}

# ── Startup ───────────────────────────────────────────────────────────────────
$networkUrl  = Get-NetworkUrlPrefix
$externalUrl = Get-ExternalUrlPrefix

Write-Host "Detecting network configuration..."
Write-Host "  Network URL:  $networkUrl"
Write-Host "  External URL: $externalUrl"
Write-Host ""

# Generate initial HTML and save to file
if (Test-Path $htmlFilePath) {
    Write-Host "Dashboard found at: $htmlFilePath"
} else {
    Write-Host "Generating dashboard HTML..."
    $html = New-DashboardHtml -NetworkUrl $networkUrl -ExternalUrl $externalUrl
    $html | Out-File -FilePath $htmlFilePath -Encoding UTF8 -Force
    Write-Host "Dashboard generated and saved to: $htmlFilePath"
}

# ── HTTP server ───────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Net.Http

$candidatePorts = @($Port) + @(1112..1125) | Select-Object -Unique
$bindAddresses  = @('+', 'localhost')

$listener     = $null
$selectedPort = $Port
$actualBind   = $null
$started      = $false

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
    Write-Warning "To enable network access, run PowerShell as Administrator, or run:"
    Write-Warning "  netsh http add urlacl url=http://+:$selectedPort/ user=$env:USERDOMAIN\$env:USERNAME"
}

Write-Host "Starting HTTP server on port $selectedPort"
Write-Host ""
Write-Host "Access the dashboard at:"
Write-Host "  Network:   ${networkUrl}:$selectedPort"
Write-Host "  External:  ${externalUrl}:$selectedPort"
Write-Host "  Local:     http://localhost:$selectedPort"
Write-Host ""
Write-Host "Server running (PID: $PID)"
Write-Host "Press Enter to stop the server"

# ── Request handler ───────────────────────────────────────────────────────────
# Defined as a scriptblock so it can be called inline (no cross-scope issues)
$handleRequest = {
    param($context, $htmlFilePath, $SCRIPT_DIR)

    $request  = $context.Request
    $response = $context.Response
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - $($request.HttpMethod) $($request.Url.PathAndQuery)"

    if ($request.Url.PathAndQuery -eq '/' -or $request.Url.PathAndQuery -eq '/index.html') {
        # Re-import modules in this scope and regenerate HTML fresh on every request
        $libDir = Join-Path $SCRIPT_DIR 'lib'
        Import-Module -Force (Join-Path $libDir 'url_helpers.psm1') -ErrorAction SilentlyContinue
        Import-Module -Force (Join-Path $libDir 'app_helpers.psm1') -ErrorAction SilentlyContinue

        $networkUrl  = if (Get-Command Get-NetworkUrlPrefix  -ErrorAction SilentlyContinue) { Get-NetworkUrlPrefix  } else { 'http://localhost' }
        $externalUrl = if (Get-Command Get-ExternalUrlPrefix -ErrorAction SilentlyContinue) { Get-ExternalUrlPrefix } else { 'http://localhost' }

        $jsonFile = Join-Path $SCRIPT_DIR 'apps.json'
        if (Test-Path $jsonFile) {
            $apps = @(Get-Content $jsonFile -Raw | ConvertFrom-Json)
            $appsWithPorts = @($apps | Where-Object {
                $p = $null
                if ($_.PSObject.Properties.Name -contains 'Port') { $p = $_.Port }
                $p -and -not [string]::IsNullOrWhiteSpace([string]$p) -and [int]$p -gt 0
            })

            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $cards = ''
            foreach ($app in $appsWithPorts) {
                $port      = [int]$app.Port
                $name      = $app.Name
                $appType   = if ($app.PSObject.Properties.Name -contains 'Type' -and $app.Type) { $app.Type } else { 'Process' }
                $nginxPath = if ($app.PSObject.Properties.Name -contains 'NginxPath') { $app.NginxPath } else { '' }
                $basePath  = if ($app.PSObject.Properties.Name -contains 'BasePath')  { $app.BasePath  } else { '' }
                $typeClass   = $appType.ToLower()
                $portInUse   = (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) -ne $null
                $statusClass = if ($portInUse) { 'status-running' } else { 'status-stopped' }
                $statusText  = if ($portInUse) { 'Running' } else { 'Stopped' }
                if (-not [string]::IsNullOrWhiteSpace($nginxPath)) {
                    $localhostUrl   = "http://localhost/$($nginxPath.TrimStart('/'))/"
                    $networkAppUrl  = "$networkUrl/$($nginxPath.TrimStart('/'))/"
                    $externalAppUrl = "$externalUrl/$($nginxPath.TrimStart('/'))/"
                } else {
                    $pathSuffix = if (-not [string]::IsNullOrWhiteSpace($basePath)) { "/$($basePath.TrimStart('/'))" } else { '' }
                    $localhostUrl   = "http://localhost:$port$pathSuffix"
                    $networkAppUrl  = "${networkUrl}:$port$pathSuffix"
                    $externalAppUrl = "${externalUrl}:$port$pathSuffix"
                }
                $cards += @"
            <div class="app-card">
                <div class="app-name">$name <span class="status-indicator $statusClass" title="$statusText"></span></div>
                <span class="app-type $typeClass">$appType</span>
                <div class="url-section"><div class="url-label">🏠 Localhost:</div>
                    <div class="url-container"><a href="$localhostUrl" target="_blank" class="url-link">$localhostUrl</a><button class="copy-btn" onclick="copyToClipboard('$localhostUrl',this)">📋 Copy</button></div></div>
                <div class="url-section"><div class="url-label">🌐 Network:</div>
                    <div class="url-container"><a href="$networkAppUrl" target="_blank" class="url-link">$networkAppUrl</a><button class="copy-btn" onclick="copyToClipboard('$networkAppUrl',this)">📋 Copy</button></div></div>
                <div class="url-section"><div class="url-label">🌍 External:</div>
                    <div class="url-container"><a href="$externalAppUrl" target="_blank" class="url-link">$externalAppUrl</a><button class="copy-btn" onclick="copyToClipboard('$externalAppUrl',this)">📋 Copy</button></div></div>
            </div>
"@
            }

            $htmlContent = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>App Management Dashboard</title>
<style>
body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;margin:0;padding:20px;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh}
.container{max-width:1200px;margin:0 auto;background:white;border-radius:15px;box-shadow:0 20px 40px rgba(0,0,0,.1);overflow:hidden}
.header{background:linear-gradient(135deg,#11998e 0%,#38ef7d 100%);color:white;padding:30px;text-align:center}
.header h1{margin:0;font-size:2.5em;font-weight:300}.header p{margin:10px 0 0;opacity:.9;font-size:1.1em}
.apps-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(350px,1fr));gap:20px;padding:30px}
.app-card{background:#f8f9fa;border-radius:10px;padding:20px;border-left:4px solid #11998e;transition:transform .2s,box-shadow .2s}
.app-card:hover{transform:translateY(-2px);box-shadow:0 10px 25px rgba(0,0,0,.1)}
.app-name{font-size:1.3em;font-weight:600;color:#2c3e50;margin-bottom:10px}
.app-type{background:#e3f2fd;color:#1976d2;padding:4px 8px;border-radius:15px;font-size:.8em;display:inline-block;margin-bottom:15px}
.app-type.streamlit{background:#ffebee;color:#c62828}.app-type.django{background:#e8f5e9;color:#2e7d32}
.app-type.flask{background:#fff3e0;color:#ef6c00}.app-type.dash{background:#e3f2fd;color:#1565c0}.app-type.process{background:#f3e5f5;color:#6a1b9a}
.url-section{margin-bottom:15px}.url-label{font-weight:600;color:#555;margin-bottom:5px;font-size:.9em}
.url-container{display:flex;align-items:center;gap:8px;margin-bottom:5px}
.url-link{flex:1;background:white;border:1px solid #ddd;border-radius:5px;padding:8px 12px;text-decoration:none;color:#2c3e50;transition:background-color .2s;word-break:break-all;display:block}
.url-link:hover{background:#f0f8ff;border-color:#11998e}
.copy-btn{background:#667eea;color:white;border:none;padding:6px 12px;border-radius:4px;cursor:pointer;font-size:.85em;transition:background .2s;white-space:nowrap}
.copy-btn:hover{background:#5568d3}.copy-btn.copied{background:#2ecc71}
.footer{background:#f8f9fa;padding:20px;text-align:center;color:#666;border-top:1px solid #eee}
.refresh-btn{background:#11998e;color:white;border:none;padding:10px 20px;border-radius:5px;cursor:pointer;font-size:1em;margin-bottom:20px}
.refresh-btn:hover{background:#0e7a6f}
.status-indicator{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px}
.status-running{background:#2ecc71}.status-stopped{background:#e74c3c}
</style>
<script>
function copyToClipboard(url,btn){if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(url).then(()=>showCopySuccess(btn)).catch(()=>fallbackCopy(url,btn))}else{fallbackCopy(url,btn)}}
function fallbackCopy(url,btn){const ta=document.createElement('textarea');ta.value=url;ta.style.position='fixed';ta.style.left='-9999px';document.body.appendChild(ta);ta.focus();ta.select();try{document.execCommand('copy')?showCopySuccess(btn):showCopyFailed(btn)}catch{showCopyFailed(btn)}document.body.removeChild(ta)}
function showCopySuccess(btn){const t=btn.textContent;btn.textContent='✓ Copied!';btn.classList.add('copied');setTimeout(()=>{btn.textContent=t;btn.classList.remove('copied')},2000)}
function showCopyFailed(btn){btn.textContent='✗ Failed';setTimeout(()=>{btn.textContent='📋 Copy'},2000)}
</script>
</head><body><div class="container">
<div class="header"><h1>🪟 App Management Dashboard</h1><p>Windows Server with psmux</p></div>
<div style="text-align:center;padding-top:20px"><button class="refresh-btn" onclick="location.reload()">🔄 Refresh</button></div>
<div class="apps-grid">
$cards
</div>
<div class="footer"><p>Generated by App Management Windows • Powered by psmux | $timestamp</p></div>
</div></body></html>
"@
        } else {
            $htmlContent = "<html><body><p>apps.json not found</p></body></html>"
        }

        $htmlContent | Out-File -FilePath $htmlFilePath -Encoding UTF8 -Force
        $response.ContentType     = 'text/html; charset=utf-8'
        $response.StatusCode      = 200
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

# ── Server loop ───────────────────────────────────────────────────────────────
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
            & $handleRequest $contextTask.Result $htmlFilePath $SCRIPT_DIR
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
