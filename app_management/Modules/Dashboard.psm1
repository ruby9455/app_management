Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $modulePath = Split-Path $PSScriptRoot -Parent
    if (-not (Get-Module -Name UrlHelpers -ErrorAction SilentlyContinue)) {
        Import-Module -Force (Join-Path $modulePath 'Modules/UrlHelpers.psm1') -ErrorAction SilentlyContinue
    }
    if (-not (Get-Module -Name NetworkHelpers -ErrorAction SilentlyContinue)) {
        Import-Module -Force (Join-Path $modulePath 'Modules/NetworkHelpers.psm1') -ErrorAction SilentlyContinue
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

    # Ensure we have apps array
    if (-not $Apps) { return "<html><body><p>No apps provided.</p></body></html>" }
    
    # Filter to apps with ports - make filtering more robust
    $appsWithPorts = @($Apps | Where-Object { 
        if ($_ -eq $null) { return $false }
        if ($_ -is [System.Management.Automation.PSCustomObject] -or $_ -is [hashtable]) {
            $port = $_.Port
            return $port -and ([int]$port) -gt 0
        }
        return $false
    })
    
    if ($appsWithPorts.Count -eq 0) { return "<html><body><p>No apps with ports.</p></body></html>" }

    if ([string]::IsNullOrWhiteSpace($NetworkUrlPrefix)) { 
        if (Get-Command -Name Get-NetworkUrlPrefix -ErrorAction SilentlyContinue) {
            $NetworkUrlPrefix = Get-NetworkUrlPrefix
        } else {
            $NetworkUrlPrefix = "http://localhost"
        }
    }
    if ([string]::IsNullOrWhiteSpace($ExternalUrlPrefix)) { 
        if (Get-Command -Name Get-ExternalUrlPrefix -ErrorAction SilentlyContinue) {
            $ExternalUrlPrefix = Get-ExternalUrlPrefix
        } else {
            $ExternalUrlPrefix = "http://localhost"
        }
    }
    if ([string]::IsNullOrWhiteSpace($GenericUrlPrefix)) { 
        if (Get-Command -Name Get-GenericUrlPrefix -ErrorAction SilentlyContinue) {
            $GenericUrlPrefix = Get-GenericUrlPrefix
        } else {
            $GenericUrlPrefix = "http://localhost"
        }
    }

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
        .url-container { display: flex; align-items: center; gap: 8px; margin-bottom: 5px; }
        .url-link { flex: 1; }
        .copy-btn { background: #667eea; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; font-size: 0.85em; transition: background 0.2s; white-space: nowrap; }
        .copy-btn:hover { background: #5568d3; }
        .copy-btn:active { background: #4454b8; }
        .copy-btn.copied { background: #2ecc71; }
        .footer { background: #f8f9fa; padding: 20px; text-align: center; color: #666; border-top: 1px solid #eee; }
        .refresh-btn { background: #4facfe; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; font-size: 1em; margin-bottom: 20px; }
        .refresh-btn:hover { background: #3d8bfe; }
    </style>
    <script>
        // Simple ping check to style links if targets are alive (optional enhancement)
        async function ping(url, anchor){ try{ const c = new AbortController(); const t = setTimeout(()=>c.abort(), 1500); const r = await fetch(url, {mode:'no-cors', signal:c.signal}); anchor.classList.add('up'); clearTimeout(t);} catch(e){ anchor.classList.add('down'); } }
        
        // Copy URL to clipboard functionality
        function copyToClipboard(url, button) {
            navigator.clipboard.writeText(url).then(() => {
                const originalText = button.textContent;
                button.textContent = '✓ Copied!';
                button.classList.add('copied');
                setTimeout(() => {
                    button.textContent = originalText;
                    button.classList.remove('copied');
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy:', err);
                button.textContent = '✗ Failed';
                setTimeout(() => {
                    button.textContent = '📋 Copy';
                }, 2000);
            });
        }
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
        $portInUse = $false
        if (Get-Command -Name Test-PortInUse -ErrorAction SilentlyContinue) {
            $portInUse = Test-PortInUse -Port $port
        }
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
                    <div class="url-container">
                        <a href="$localUrl" target="_blank" class="url-link">$localUrl</a>
                        <button class="copy-btn" onclick="copyToClipboard('$localUrl', this)" title="Copy to clipboard">📋 Copy</button>
                    </div>
                </div>
                <div class="url-section">
                    <div class="url-label">🌐 Network URL</div>
                    <div class="url-container">
                        <a href="$networkUrl" target="_blank" class="url-link">$networkUrl</a>
                        <button class="copy-btn" onclick="copyToClipboard('$networkUrl', this)" title="Copy to clipboard">📋 Copy</button>
                    </div>
                </div>
                <div class="url-section">
                    <div class="url-label">🔗 Generic URL</div>
                    <div class="url-container">
                        <a href="$genericUrl" target="_blank" class="url-link">$genericUrl</a>
                        <button class="copy-btn" onclick="copyToClipboard('$genericUrl', this)" title="Copy to clipboard">📋 Copy</button>
                    </div>
                </div>
                <div class="url-section">
                    <div class="url-label">🌍 External URL</div>
                    <div class="url-container">
                        <a href="$externalUrl" target="_blank" class="url-link">$externalUrl</a>
                        <button class="copy-btn" onclick="copyToClipboard('$externalUrl', this)" title="Copy to clipboard">📋 Copy</button>
                    </div>
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
