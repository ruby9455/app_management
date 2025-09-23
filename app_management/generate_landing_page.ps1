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

# Import Url helpers module
try {
    $modulesRoot = Join-Path $PSScriptRoot 'Modules'
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'UrlHelpers.psm1')
} catch { throw "Failed to import UrlHelpers module from '$modulesRoot'. Error: $($_.Exception.Message)" }

# Load apps.json
$jsonFilePath = "$PSScriptRoot\apps.json"
Write-Host "Reading apps from: $jsonFilePath"

if (-not (Test-Path $jsonFilePath)) {
    throw "apps.json not found at $jsonFilePath"
}

$apps = Get-Content $jsonFilePath | ConvertFrom-Json

if (-not $apps -or (@($apps).Count -eq 0)) {
    Write-Host "No apps with ports found in apps.json."
    return
}

# Detect URL prefixes
$networkUrlPrefix = UrlHelpers\Get-NetworkUrlPrefix
$externalUrlPrefix = UrlHelpers\Get-ExternalUrlPrefix
$genericUrlPrefix  = UrlHelpers\Get-GenericUrlPrefix

Write-Host "Detected Network URL prefix: $networkUrlPrefix"
Write-Host "Detected External URL prefix: $externalUrlPrefix"
Write-Host "Detected Generic URL prefix: $genericUrlPrefix"

# Import Dashboard module
try {
    $modulesRoot = Join-Path $PSScriptRoot 'Modules'
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'Dashboard.psm1')
} catch { throw "Failed to import Dashboard module from '$modulesRoot'. Error: $($_.Exception.Message)" }

# Generate HTML content using shared module
Write-Host "Generating HTML index page..."
$htmlContent = Dashboard\New-AppDashboardHtml -Apps $apps -NetworkUrlPrefix $networkUrlPrefix -ExternalUrlPrefix $externalUrlPrefix -GenericUrlPrefix $genericUrlPrefix

# Save HTML file
$htmlFilePath = "$PSScriptRoot\app_index.html"
$htmlContent | Out-File -FilePath $htmlFilePath -Encoding UTF8
Write-Host "HTML index page saved to: $htmlFilePath"

# Start HTTP server (with automatic fallback if the default port is taken or reserved)
Write-Host "Starting HTTP server..."
Write-Host "Press Ctrl+C to stop the server"

# Simple HTTP server using .NET HttpListener
Add-Type -AssemblyName System.Net.Http

# Helper to discover a free TCP port (loopback only)
function Get-FreeTcpPort {
    $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $tcp.Start()
    $port = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port
    $tcp.Stop()
    return $port
}

$listener = [System.Net.HttpListener]::new()

$selectedPort = $Port
$candidatePorts = @($Port) + (1112..1125) + (Get-FreeTcpPort)
$candidatePorts = $candidatePorts | Select-Object -Unique

$started = $false
foreach ($p in $candidatePorts) {
    try {
        $listener.Prefixes.Clear()
        $listener.Prefixes.Add("http://$HostAddress`:$p/")
        $listener.Start()
        $selectedPort = $p
        $started = $true
        break
    } catch {
        $msg = $_.Exception.Message
        Write-Warning "Failed to bind http://$HostAddress`:$p/ - $msg"
        continue
    }
}

if (-not $started) {
    throw "Unable to start HTTP server; all candidate ports failed."
}

Write-Host "Server started successfully on http://$HostAddress`:$selectedPort/"
Write-Host "Open your browser and go to: http://$HostAddress`:$selectedPort"

try {
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
    Write-Error "Server error: $($_.Exception.Message)"
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
