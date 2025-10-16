Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-AppDashboardHtml {
    <#
    .SYNOPSIS
    Generates a simple HTML dashboard listing app links for internal/external access.

    .PARAMETER Apps
    Array of app objects/hashtables with fields: Name, Type, AppPath, IndexPath, Port, BasePath.

    .PARAMETER NetworkUrlPrefix
    The local/network URL prefix like http://192.168.1.10

    .PARAMETER ExternalUrlPrefix
    The external/public URL prefix like http://203.0.113.10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Apps,
        [Parameter(Mandatory)] [string]$NetworkUrlPrefix,
        [Parameter(Mandatory)] [string]$ExternalUrlPrefix,
        [string]$GenericUrlPrefix
    )

    function Get-FieldValueLocal {
        param([object]$o, [string]$Name)
        if ($null -eq $o) { return $null }
        if ($o -is [hashtable]) { return $o[$Name] }
        return ($o.$Name)
    }

    $rows = @()
    foreach ($app in $Apps) {
        $name = Get-FieldValueLocal $app 'Name'
        $type = Get-FieldValueLocal $app 'Type'
        $port = Get-FieldValueLocal $app 'Port'
        $basePath = Get-FieldValueLocal $app 'BasePath'
        $indexPath = Get-FieldValueLocal $app 'IndexPath'

        $internal = ''
        $external = ''
        $generic  = ''
        if ($type -and $type -match '^(?i:streamlit|dash|flask)$' -and $port) {
            $bp = if ($basePath) { $basePath.Trim('/') } else { '' }
            $pathSuffix = if ($bp) { "/$bp" } else { '' }
            $internal = "${NetworkUrlPrefix}:$port$pathSuffix"
            $external = "${ExternalUrlPrefix}:$port$pathSuffix"
            if (-not [string]::IsNullOrWhiteSpace($GenericUrlPrefix)) { $generic = "${GenericUrlPrefix}:$port$pathSuffix" }
        } elseif ($type -and $type -match '^(?i:django)$' -and $port) {
            # Django default host should be 127.0.0.1 for development
            $internal = "http://127.0.0.1:$port"
            $external = "${ExternalUrlPrefix}:$port"
            if (-not [string]::IsNullOrWhiteSpace($GenericUrlPrefix)) { $generic = "${GenericUrlPrefix}:$port" }
        } else {
            # No port => no runnable URL, show placeholder
            $internal = '-'
            $external = '-'
            $generic  = '-'
        }

        $rows += @"
            <tr>
                <td>$([System.Web.HttpUtility]::HtmlEncode($name))</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($type))</td>
                <td>$(if ($internal -ne '-') { "<a href='$internal' target='_blank'>$internal</a>" } else { '-' })</td>
                <td>$(if ($generic -and $generic -ne '-') { "<a href='$generic' target='_blank'>$generic</a>" } else { '-' })</td>
                <td>$(if ($external -ne '-') { "<a href='$external' target='_blank'>$external</a>" } else { '-' })</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($indexPath))</td>
            </tr>
