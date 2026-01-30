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

.NOTES
NETWORK ACCESS (Admin vs Normal User):

Windows HttpListener has security restrictions on URL bindings:

  - WITHOUT ADMIN: Can only bind to "localhost" or "127.0.0.1". Other users on the 
    network cannot access the dashboard via your IP or computer name.

  - WITH ADMIN: Can bind to "+" (all interfaces), allowing access via Network URL,
    External URL, and computer name from other machines.

The script automatically tries to bind to "+" first, then falls back to "localhost"
with a warning if admin privileges are not available.

ONE-TIME WORKAROUND (no admin needed after setup):
Run this command ONCE as Administrator to permanently allow your user to host on port 1111:

    netsh http add urlacl url=http://+:1111/ user=DOMAIN\username

Replace DOMAIN\username with your actual username (e.g., SAH0223908\rchan09).

To remove the reservation later:

    netsh http delete urlacl url=http://+:1111/

.EXAMPLE
./landing_page.ps1

.EXAMPLE
./landing_page.ps1 -Port 8080
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
    Write-Host "Dashboard found at: $htmlFilePath" -ForegroundColor Blue
} else {
    Write-Host "Generating dashboard HTML..." -ForegroundColor Blue
    $htmlContent = Get-DashboardHtml
    $htmlContent | Out-File -FilePath $htmlFilePath -Encoding UTF8
    Write-Host "Dashboard generated and saved to: $htmlFilePath" -ForegroundColor Green
}

# Detect URL prefixes for display
$displayNetworkUrl = if (Get-Command -Name Get-NetworkUrlPrefix -ErrorAction SilentlyContinue) { Get-NetworkUrlPrefix } else { "http://localhost" }
$displayExternalUrl = if (Get-Command -Name Get-ExternalUrlPrefix -ErrorAction SilentlyContinue) { Get-ExternalUrlPrefix } else { "http://localhost" }
$displayGenericUrl = if (Get-Command -Name Get-GenericUrlPrefix -ErrorAction SilentlyContinue) { Get-GenericUrlPrefix } else { "http://localhost" }

Write-Host "Detecting network configuration..." -ForegroundColor Blue
Write-Host "  Network URL:  $displayNetworkUrl" -ForegroundColor Cyan
Write-Host "  External URL: $displayExternalUrl" -ForegroundColor Cyan
Write-Host "  Generic URL:  $displayGenericUrl" -ForegroundColor Cyan
Write-Host ""

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

$listener = $null

$selectedPort = $Port
$candidatePorts = @($Port) + (1112..1125) + (Get-FreeTcpPort)
$candidatePorts = $candidatePorts | Select-Object -Unique

# Try binding to "+" (all interfaces) first, fall back to localhost if no admin rights
$bindAddresses = @("+", "localhost")
if ($HostAddress -ne "localhost") {
    # User specified a custom address, try it first
    $bindAddresses = @($HostAddress) + $bindAddresses
}

$started = $false
$actualBindAddress = $null
foreach ($bindAddr in $bindAddresses) {
    foreach ($p in $candidatePorts) {
        try {
            # Create a fresh listener for each attempt
            $listener = [System.Net.HttpListener]::new()
            $listener.Prefixes.Add("http://${bindAddr}:$p/")
            $listener.Start()
            $selectedPort = $p
            $actualBindAddress = $bindAddr
            $started = $true
            break
        } catch {
            $msg = $_.Exception.Message
            if ($bindAddr -eq "+") {
                # Silently skip + binding failure (likely permission issue)
            } else {
                Write-Warning "Failed to bind http://${bindAddr}:$p/ - $msg"
            }
            if ($null -ne $listener) {
                try { $listener.Close() } catch { }
                $listener = $null
            }
            continue
        }
    }
    if ($started) { break }
}

if (-not $started) {
    throw "Unable to start HTTP server; all candidate ports failed."
}

# Warn if only localhost binding succeeded (network access won't work)
if ($actualBindAddress -eq "localhost") {
    Write-Host ""
    Write-Warning "Server bound to localhost only. Network URLs will not work."
    Write-Warning "To enable network access, run PowerShell as Administrator."
    Write-Host ""
}

