<#
.SYNOPSIS
Host an HTML dashboard for all app URLs on port 1111.

.DESCRIPTION
This script hosts a dashboard page for all app URLs. It checks if app_index.html exists,
and if not, generates it using Dashboard.psm1. The page is served via HTTP on port 1111.
The refresh button on the page or browser refresh regenerates the HTML with the latest data.

.PARAMETER Port
The port to host the web server on. Default is 1111.

.PARAMETER HostAddress
The host address to bind to. Default is localhost.

.EXAMPLE
./generate_landing_page.ps1

.EXAMPLE
./generate_landing_page.ps1 -Port 8080 -HostAddress "0.0.0.0"
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

# Import Dashboard module (single source of truth for HTML generation)
try {
    $modulesRoot = Join-Path $PSScriptRoot 'Modules'
    Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'Dashboard.psm1')
} catch { throw "Failed to import Dashboard module from '$modulesRoot'. Error: $($_.Exception.Message)" }

# Path to HTML file
$htmlFilePath = "$PSScriptRoot\app_index.html"

# Function to generate HTML using Dashboard module
function Get-DashboardHtml {
    # Import Url helpers module for URL prefix detection
    try {
        $modulesRoot = Join-Path $PSScriptRoot 'Modules'
        if (-not (Get-Module -Name UrlHelpers -ErrorAction SilentlyContinue)) {
            Import-Module -Force -ErrorAction Stop (Join-Path $modulesRoot 'UrlHelpers.psm1')
        }
    } catch { Write-Warning "Could not import UrlHelpers module. URL prefixes will use defaults." }

    # Load apps.json
    $jsonFilePath = "$PSScriptRoot\apps.json"
    
    if (-not (Test-Path $jsonFilePath)) {
        throw "apps.json not found at $jsonFilePath"
    }

    $apps = Get-Content $jsonFilePath | ConvertFrom-Json

    if (-not $apps -or (@($apps).Count -eq 0)) {
        return "<html><body><p>No apps found in apps.json.</p></body></html>"
    }

    # Detect URL prefixes (with fallbacks if module not available)
    $networkUrlPrefix = if (Get-Command -Name Get-NetworkUrlPrefix -ErrorAction SilentlyContinue) { 
        Get-NetworkUrlPrefix 
    } else { 
        "http://localhost" 
    }
    
    $externalUrlPrefix = if (Get-Command -Name Get-ExternalUrlPrefix -ErrorAction SilentlyContinue) { 
        Get-ExternalUrlPrefix 
    } else { 
        "http://localhost" 
    }
    
    $genericUrlPrefix = if (Get-Command -Name Get-GenericUrlPrefix -ErrorAction SilentlyContinue) { 
        Get-GenericUrlPrefix 
    } else { 
        "http://localhost" 
    }

    # Generate HTML using Dashboard module
    $htmlContent = Dashboard\New-AppDashboardHtml -Apps $apps `
        -NetworkUrlPrefix $networkUrlPrefix `
        -ExternalUrlPrefix $externalUrlPrefix `
        -GenericUrlPrefix $genericUrlPrefix

    return $htmlContent
}

# Check if HTML file exists, if not generate it
if (Test-Path $htmlFilePath) {
    Write-Host "HTML dashboard found at: $htmlFilePath"
} else {
    Write-Host "Generating HTML dashboard..."
    $htmlContent = Get-DashboardHtml
    $htmlContent | Out-File -FilePath $htmlFilePath -Encoding UTF8
    Write-Host "HTML dashboard generated and saved to: $htmlFilePath"
}

# Start HTTP server
Write-Host "Starting HTTP server on http://$HostAddress`:$Port/"
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
            # Generate fresh HTML on each request (enables refresh functionality)
            $htmlContent = Get-DashboardHtml
            
            # Also save it to file for reference
            $htmlContent | Out-File -FilePath $htmlFilePath -Encoding UTF8 -Force
            
            # Serve the HTML
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
