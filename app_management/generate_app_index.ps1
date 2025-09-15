<#
.SYNOPSIS
Generate an HTML index page with all app URLs and start a web server on port 1111.

.DESCRIPTION
This script reads apps from apps.json, generates an HTML page with all app URLs,
and starts a simple HTTP server on port 1111 to host the index page.

.PARAMETER Port
The port to host the web server on. Default is 1111.

.PARAMETER HostAddress
The host address to bind to. Default is localhost.

.EXAMPLE
./generate_app_index.ps1

.EXAMPLE
./generate_app_index.ps1 -Port 8080 -HostAddress "0.0.0.0"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 1111,
    
    [Parameter(Mandatory = $false)]
    [string]$HostAddress = "localhost"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dynamic URL prefix detection functions
function Get-NetworkUrlPrefix {
    try {
        # Get the primary network adapter's IP address
        $networkAdapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -notlike "127.*" -and 
            $_.IPAddress -notlike "169.254.*" -and
            $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual"
        } | Sort-Object InterfaceIndex | Select-Object -First 1
        
        if ($networkAdapter) {
            return "http://$($networkAdapter.IPAddress)"
        }
        
        # Fallback: try to get any non-loopback IPv4 address
        $fallbackAdapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*"
        } | Select-Object -First 1
        
        if ($fallbackAdapter) {
            return "http://$($fallbackAdapter.IPAddress)"
        }
    } catch {
        Write-Warning "Failed to detect network IP: $($_.Exception.Message)"
    }
    
    # Ultimate fallback
    return "http://10.17.62.232"
}

function Get-ExternalUrlPrefix {
    try {
        # Try to get external IP using a web service
        $externalIP = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5 -ErrorAction Stop
        if ($externalIP -and $externalIP -match '^\d+\.\d+\.\d+\.\d+$') {
            return "http://$externalIP"
        }
    } catch {
        Write-Warning "Failed to detect external IP via ipify.org: $($_.Exception.Message)"
    }
    
    try {
        # Alternative service
        $externalIP = Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 5 -ErrorAction Stop
        if ($externalIP -and $externalIP -match '^\d+\.\d+\.\d+\.\d+$') {
            return "http://$externalIP"
        }
    } catch {
        Write-Warning "Failed to detect external IP via ifconfig.me: $($_.Exception.Message)"
    }
    
    # Ultimate fallback
    return "http://203.1.252.70"
}

# Load apps.json
$jsonFilePath = "$PSScriptRoot\apps.json"
Write-Host "Reading apps from: $jsonFilePath"

if (-not (Test-Path $jsonFilePath)) {
    throw "apps.json not found at $jsonFilePath"
}

$apps = Get-Content $jsonFilePath | ConvertFrom-Json

# Filter to apps with ports
$apps = $apps | Where-Object { $_.PSObject.Properties.Name -contains 'Port' -and $_.Port -and $_.Port -gt 0 }

if (-not $apps -or (@($apps).Count -eq 0)) {
    Write-Host "No apps with ports found in apps.json."
    return
}

# Detect URL prefixes
$networkUrlPrefix = Get-NetworkUrlPrefix
$externalUrlPrefix = Get-ExternalUrlPrefix

Write-Host "Detected Network URL prefix: $networkUrlPrefix"
Write-Host "Detected External URL prefix: $externalUrlPrefix"

# Generate HTML content
function Generate-HtmlIndex {
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
        .url-section {
            margin-bottom: 15px;
        }
        .url-label {
            font-weight: 600;
            color: #555;
            margin-bottom: 5px;
            font-size: 0.9em;
        }
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
        .url-link:hover {
            background: #f0f8ff;
            border-color: #4facfe;
        }
        .url-link:active {
            background: #e3f2fd;
        }
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666;
            border-top: 1px solid #eee;
        }
        .refresh-btn {
            background: #4facfe;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 1em;
            margin-bottom: 20px;
        }
        .refresh-btn:hover {
            background: #3d8bfe;
        }
    </style>
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

    foreach ($app in $apps) {
        $port = $app.Port
        $basePath = if ($app.PSObject.Properties.Name -contains 'BasePath' -and $app.BasePath) { "/$($app.BasePath)" } else { "" }
        
        $html += @"
            <div class="app-card">
                <div class="app-name">$($app.Name)</div>
                <div class="app-type">$($app.Type)</div>
                
                <div class="url-section">
                    <div class="url-label">🏠 Local URL</div>
                    <a href="http://localhost:$port$basePath" target="_blank" class="url-link">
                        http://localhost:$port$basePath
                    </a>
                </div>
                
                <div class="url-section">
                    <div class="url-label">🌐 Network URL</div>
                    <a href="$networkUrlPrefix`:$port$basePath" target="_blank" class="url-link">
                        $networkUrlPrefix`:$port$basePath
                    </a>
                </div>
                
                <div class="url-section">
                    <div class="url-label">🌍 External URL</div>
                    <a href="$externalUrlPrefix`:$port$basePath" target="_blank" class="url-link">
                        $externalUrlPrefix`:$port$basePath
                    </a>
                </div>
            </div>
"@
    }

    $html += @"
        </div>
        
        <div class="footer">
            <p>Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Network: $networkUrlPrefix | External: $externalUrlPrefix</p>
        </div>
    </div>
</body>
</html>
"@

    return $html
}

# Generate HTML content
Write-Host "Generating HTML index page..."
$htmlContent = Generate-HtmlIndex

# Save HTML file
$htmlFilePath = "$PSScriptRoot\app_index.html"
$htmlContent | Out-File -FilePath $htmlFilePath -Encoding UTF8
Write-Host "HTML index page saved to: $htmlFilePath"

# Start HTTP server
Write-Host "Starting HTTP server on $HostAddress`:$Port..."
Write-Host "Open your browser and go to: http://$HostAddress`:$Port"
Write-Host "Press Ctrl+C to stop the server"

# Simple HTTP server using .NET HttpListener
Add-Type -AssemblyName System.Net.Http

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://$HostAddress`:$Port/")

try {
    $listener.Start()
    Write-Host "Server started successfully!"
    
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - $($request.HttpMethod) $($request.Url.PathAndQuery)"
        
        if ($request.Url.PathAndQuery -eq "/" -or $request.Url.PathAndQuery -eq "/index.html") {
            # Serve the HTML file
            $response.ContentType = "text/html; charset=utf-8"
            $response.StatusCode = 200
            
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        } else {
            # 404 for other paths
            $response.StatusCode = 404
            $response.ContentType = "text/plain"
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("404 - Not Found")
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        
        $response.OutputStream.Close()
    }
} catch {
    Write-Error "Error starting server: $($_.Exception.Message)"
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