"@
    }

    $tableRows = ($rows -join "`n")
    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Apps Dashboard</title>
  <style>
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin: 2rem; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; }
    th { background: #f4f4f4; text-align: left; }
    tr:nth-child(even) { background: #fafafa; }
    caption { text-align: left; font-size: 1.25rem; margin-bottom: .5rem; }
  </style>
  <script>
    function filterTable() {
      const q = document.getElementById('q').value.toLowerCase();
      const rows = document.querySelectorAll('#apps tbody tr');
      rows.forEach(r => {
        const text = r.innerText.toLowerCase();
        r.style.display = text.includes(q) ? '' : 'none';
      });
    }
  </script>
  <link rel="icon" href="data:,">
  <meta http-equiv="Cache-Control" content="no-store" />
  <meta http-equiv="Pragma" content="no-cache" />
  <meta http-equiv="Expires" content="0" />
  <base target="_blank">
  <meta name="referrer" content="no-referrer" />
  <meta http-equiv="Content-Security-Policy" content="default-src 'self' 'unsafe-inline' data:;">
  <meta http-equiv="Permissions-Policy" content="geolocation=(), microphone=(), camera=()">
  <meta http-equiv="X-Content-Type-Options" content="nosniff" />
</head>
<body>
  <h1>Apps Dashboard</h1>
    <p>Internal prefix: <code>$NetworkUrlPrefix</code> | Generic prefix: <code>$GenericUrlPrefix</code> | External prefix: <code>$ExternalUrlPrefix</code></p>
  <input id="q" type="search" placeholder="Filter apps..." oninput="filterTable()" style="padding:.5rem; width: 50%" />
  <table id="apps">
    <caption>Available Applications</caption>
    <thead>
      <tr>
        <th>Name</th>
        <th>Type</th>
    <th>Internal URL</th>
    <th>Generic URL</th>
    <th>External URL</th>
        <th>Index Path</th>
      </tr>
    </thead>
    <tbody>
      $tableRows
    </tbody>
  </table>
</body>
</html>
"@

    return $html
}

Export-ModuleMember -Function New-AppDashboardHtml
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    if (-not (Get-Module -Name UrlHelpers -ListAvailable)) {
        Import-Module -Force (Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules/UrlHelpers.psm1')
    }
    if (-not (Get-Module -Name NetworkHelpers -ListAvailable)) {
        Import-Module -Force (Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules/NetworkHelpers.psm1')
    }
} catch { }

function New-AppDashboardHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [array]$Apps,
        [string]$NetworkUrlPrefix,
        [string]$ExternalUrlPrefix,
        [string]$GenericUrlPrefix
    )

    # Filter to apps with ports
    $appsWithPorts = $Apps | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Port' -and $_.Port -and $_.Port -gt 0 }
    if (-not $appsWithPorts -or (@($appsWithPorts).Count -eq 0)) { return "<html><body><p>No apps with ports.</p></body></html>" }

    if ([string]::IsNullOrWhiteSpace($NetworkUrlPrefix)) { $NetworkUrlPrefix = Get-NetworkUrlPrefix }
    if ([string]::IsNullOrWhiteSpace($ExternalUrlPrefix)) { $ExternalUrlPrefix = Get-ExternalUrlPrefix }
    if ([string]::IsNullOrWhiteSpace($GenericUrlPrefix)) { $GenericUrlPrefix = Get-GenericUrlPrefix }

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
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
            font-weight: 300;
        }
        .header p {
            margin: 10px 0 0 0;
            opacity: 0.9;
            font-size: 1.1em;
        }
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
            border-left: 4px solid #4facfe;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .app-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        }
        .app-name {
            font-size: 1.3em;
            font-weight: 600;
            color: #2c3e50;
            margin-bottom: 10px;
        }
        .app-type {
            background: #e3f2fd;
            color: #1976d2;
            padding: 4px 8px;
            border-radius: 15px;
            font-size: 0.8em;
            display: inline-block;
            margin-bottom: 15px;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-left: 10px;
            vertical-align: middle;
        }
        .status-running {
            background: #2ecc71;
            box-shadow: 0 0 8px rgba(46, 204, 113, 0.6);
        }
        .status-stopped {
            background: #e74c3c;
            box-shadow: 0 0 8px rgba(231, 76, 60, 0.6);
        }
        .url-section { margin-bottom: 15px; }
        .url-label { font-weight: 600; color: #555; margin-bottom: 5px; font-size: 0.9em; }
        .url-link {
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 8px 12px;
            margin-bottom: 5px;
            display: block;
            text-decoration: none;
            color: #2c3e50;
            transition: background-color 0.2s;
            word-break: break-all;
        }
        .url-link:hover { background: #f0f8ff; border-color: #4facfe; }
        .url-link:active { background: #e3f2fd; }
        .footer { background: #f8f9fa; padding: 20px; text-align: center; color: #666; border-top: 1px solid #eee; }
        .refresh-btn { background: #4facfe; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; font-size: 1em; margin-bottom: 20px; }
        .refresh-btn:hover { background: #3d8bfe; }
    </style>
    <script>
        // Simple ping check to style links if targets are alive (optional enhancement)
        async function ping(url, anchor){ try{ const c = new AbortController(); const t = setTimeout(()=>c.abort(), 1500); const r = await fetch(url, {mode:'no-cors', signal:c.signal}); anchor.classList.add('up'); clearTimeout(t);} catch(e){ anchor.classList.add('down'); } }
    </script>
    <style>.url-link.up{border-color:#2ecc71;background:#ecf9f1}.url-link.down{border-color:#e74c3c;background:#fdecea}</style>
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
        $port = $app.Port
        $basePathStr = if ($app.PSObject.Properties.Name -contains 'BasePath' -and $app.BasePath -and ([string]::IsNullOrWhiteSpace([string]$app.BasePath) -eq $false)) { "/$($app.BasePath)" } else { "" }
        $appName = $app.Name
        $appType = $app.Type

        # Check if port is in use
        $portInUse = Test-PortInUse -Port $port
        $statusClass = if ($portInUse) { "status-running" } else { "status-stopped" }
        $statusText = if ($portInUse) { "Running" } else { "Stopped" }

        # Build URLs with special-case for Django network URL to use 127.0.0.1
        $localUrl = "http://localhost:$port$basePathStr"
        if ($appType -and $appType -ieq 'Django') {
            $networkUrl = "http://127.0.0.1:$port"
        } else {
            $networkUrl = "$NetworkUrlPrefix`:$port$basePathStr"
        }
    $externalUrl = "$ExternalUrlPrefix`:$port$basePathStr"
    $genericUrl = "$GenericUrlPrefix`:$port$basePathStr"

        $html += @"
            <div class="app-card">
                <div class="app-name">$appName<span class="status-indicator $statusClass" title="$statusText"></span></div>
                <div class="app-type">$appType</div>
                <div class="url-section">
                    <div class="url-label">🏠 Local URL</div>
                    <a href="$localUrl" target="_blank" class="url-link">$localUrl</a>
                </div>
                <div class="url-section">
                    <div class="url-label">🌐 Network URL</div>
                    <a href="$networkUrl" target="_blank" class="url-link">$networkUrl</a>
                </div>
                <div class="url-section">
                    <div class="url-label">🔗 Generic URL</div>
                    <a href="$genericUrl" target="_blank" class="url-link">$genericUrl</a>
                </div>
                <div class="url-section">
                    <div class="url-label">🌍 External URL</div>
                    <a href="$externalUrl" target="_blank" class="url-link">$externalUrl</a>
                </div>
            </div>
"@
    }

    $html += @"
        </div>
        <div class="footer">
            <p>Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Network: $NetworkUrlPrefix | Generic: $GenericUrlPrefix | External: $ExternalUrlPrefix</p>
        </div>
    </div>
</body>
</html>
"@

    return $html
}

Export-ModuleMember -Function 'New-AppDashboardHtml'