Write-Host "Starting HTTP server on port $selectedPort" -ForegroundColor Green
Write-Host ""
Write-Host "Access the dashboard at:"
Write-Host "  Network:   ${displayNetworkUrl}:$selectedPort" -ForegroundColor Green
Write-Host "  External:  ${displayExternalUrl}:$selectedPort" -ForegroundColor Green
Write-Host "  Local:     http://localhost:$selectedPort" -ForegroundColor Green
Write-Host ""
Write-Host "Server running (PID: $PID)" -ForegroundColor Cyan
Write-Host "Press Enter to stop the server" -ForegroundColor Cyan

# Script block for handling HTTP requests
$requestHandler = {
    param($context, $htmlFilePath, $PSScriptRoot)
    
    $request = $context.Request
    $response = $context.Response
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - $($request.HttpMethod) $($request.Url.PathAndQuery)"
    
    if ($request.Url.PathAndQuery -eq "/" -or $request.Url.PathAndQuery -eq "/index.html") {
        # Import modules for HTML generation
        $modulesRoot = Join-Path $PSScriptRoot 'Modules'
        Import-Module -Force -ErrorAction SilentlyContinue (Join-Path $modulesRoot 'Dashboard.psm1')
        Import-Module -Force -ErrorAction SilentlyContinue (Join-Path $modulesRoot 'UrlHelpers.psm1')
        
        # Load apps.json
        $jsonFilePath = "$PSScriptRoot\apps.json"
        if (Test-Path $jsonFilePath) {
            $apps = Get-Content $jsonFilePath | ConvertFrom-Json
            
            $networkUrlPrefix = if (Get-Command -Name Get-NetworkUrlPrefix -ErrorAction SilentlyContinue) { 
                Get-NetworkUrlPrefix 
            } else { "http://localhost" }
            
            $externalUrlPrefix = if (Get-Command -Name Get-ExternalUrlPrefix -ErrorAction SilentlyContinue) { 
                Get-ExternalUrlPrefix 
            } else { "http://localhost" }
            
            $genericUrlPrefix = if (Get-Command -Name Get-GenericUrlPrefix -ErrorAction SilentlyContinue) { 
                Get-GenericUrlPrefix 
            } else { "http://localhost" }
            
            $htmlContent = Dashboard\New-AppDashboardHtml -Apps $apps `
                -NetworkUrlPrefix $networkUrlPrefix `
                -ExternalUrlPrefix $externalUrlPrefix `
                -GenericUrlPrefix $genericUrlPrefix
        } else {
            $htmlContent = "<html><body><p>apps.json not found</p></body></html>"
        }
        
        # Save to file for reference
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

try {
    # Use async pattern to allow checking for Enter key
    while ($listener.IsListening) {
        # Start async context retrieval
        $contextTask = $listener.GetContextAsync()
        
        # Poll for Enter key or completed request
        while (-not $contextTask.IsCompleted) {
            # Check if Enter key was pressed (non-blocking)
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Enter) {
                    Write-Host ""
                    Write-Host "Shutting down server..." -ForegroundColor Yellow
                    $listener.Stop()
                    Write-Host "Server stopped" -ForegroundColor Green
                    break
                }
            }
            Start-Sleep -Milliseconds 100
        }
        
        # If listener stopped, exit loop
        if (-not $listener.IsListening) {
            break
        }
        
        # Process the request if we have one
        if ($contextTask.IsCompleted -and -not $contextTask.IsFaulted) {
            $context = $contextTask.Result
            & $requestHandler $context $htmlFilePath $PSScriptRoot
        }
    }
    
    Write-Host ""
} catch {
    if ($_.Exception.Message -notlike "*stopped*" -and $_.Exception.Message -notlike "*closed*") {
        Write-Error "Server error: $($_.Exception.Message)"
    }
} finally {
    if ($null -ne $listener) {
        if ($listener.IsListening) {
            $listener.Stop()
        }
        $listener.Close()
    }
}
