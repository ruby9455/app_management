<#!
.SYNOPSIS
Launch Streamlit, Django, and Dash apps from apps.json, each in a new Windows Terminal tab (or new PowerShell window), with the tab titled as the app name.

.DESCRIPTION
Reads apps from apps.json (same folder as this script). For every app with Type == "Streamlit", "Django", "Dash", or "Flask",
opens a new Windows Terminal tab titled with the app Name and runs either:
  - uv:  uv run streamlit run <IndexPath> --server.port <Port> [--server.baseUrlPath <BasePath>]
  - pip: [activate venv if VenvPath provided]; streamlit run <IndexPath> --server.port <Port> [--server.baseUrlPath <BasePath>]
For Type == "Django":
  - uv:  uv run <manage.py> runserver [0.0.0.0:<Port>]
  - pip: [activate venv if VenvPath provided]; py <manage.py> runserver [0.0.0.0:<Port>]
For Type == "Dash":
  - uv:  uv run python <IndexPath> --server.port <Port>
  - pip: [activate venv if VenvPath provided]; python <IndexPath> --server.port <Port>
  IndexPath is required.
For Type == "Flask":
  - uv:  set FLASK_APP=<IndexPath> and FLASK_ENV=development; uv run flask run --host=0.0.0.0 --port <Port>
  - pip: [activate venv if VenvPath provided]; set FLASK_APP and FLASK_ENV; flask run --host=0.0.0.0 --port <Port>
Detection order: explicit app.PackageManager, otherwise pyproject.toml → uv, else pip. If Windows Terminal is not found, a new PowerShell window is opened instead.

.PARAMETER AppName
Optional. If provided, only launch the app whose Name matches (case-insensitive).

.EXAMPLE
./run_streamlit_app_tab.ps1

.EXAMPLE
./run_streamlit_app_tab.ps1 -AppName "REDCap"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AppName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Utility: Return apps list with unique Names (case-insensitive), keeping first occurrence
function Deduplicate-AppsByName {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$Apps
    )
    return @($Apps | Group-Object { $_.Name.ToString().ToLowerInvariant() } | ForEach-Object { $_.Group | Select-Object -First 1 })
}

# Access helper: support both PSCustomObject and [hashtable]
function Get-FieldValue {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Object,
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Name)) { return $Object[$Name] } else { return $null }
    }
    if ($Object.PSObject -and $Object.PSObject.Properties.Match($Name).Count -gt 0) { return $Object.$Name }
    return $null
}

function Set-FieldValue {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Object,
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        $Value
    )
    if ($null -eq $Object) { return }
    if ($Object -is [hashtable]) {
        $Object[$Name] = $Value
        return
    }
    if ($Object.PSObject -and $Object.PSObject.Properties.Match($Name).Count -gt 0) {
        $Object.$Name = $Value
    } else {
        try { Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value -Force | Out-Null } catch { }
    }
}

function Has-NonEmptyField {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Object,
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    $value = Get-FieldValue -Object $Object -Name $Name
    return ($null -ne $value -and ([string]::IsNullOrWhiteSpace([string]$value) -eq $false))
}

# Resolve pwsh path
$pwshCmd = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue
if (-not $pwshCmd) {
    throw "'pwsh' was not found in PATH. Please ensure PowerShell 7+ is installed."
}
$pwshPath = $pwshCmd.Source

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

# Detect URL prefixes
$script:networkUrlPrefix = Get-NetworkUrlPrefix
$script:externalUrlPrefix = Get-ExternalUrlPrefix

Write-Host "Detected Network URL prefix: $script:networkUrlPrefix"
Write-Host "Detected External URL prefix: $script:externalUrlPrefix"

# Load apps.json
$jsonFilePath = "$PSScriptRoot\apps.json"
Write-Host "Reading apps from: $jsonFilePath"

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

if (-not (Test-Path $jsonFilePath)) {
    try {
        $examplePath = Join-Path $PSScriptRoot 'apps_example.json'
        if (Test-Path $examplePath) {
            Copy-Item -Path $examplePath -Destination $jsonFilePath -Force
            Write-Host "Created apps.json from template: $examplePath"
        } else {
            # Fallback to minimal empty list
            '[]' | Out-File -FilePath $jsonFilePath -Encoding UTF8 -Force
            Write-Host "Created empty apps.json at: $jsonFilePath"
        }
    } catch {
        throw "Failed to create apps.json at ${jsonFilePath}: $($_.Exception.Message)"
    }
}

$apps = Get-Content $jsonFilePath | ConvertFrom-Json
if ($apps -isnot [array]) { $apps = @($apps) }

# Filter to supported app types
$apps = $apps | Where-Object { $_.Type -and ( @('Streamlit','Django','Dash','Flask') -contains $_.Type ) }
$apps = Deduplicate-AppsByName -Apps @($apps)

if ($AppName) {
    $apps = $apps | Where-Object { $_.Name -ieq $AppName }
    if (-not $apps -or $apps.Count -eq 0) {
        throw "App '$AppName' not found or not a Streamlit app in apps.json."
    }
}

if (-not $apps -or $apps.Count -eq 0) {
    Write-Host "No Streamlit apps found in apps.json. Opening menu so you can add one."
}

# Helper: get listening PIDs for a given port using OwningProcess
function Get-ListeningPidsForPort {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )
    $conns = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if (-not $conns) { return @() }
    $pids = $conns | Select-Object -ExpandProperty OwningProcess -Unique
    return @($pids)
}

# Stop an app by killing the process(es) owning the listening port
function Stop-AppByConfig {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )
    $name = $App.Name
    if (-not (Has-NonEmptyField -Object $App -Name 'Port')) {
        Write-Warning "Cannot stop '$name': no Port configured."
        return
    }
    $port = [int](Get-FieldValue -Object $App -Name 'Port')
    $pids = Get-ListeningPidsForPort -Port $port
    if ($null -eq $pids) { $pids = @() }
    if (@($pids).Count -eq 0) {
        Write-Host "No listening process found on port $port for '$name'."
        return
    }
    foreach ($processId in @($pids)) {
        try {
            $procName = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName
            Write-Host "Stopping '$name' PID $processId ($procName) on port $port..."
            Stop-Process -Id $processId -Force -ErrorAction Stop
            Write-Host "Stopped PID $processId."
        } catch {
            Write-Warning "Failed to stop PID ${processId}: $($_.Exception.Message)"
        }
    }
}


# Close PowerShell window by title and command line (finds the tab running the app)
function Close-PSWindowByTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    try {
        Write-Host "Looking for existing tabs with title: $Title"
        
        # Find PowerShell processes
        $psProcesses = Get-Process -Name "pwsh" -ErrorAction SilentlyContinue
        Write-Host "Found $($psProcesses.Count) PowerShell processes"
        
        foreach ($proc in $psProcesses) {
            try {
                $windowTitle = $proc.MainWindowTitle
                $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                
                # Decode base64 command if it's encoded
                $decodedCommand = $commandLine
                if ($commandLine -and $commandLine -match "-EncodedCommand\s+(\S+)") {
                    try {
                        $encodedPart = $matches[1]
                        $decodedBytes = [Convert]::FromBase64String($encodedPart)
                        $decodedCommand = [System.Text.Encoding]::Unicode.GetString($decodedBytes)
                    } catch {
                        # If decoding fails, use original command
                    }
                }
                
                Write-Host "PID $($proc.Id): Title='$windowTitle'"
                Write-Host "  Decoded Cmd: $decodedCommand"
                
                # Check if this is the app we want to close
                $isTargetApp = $false
                
                # Method 1: Check window title
                if ($windowTitle -eq $Title) {
                    Write-Host "  -> Match by title"
                    $isTargetApp = $true
                }
                
                # Method 2: Check decoded command line for app-specific patterns
                if ($decodedCommand -and $decodedCommand -match "streamlit run.*$Title|flask run.*$Title|manage\.py runserver.*$Title|python.*$Title") {
                    Write-Host "  -> Match by decoded command line"
                    $isTargetApp = $true
                }
                
                # Method 3: Check for the specific app name in the decoded command
                if ($decodedCommand -and $decodedCommand -match "WindowTitle.*=.*'$Title'") {
                    Write-Host "  -> Match by WindowTitle setting"
                    $isTargetApp = $true
                }
                
                if ($isTargetApp) {
                    Write-Host "Closing existing tab: $Title (PID: $($proc.Id))"
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    Write-Host "Waiting for process to fully terminate..."
                    Start-Sleep -Milliseconds 2000  # Longer pause to ensure clean shutdown
                }
            } catch {
                Write-Host "  -> Cannot access PID $($proc.Id): $($_.Exception.Message)"
                continue
            }
        }
        
        # Verify no remaining processes with this title
        Write-Host "Verifying no remaining '$Title' processes..."
        Start-Sleep -Milliseconds 500
        $remainingProcesses = Get-Process -Name "pwsh" -ErrorAction SilentlyContinue | Where-Object {
            try {
                $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
                $decodedCommand = $commandLine
                if ($commandLine -and $commandLine -match "-EncodedCommand\s+(\S+)") {
                    try {
                        $encodedPart = $matches[1]
                        $decodedBytes = [Convert]::FromBase64String($encodedPart)
                        $decodedCommand = [System.Text.Encoding]::Unicode.GetString($decodedBytes)
                    } catch { }
                }
                $decodedCommand -and $decodedCommand -match "WindowTitle.*=.*'$Title'"
            } catch { $false }
        }
        
        if ($remainingProcesses) {
            Write-Host "Found $($remainingProcesses.Count) remaining '$Title' processes, closing them..."
            foreach ($proc in $remainingProcesses) {
                try {
                    Write-Host "Closing remaining process PID: $($proc.Id)"
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                } catch {
                    Write-Warning "Failed to close remaining process PID $($proc.Id): $($_.Exception.Message)"
                }
            }
        } else {
            Write-Host "No remaining '$Title' processes found."
        }
    } catch {
        Write-Warning "Failed to close window '$Title': $($_.Exception.Message)"
    }
}

# Focus a Windows Terminal tab by title (best effort)
function Focus-TerminalTabByTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    try {
        # Intentionally do nothing: direct CLI focusing can create new tabs on some WT versions
    } catch { }
    return $false
}

# Focus a Windows Terminal tab by title using UI Automation
function Focus-WindowsTerminalTabByUIA {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue | Out-Null
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue | Out-Null

        $wtProcs = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }
        foreach ($wt in $wtProcs) {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($wt.MainWindowHandle)
            if ($null -eq $root) { continue }

            $tabItemCond = New-Object System.Windows.Automation.AndCondition (
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)),
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Title))
            )

            $tabItem = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $tabItemCond)
            if ($tabItem) {
                $selectPattern = $tabItem.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                if ($selectPattern) { $selectPattern.Select() }
                return $wt
            }
        }
    } catch {
        Write-Host "UIA focus failed: $($_.Exception.Message)"
    }
    return $null
}

# Wait until a port is no longer listened on
function Wait-ForPortToBeFree {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [int]$TimeoutSeconds = 10
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $pids = Get-ListeningPidsForPort -Port $Port
        if (-not $pids -or @($pids).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

# Send Enter key to the Windows Terminal tab running the specified app title
function Send-EnterToAppTab {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    try {
        if (-not ("Win32Send" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Send {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const int SW_RESTORE = 9;
    public const uint WM_KEYDOWN = 0x0100;
    public const uint WM_KEYUP = 0x0101;
    public const int VK_RETURN = 0x0D;
}
"@
        }

        # Give WT a brief moment to show the restart prompt
        Start-Sleep -Milliseconds 300

        # Try to focus the correct tab via UI Automation
        $wtProc = Focus-WindowsTerminalTabByUIA -Title $Title
        if (-not $wtProc) {
            # Fallback: choose any WT window
            $wtProc = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        }
        if ($wtProc) {
            [Win32Send]::ShowWindow($wtProc.MainWindowHandle, [Win32Send]::SW_RESTORE) | Out-Null
            [Win32Send]::SetForegroundWindow($wtProc.MainWindowHandle) | Out-Null
            Start-Sleep -Milliseconds 200

            # Use SendKeys to ensure the Enter goes to the active control
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            Write-Host "Sent Enter via SendKeys to Windows Terminal for '$Title'."
            return
        }

        # Fallback: try previous pwsh-targeted approach if Windows Terminal handle not available
        $psProcesses = Get-Process -Name "pwsh" -ErrorAction SilentlyContinue
        foreach ($proc in $psProcesses) {
            try {
                $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                $decodedCommand = $commandLine
                if ($commandLine -and $commandLine -match "-EncodedCommand\s+(\S+)") {
                    try {
                        $encodedPart = $matches[1]
                        $decodedBytes = [Convert]::FromBase64String($encodedPart)
                        $decodedCommand = [System.Text.Encoding]::Unicode.GetString($decodedBytes)
                    } catch { }
                }
                if ($decodedCommand -and $decodedCommand -match "WindowTitle.*=.*'$Title'") {
                    [Win32Send]::ShowWindow($proc.MainWindowHandle, [Win32Send]::SW_RESTORE) | Out-Null
                    [Win32Send]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
                    Start-Sleep -Milliseconds 100
                    [Win32Send]::PostMessage($proc.MainWindowHandle, [Win32Send]::WM_KEYDOWN, [IntPtr][Win32Send]::VK_RETURN, [IntPtr]0) | Out-Null
                    [Win32Send]::PostMessage($proc.MainWindowHandle, [Win32Send]::WM_KEYUP, [IntPtr][Win32Send]::VK_RETURN, [IntPtr]0) | Out-Null
                    Write-Host "Sent Enter to '$Title' (PID $($proc.Id))."
                    return
                }
            } catch { continue }
        }
        Write-Warning "Could not find a target to send Enter for '$Title'."
    } catch {
        Write-Warning "Failed to send Enter to '$Title': $($_.Exception.Message)"
    }
}

# Ensure Win32Send type exists (focus/restore window)
function Ensure-TypeForWin32Send {
    if (-not ("Win32Send" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Send {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public const int SW_RESTORE = 9;
}
"@
    }
}

# Close a Windows Terminal tab (or pwsh window) by title
function Close-AppTabByTitle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,
        [switch]$DryRun
    )

    if ($DryRun) { Write-Host "[DryRun] Would close tab/window titled '$Title'"; return }

    # Try Windows Terminal UIA first: focus tab, then send Ctrl+Shift+W
    $wtProc = Focus-WindowsTerminalTabByUIA -Title $Title
    if ($wtProc) {
        try {
            Ensure-TypeForWin32Send
            [Win32Send]::ShowWindow($wtProc.MainWindowHandle, [Win32Send]::SW_RESTORE) | Out-Null
            [Win32Send]::SetForegroundWindow($wtProc.MainWindowHandle) | Out-Null
            Start-Sleep -Milliseconds 150
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait("^+w")
            Write-Host "Sent Ctrl+Shift+W to close Windows Terminal tab '$Title'."
            Start-Sleep -Milliseconds 200
            return
        } catch {
            Write-Host "WT UIA close failed for '$Title': $($_.Exception.Message)"
        }
    }

    # Fallback: kill matching pwsh process by title or encoded command signature
    try {
        $psProcesses = Get-Process -Name "pwsh" -ErrorAction SilentlyContinue
        foreach ($proc in $psProcesses) {
            try {
                $windowTitle = $proc.MainWindowTitle
                $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine

                $decodedCommand = $commandLine
                if ($commandLine -and $commandLine -match "-EncodedCommand\s+(\S+)") {
                    try {
                        $encodedPart = $matches[1]
                        $decodedBytes = [Convert]::FromBase64String($encodedPart)
                        $decodedCommand = [System.Text.Encoding]::Unicode.GetString($decodedBytes)
                    } catch { }
                }

                $isMatch = $false
                if ($windowTitle -eq $Title) { $isMatch = $true }
                elseif ($decodedCommand -and $decodedCommand -match "WindowTitle.*=.*'$([regex]::Escape($Title))'") { $isMatch = $true }

                if ($isMatch) {
                    Write-Host "Stopping pwsh process for '$Title' (PID $($proc.Id))..."
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                }
            } catch { continue }
        }
    } catch {
        Write-Warning "Failed to close window '$Title': $($_.Exception.Message)"
    }
}

# Close all idle app tabs (apps with Port set but no listener)
function Close-AllIdleAppTabs {
    param(
        [switch]$DryRun
    )

    $appsList = Get-CurrentAppsList
    if (-not $appsList -or $appsList.Count -eq 0) {
        Write-Host "No supported apps found in apps list. Nothing to close."
        return
    }

    $idleApps = @()
    foreach ($app in $appsList) {
        $name = Get-FieldValue -Object $app -Name 'Name'
        if (-not (Has-NonEmptyField -Object $app -Name 'Port')) { continue }
        $port = [int](Get-FieldValue -Object $app -Name 'Port')
        $pids = Get-ListeningPidsForPort -Port $port
        if (-not $pids -or @($pids).Count -eq 0) { $idleApps += $app }
    }

    if ($idleApps.Count -eq 0) {
        Write-Host "No idle app tabs detected."
        return
    }

    Write-Host "Closing $($idleApps.Count) idle app tab(s)..."
    foreach ($app in $idleApps) {
        $title = Get-FieldValue -Object $app -Name 'Name'
        $portStr = Get-FieldValue -Object $app -Name 'Port'
        Write-Host "-> $title (Port $portStr)"
        Close-AppTabByTitle -Title $title -DryRun:$DryRun
    }
}

# Function to detect package manager based on project files
function Get-PackageManager {
    param (
        [string]$ProjectDirectory
    )
    
    $pyprojectFile = Join-Path $ProjectDirectory "pyproject.toml"
    if (Test-Path $pyprojectFile) {
        return "uv"
    } else {
        return "pip"
    }
}

# ===== Helpers for CRUD on apps.json (ported from manage_apps_withbasepath_uv.ps1) =====

# Convert a PSObject to a hashtable
function ConvertTo-Hashtable {
    param (
        [Parameter(Mandatory=$true)]
        [object]$Object
    )

    if ($null -eq $Object) { return @{} }
    if ($Object -is [hashtable]) {
        # Return a shallow copy to avoid accidental mutation of the original reference
        $copy = @{}
        foreach ($k in $Object.Keys) { $copy[$k] = $Object[$k] }
        return $copy
    }

    $hashtable = @{}
    if ($Object.PSObject) {
        foreach ($property in $Object.PSObject.Properties) {
            $hashtable[$property.Name] = $property.Value
        }
    }
    return $hashtable
}

# Return apps list with unique Names (case-insensitive), keeping first occurrence
function Deduplicate-AppsByName {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$Apps
    )
    return @($Apps | Group-Object { $_.Name.ToString().ToLowerInvariant() } | ForEach-Object { $_.Group | Select-Object -First 1 })
}

# Test if directory looks like a venv (has Scripts/activate.bat)
function Test-Venv {
    param(
        [string]$Directory
    )
    $venvPath = Join-Path -Path $Directory -ChildPath "Scripts/activate.bat"
    if (-not (Test-Path $venvPath)) { $venvPath = Join-Path -Path $Directory -ChildPath "Scripts\Activate.ps1" }
    return (Test-Path $venvPath)
}

# Search for a venv under a project directory
function Search-Venv {
    param (
        [string]$ProjectDirectory
    )
    $venvDir = @(
        Get-ChildItem -Path $ProjectDirectory -Recurse -Directory -ErrorAction SilentlyContinue |
            Where-Object { (Test-Path (Join-Path $_.FullName 'Scripts\activate.bat')) -or (Test-Path (Join-Path $_.FullName 'Scripts\Activate.ps1')) }
    )
    if ($venvDir.Count -eq 1) { return $venvDir[0].Name }
    elseif ($venvDir.Count -gt 1) {
        for ($i = 0; $i -lt $venvDir.Count; $i++) { Write-Host ("{0}: {1}" -f ($i+1), $venvDir[$i].FullName) }
        $index = [int](Read-Host "Enter the index of the virtual environment to use") - 1
        return $venvDir[$index].Name
    } else { return $null }
}

# Read a venv directory from user, validate
function Get-VenvDirectory { 
    do {
        $venvPath = Read-Host "Enter the absoulte path for directory containing 'Scripts/activate.bat'"
        if (-not (Test-Venv -Directory $venvPath)) {
            Write-Host "The specified path '$venvPath' does not contain a valid venv."
        }
    } while (-not (Test-Venv -Directory $venvPath))
    return $venvPath
}

# Gather requirements content if any
function Get-RequirementsContent {
    param (
        [string]$ProjectDirectory
    )
    $requirementsFile = Get-ChildItem -Path $ProjectDirectory -Recurse -Filter "requirements.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($requirementsFile) { return Get-Content $requirementsFile.FullName } else { return "No requirements.txt found" }
}

# Detect basic app type by deps
function Get-AppType {
    param (
        [string]$ProjectDirectory
    )
    $packageManager = Get-PackageManager -ProjectDirectory $ProjectDirectory
    $packageNames = @()
    if ($packageManager -eq "uv") {
        # Try to parse pyproject.toml very lightly
        $pyprojectFile = Join-Path $ProjectDirectory "pyproject.toml"
        if (Test-Path $pyprojectFile) {
            $content = Get-Content $pyprojectFile -Raw
            if ($content -match 'streamlit') { return 'Streamlit' }
            if ($content -match 'django') { return 'Django' }
            if ($content -match 'flask') { return 'Flask' }
            if ($content -match 'dash') { return 'Dash' }
        }
    } else {
        $req = Get-RequirementsContent -ProjectDirectory $ProjectDirectory
        if ($req -ne "No requirements.txt found") {
            $text = ($req -join "`n")
            if ($text -match '(?i)streamlit') { return 'Streamlit' }
            if ($text -match '(?i)django') { return 'Django' }
            if ($text -match '(?i)flask') { return 'Flask' }
            if ($text -match '(?i)dash') { return 'Dash' }
        }
    }
    return 'Unknown Application Type'
}

# Choose a python entry file for streamlit/flask
function Get-AllUniquePyFile {
    param (
        [string]$ProjectDirectory
    )
    $venvDirectories = Get-ChildItem -Path $ProjectDirectory -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object {
        Test-Venv -Directory $_.FullName
    }
    $venvPaths = $venvDirectories | ForEach-Object { $_.FullName }
    $allPyFiles = @(Get-ChildItem -Path $ProjectDirectory -Recurse -Filter *.py -ErrorAction SilentlyContinue | Where-Object {
        $filePath = $_.FullName
        $isInVenv = $false
        foreach ($venvPath in $venvPaths) {
            if ($filePath -like "$venvPath*") { $isInVenv = $true; break }
        }
        -not $isInVenv
    } | Select-Object -ExpandProperty FullName -Unique)
    return $allPyFiles
}

function Get-IndexPyFile {
    param (
        [string]$ProjectDirectory
    )
    $allPyFiles = Get-AllUniquePyFile -ProjectDirectory $ProjectDirectory
    if ($allPyFiles -isnot [array]) { $allPyFiles = @($allPyFiles) }
    for ($i = 0; $i -lt $allPyFiles.Length; $i++) {
        $relativePath = $allPyFiles[$i] -replace [regex]::Escape($ProjectDirectory), '~'
        $relativePath = $relativePath -replace '\\', '/'
        Write-Host ("{0}: {1}" -f ($i+1), $relativePath)
    }
    $indexPage = [int](Read-Host "Enter the index of the index python file")
    $indexPage = $indexPage - 1
    $selectedPyFile = $allPyFiles[$indexPage]
    $selectedPyFile = $selectedPyFile.Substring($ProjectDirectory.Length + 1)
    return $selectedPyFile
}

# Prompt for port with random option
function Get-PortNumber {
    $portResponse = Read-Host "Would you like to assign a random port for this app? (y/n)"
    if ($portResponse -ieq "yes" -or $portResponse -ieq "y") {
        do {
            $port = Get-Random -Minimum 3000 -Maximum 9000
            $portCheck = Test-NetConnection -ComputerName "localhost" -Port $port
        } while ($portCheck.TcpTestSucceeded -eq $true)
        return $port
    } else {
        do {
            $port = Read-Host "Enter a specific port number (or 'help' to use a random port)"
            if ($port -eq "help") {
                Write-Host "Generating a random port number..."
                do {
                    $port = Get-Random -Minimum 3000 -Maximum 9000
                    $portCheck = Test-NetConnection -ComputerName "localhost" -Port $port
                } while ($portCheck.TcpTestSucceeded -eq $true)
            } else {
                $port = [int]$port
                $portCheck = Test-NetConnection -ComputerName "localhost" -Port $Port
                if ($portCheck.TcpTestSucceeded -eq $true) { Write-Host "Port $Port is already in use. Please enter a different port." }
            }
        } while ($portCheck.TcpTestSucceeded -eq $true)
        return $port
    }
}

# Save global apps back to JSON (with confirmation)
function Update-Json {
    $saveResponse = Read-Host ">>> Would you like to save the updated apps list to the JSON file? (y/n)"
    if ($saveResponse -ieq "yes" -or $saveResponse -ieq "y") {
        try {
            $global:apps | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFilePath -Encoding UTF8
            Write-Host "Apps list saved successfully to $jsonFilePath."
            # Refresh $apps from file so UI reflects latest saved changes
            $apps = Get-Content $jsonFilePath | ConvertFrom-Json
            if ($apps -isnot [array]) { $apps = @($apps) }
            $apps = $apps | Where-Object { $_.Type -and ( @('Streamlit','Django','Dash','Flask') -contains $_.Type ) }
            $apps = Deduplicate-AppsByName -Apps @($apps)
            # Keep in-memory editable list in sync as hashtables (deduped)
            $global:apps = @()
            foreach ($a in $apps) { $global:apps += (ConvertTo-Hashtable -Object $a) }
            $global:apps = Deduplicate-AppsByName -Apps $global:apps
        } catch {
            Write-Host "Failed to save file: $($_.Exception.Message)"
        }
    }
}

# Sync $apps (read-only list) and $global:apps (mutable list for CRUD)
$global:apps = @()
foreach ($a in $apps) { $global:apps += (ConvertTo-Hashtable -Object $a) }
$global:apps = Deduplicate-AppsByName -Apps $global:apps

# Update an app using 'git pull'
function Update-AppRepo {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )
    $name = $App.Name
    $appPath = $App.AppPath
    
    if (-not (Test-Path $appPath)) {
        Write-Warning "Path '$appPath' does not exist for app '$name'."
        return
    }

    Write-Host "Updating app '$name' via 'git pull'..."
    Push-Location $appPath
    try {
        git pull
        Write-Host "App '$name' updated successfully with 'git pull'."
    } catch {
        Write-Warning "Failed to update app '$name': $($_.Exception.Message)"
    } finally {
        Pop-Location
    }
}

# Update virtual environment for an app
function Update-Venv {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )
    
    $name = $App.Name
    $appPath = $App.AppPath
    $venvPath = $App.VenvPath
    $packageManager = if ($App.PSObject.Properties.Match('PackageManager').Count -gt 0 -and ([string]::IsNullOrWhiteSpace([string]$App.PackageManager) -eq $false)) { 
        [string]$App.PackageManager 
    } else { 
        Get-PackageManager -ProjectDirectory $appPath 
    }
    
    Write-Host "===== Update Virtual Environment for '$name' ====="
    
    if ($packageManager -ieq 'uv') {
        Write-Host "Using uv to update dependencies from pyproject.toml..."
        Push-Location $appPath
        try {
            uv sync
            Write-Host "Dependencies updated successfully with uv sync."
        } catch {
            Write-Warning "Failed to update dependencies with uv sync: $($_.Exception.Message)"
        } finally {
            Pop-Location
        }
    } else {
        # Check if $app.appRequirements is set
        $requirementsFile = $null
        if ($App.PSObject.Properties.Match('appRequirements').Count -gt 0 -and ([string]::IsNullOrWhiteSpace([string]$App.appRequirements) -eq $false)) {
            Write-Host "Using requirements file from app settings..."
            $requirementsFile = [string]$App.appRequirements
        } else {
            # Search for requirements.txt file in the project directory and its subdirectories
            $requirementsFile = Get-ChildItem -Path $appPath -Recurse -Filter "requirements.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
        }

        if ($null -eq $requirementsFile) {
            Write-Warning "requirements.txt not found in '$appPath' for app '$name'."
            return
        }

        $requirementsFilePath = if ($requirementsFile -is [string]) { $requirementsFile } else { $requirementsFile.FullName }
        
        # Determine target venv path
        $targetVenvPath = if ($App.PSObject.Properties.Match('VenvPath').Count -gt 0 -and ([string]::IsNullOrWhiteSpace([string]$App.VenvPath) -eq $false)) {
            [string]$App.VenvPath
        } else {
            Join-Path $appPath '.venv'
        }

        $activateScript = Join-Path $targetVenvPath 'Scripts/Activate.ps1'
        if (-not (Test-Path $activateScript)) { 
            $activateScript = Join-Path $targetVenvPath 'Scripts\Activate.ps1' 
        }

        if (Test-Path $activateScript) {
            Write-Host "Activating virtual environment and installing dependencies from '$requirementsFilePath'..."
            Push-Location $appPath
            try {
                & $activateScript
                pip install -r $requirementsFilePath
                Write-Host "Virtual environment updated successfully."
            } catch {
                Write-Warning "Failed to update virtual environment: $($_.Exception.Message)"
            } finally {
                Pop-Location
            }
        } else {
            Write-Warning "Virtual environment not found at '$targetVenvPath' for app '$name'."
        }
    }
}

# Update an app (repo + venv + restart)
function Update-App {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )
    
    $name = $App.Name
    Write-Host "===== Update App '$name' ====="
    
    # Stop the app first
    Stop-AppByConfig -App $App
    # If the app has a port, wait briefly for it to free up
    if (Has-NonEmptyField -Object $App -Name 'Port') {
        $null = Wait-ForPortToBeFree -Port ([int](Get-FieldValue -Object $App -Name 'Port')) -TimeoutSeconds 10
    }

    # Update repo
    Update-AppRepo -App $App
    
    # Update virtual environment
    Update-Venv -App $App
    
    # Ensure the port is still free after updates (just in case background tasks spawned)
    if (Has-NonEmptyField -Object $App -Name 'Port') {
        $null = Wait-ForPortToBeFree -Port ([int](Get-FieldValue -Object $App -Name 'Port')) -TimeoutSeconds 10
    }

    # Give Windows Terminal time to display the "Press ENTER to continue" prompt
    Start-Sleep -Milliseconds 300

    # Bring the existing tab to the foreground and send Enter to trigger restart in-place
    Write-Host "Triggering restart in existing tab for '$name'..."
    Send-EnterToAppTab -Title $name
    # Best-effort: a second Enter shortly after, in case the first hit a transient state
    Start-Sleep -Milliseconds 200
    Send-EnterToAppTab -Title $name
}

# Get the current apps list (prefer in-memory edits if available)
function Get-CurrentAppsList {
    $inMem = @($global:apps)
    if ($inMem.Count -gt 0) { return (Deduplicate-AppsByName -Apps $inMem | Sort-Object Name) }
    return (Deduplicate-AppsByName -Apps @($apps) | Sort-Object Name)
}

# Show apps and helper to select by name or index (uses current list)
function Show-AppsTab {
    Write-Host "===== All available apps ====="
    $sorted = Get-CurrentAppsList
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $name = Get-FieldValue -Object $sorted[$i] -Name 'Name'
        Write-Host ("{0}: {1}" -f ($i+1), $name)
    }
    return $sorted
}

# Generate URL display pattern for an app
function Get-AppUrlsTab {
    param(
        [object]$app
    )
    
    $port = Get-FieldValue -Object $app -Name 'Port'
    if (-not $port) {
        return "No port configured"
    }
    
    $basePath = Get-FieldValue -Object $app -Name 'BasePath'
    $basePathStr = if ($basePath -and ([string]::IsNullOrWhiteSpace([string]$basePath) -eq $false)) { "/$basePath" } else { "" }
    
    $urls = @()
    $urls += "  Local URL: http://localhost:$port$basePathStr"
    $urls += "  Network URL: $script:networkUrlPrefix`:$port$basePathStr"
    $urls += "  External URL: $script:externalUrlPrefix`:$port$basePathStr"
    
    return $urls -join "`n"
}

# Show all apps with their URLs
function Show-AppsWithUrlsTab {
    Write-Host "===== All available apps with URLs ====="
    $sorted = Get-CurrentAppsList
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $app = $sorted[$i]
        $name = Get-FieldValue -Object $app -Name 'Name'
        $type = Get-FieldValue -Object $app -Name 'Type'
        Write-Host "`n$($i+1): $name ($type)"
        Write-Host (Get-AppUrlsTab -app $app)
    }
    return $sorted
}

# Generate HTML dashboard
function Generate-HtmlDashboard {
    Write-Host "===== Generating HTML Dashboard ====="
    
    # Get current apps list
    $currentApps = Get-CurrentAppsList
    
    # Filter to apps with ports
    $appsWithPorts = $currentApps | Where-Object { 
        $port = Get-FieldValue -Object $_ -Name 'Port'
        $port -and $port -gt 0 
    }
    
    if (-not $appsWithPorts -or (@($appsWithPorts).Count -eq 0)) {
        Write-Host "No apps with ports found. Cannot generate dashboard."
        return
    }
    
    # Detect URL prefixes
    $networkUrlPrefix = Get-NetworkUrlPrefix
    $externalUrlPrefix = Get-ExternalUrlPrefix
    
    Write-Host "Detected Network URL prefix: $networkUrlPrefix"
    Write-Host "Detected External URL prefix: $externalUrlPrefix"
    
    # Generate HTML content
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

    foreach ($app in $appsWithPorts) {
        $port = Get-FieldValue -Object $app -Name 'Port'
        $basePath = Get-FieldValue -Object $app -Name 'BasePath'
        $basePathStr = if ($basePath -and ([string]::IsNullOrWhiteSpace([string]$basePath) -eq $false)) { "/$basePath" } else { "" }
        $appName = Get-FieldValue -Object $app -Name 'Name'
        $appType = Get-FieldValue -Object $app -Name 'Type'
        
        $html += @"
            <div class="app-card">
                <div class="app-name">$appName</div>
                <div class="app-type">$appType</div>
                
                <div class="url-section">
                    <div class="url-label">🏠 Local URL</div>
                    <a href="http://localhost:$port$basePathStr" target="_blank" class="url-link">
                        http://localhost:$port$basePathStr
                    </a>
                </div>
                
                <div class="url-section">
                    <div class="url-label">🌐 Network URL</div>
                    <a href="$networkUrlPrefix`:$port$basePathStr" target="_blank" class="url-link">
                        $networkUrlPrefix`:$port$basePathStr
                    </a>
                </div>
                
                <div class="url-section">
                    <div class="url-label">🌍 External URL</div>
                    <a href="$externalUrlPrefix`:$port$basePathStr" target="_blank" class="url-link">
                        $externalUrlPrefix`:$port$basePathStr
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

    # Save HTML file
    $htmlFilePath = "$PSScriptRoot\app_index.html"
    $html | Out-File -FilePath $htmlFilePath -Encoding UTF8
    
    Write-Host "HTML dashboard saved to: $htmlFilePath"
    Write-Host "You can open this file in your browser or serve it with any web server."
    Write-Host "To serve it with Python: python -m http.server 1234"
    Write-Host "To serve it with PowerShell: .\generate_app_index.ps1"
    
    return $htmlFilePath
}

function Get-AppByNameOrIndexTab {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputValue,
        [Parameter(Mandatory = $true)]
        [array]$AppList
    )
    if ($InputValue -match '^\d+$') {
        $idx = [int]$InputValue - 1
        if ($idx -ge 0 -and $idx -lt $AppList.Count) { return $AppList[$idx] }
        Write-Host "Invalid index. Please enter a number between 1 and $($AppList.Count)."
        return $null
    } else {
        $app = $AppList | Where-Object { (Get-FieldValue -Object $_ -Name 'Name') -ieq $InputValue }
        if ($null -eq $app) { Write-Host "App '$InputValue' not found."; return $null }
        return $app
    }
}

# Start the provided app list (opens each in Windows Terminal tab or new pwsh window)
function Start-AppsList {
    param(
        [Parameter(Mandatory = $true)]
        [array]$AppList
    )
    # Check if Windows Terminal is available
    $wtAvailable = $false
    $wtPath = $null
    
    # Try to find Windows Terminal in common locations
    $wtPaths = @(
        "wt.exe",  # In PATH
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe",  # WindowsApps shortcut
        "C:\Program Files\WindowsApps\Microsoft.WindowsTerminal_*\wt.exe"  # Direct executable
    )
    
    foreach ($path in $wtPaths) {
        if ($path -like "*\*") {
            # This is a file path, check if it exists
            $found = Get-ChildItem $path -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $wtPath = $found.FullName
                $wtAvailable = $true
                break
            }
        } else {
            # This is a command name, try to get it
            $cmd = Get-Command $path -ErrorAction SilentlyContinue
            if ($cmd) {
                $wtPath = $cmd.Source
                $wtAvailable = $true
                break
            }
        }
    }

    foreach ($app in $AppList) {
        $name = Get-FieldValue -Object $app -Name 'Name'
        $appPath = Get-FieldValue -Object $app -Name 'AppPath'
        $type = Get-FieldValue -Object $app -Name 'Type'
        $indexRel = Get-FieldValue -Object $app -Name 'IndexPath'

        if (-not $name) { Write-Warning "Skipping app with missing Name."; continue }
        if (-not $appPath) { Write-Warning "Skipping '$name': missing AppPath."; continue }
        if ($type -ieq 'Streamlit' -or $type -ieq 'Flask' -or $type -ieq 'Dash') {
            if (-not $indexRel) { Write-Warning "Skipping '$name': missing IndexPath."; continue }
        }

        if (-not (Test-Path -Path $appPath)) { Write-Warning "Skipping '$name': AppPath '$appPath' not found."; continue }
        if ($type -ieq 'Streamlit' -or $type -ieq 'Flask' -or $type -ieq 'Dash') {
            $indexFull = if ([System.IO.Path]::IsPathRooted($indexRel)) { $indexRel } else { Join-Path $appPath $indexRel }
            if (-not (Test-Path -Path $indexFull)) { Write-Warning "Skipping '$name': IndexPath '$indexFull' not found."; continue }
        }

        $workingDir = (Resolve-Path -Path $appPath).Path

        # Build a PowerShell command and pass via -EncodedCommand to avoid quoting issues
        $escapedDir = $workingDir -replace "'", "''"
        $escapedName = $name -replace "'", "''"
        $escapedIndex = $indexRel -replace "'", "''"
        $portArg = ""
        if ($type -ieq 'Streamlit') {
            if (Has-NonEmptyField -Object $app -Name 'Port') {
                $portArg = " --server.port $([string](Get-FieldValue -Object $app -Name 'Port'))"
            } else {
                Write-Warning "Skipping '$name': missing Port for Streamlit app."
                continue
            }
        }
        $basePathArg = ""
        if ($type -ieq 'Streamlit') {
            $bp = Get-FieldValue -Object $app -Name 'BasePath'
            if ($null -ne $bp -and ([string]::IsNullOrWhiteSpace([string]$bp) -eq $false)) {
                $escapedBasePath = ($bp -replace "'", "''")
                $basePathArg = " --server.baseUrlPath '$escapedBasePath'"
            }
        }
        $dashPortArg = ""
        if ($type -ieq 'Dash') {
            $dashPort = Get-FieldValue -Object $app -Name 'Port'
            if ($null -ne $dashPort -and ([string]::IsNullOrWhiteSpace([string]$dashPort) -eq $false)) {
                $dashPortArg = " --server.port $dashPort"
            }
        }
        $flaskHostPortArg = ""
        if ($type -ieq 'Flask') {
            $flaskPort = Get-FieldValue -Object $app -Name 'Port'
            if ($null -ne $flaskPort -and ([string]::IsNullOrWhiteSpace([string]$flaskPort) -eq $false)) {
                $flaskHostPortArg = " --host=0.0.0.0 --port $flaskPort"
            }
        }
        
        # Determine package manager: explicit override or detect by pyproject.toml
        $packageManager = $null
        if (Has-NonEmptyField -Object $app -Name 'PackageManager') {
            $packageManager = [string](Get-FieldValue -Object $app -Name 'PackageManager')
        } else {
            $pyproject = Join-Path $workingDir 'pyproject.toml'
            $packageManager = if (Test-Path $pyproject) { 'uv' } else { 'pip' }
        }

        $venvActivatePrefix = ""
        $bootstrapPrefix = ""
        if ($packageManager -ieq 'pip') {
            # Determine target venv path (explicit VenvPath or default to .venv in the project)
            $targetVenvPath = $null
            if (Has-NonEmptyField -Object $app -Name 'VenvPath') {
                $targetVenvPath = [string](Get-FieldValue -Object $app -Name 'VenvPath')
            } else {
                $targetVenvPath = Join-Path $workingDir '.venv'
            }

            $activateScript = Join-Path $targetVenvPath 'Scripts/Activate.ps1'
            if (-not (Test-Path $activateScript)) { $activateScript = Join-Path $targetVenvPath 'Scripts\Activate.ps1' }

            if (-not (Test-Path $activateScript)) {
                # No venv detected. Bootstrap a .venv under the project and install requirements if found.
                $requirements = Get-ChildItem -Path $workingDir -Recurse -Filter 'requirements.txt' -File -ErrorAction SilentlyContinue | Select-Object -First 1
                $reqFull = if ($requirements) { $requirements.FullName } else { $null }
                $escapedReq = if ($reqFull) { $reqFull -replace "'", "''" } else { $null }

                $bootstrapPrefix = "py -m venv .venv; & '.\\.venv\Scripts\Activate.ps1'; "
                if ($escapedReq) {
                    $bootstrapPrefix += "python -m pip install -r '$escapedReq'; "
                }

                # After bootstrap, activate that new .venv for the run command
                $activateScript = Join-Path $workingDir '.venv\Scripts\Activate.ps1'
            }

            if (Test-Path $activateScript) {
                $escapedActivate = ($activateScript -replace "'", "''")
                $venvActivatePrefix = "& '$escapedActivate'; "
            }
        }

        if ($type -ieq 'Streamlit') {
            if ($packageManager -ieq 'uv') {
                $runCmd = "uv run streamlit run '$escapedIndex'$portArg$basePathArg"
            } else {
                $runCmd = "${bootstrapPrefix}${venvActivatePrefix}streamlit run '$escapedIndex'$portArg$basePathArg"
            }
        } elseif ($type -ieq 'Django') {
            # Locate manage.py under the project directory
            $manageFile = Get-ChildItem -Path $workingDir -Recurse -Filter 'manage.py' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $manageFile) { Write-Warning "Skipping '$name': manage.py not found under '$workingDir'."; continue }
            try {
                $manageRel = [System.IO.Path]::GetRelativePath($workingDir, $manageFile.FullName)
            } catch {
                $manageRel = 'manage.py'
            }
            $escapedManage = $manageRel -replace "'", "''"
            $runserverPortArg = ""
            $djPort = Get-FieldValue -Object $app -Name 'Port'
            if ($null -ne $djPort -and ([string]::IsNullOrWhiteSpace([string]$djPort) -eq $false)) {
                $runserverPortArg = " $djPort"
            }
            if ($packageManager -ieq 'uv') {
                $runCmd = "uv run '$escapedManage' runserver$runserverPortArg"
            } else {
                $runCmd = "${bootstrapPrefix}${venvActivatePrefix}py '$escapedManage' runserver$runserverPortArg"
            }
        } elseif ($type -ieq 'Dash') {
            if ($packageManager -ieq 'uv') {
                $runCmd = "uv run python '$escapedIndex'$dashPortArg"
            } else {
                $runCmd = "${bootstrapPrefix}${venvActivatePrefix}python '$escapedIndex'$dashPortArg"
            }
        } elseif ($type -ieq 'Flask') {
            # Build environment assignment as a single literal string to avoid parsing issues
            $flaskEnvPrefix = "`$env:FLASK_APP = '$escapedIndex'; `$env:FLASK_ENV = 'development'; "
            if ($packageManager -ieq 'uv') {
                $runCmd = "$flaskEnvPrefix" + "uv run flask run$flaskHostPortArg"
            } else {
                $runCmd = "${bootstrapPrefix}${venvActivatePrefix}$flaskEnvPrefix" + "flask run$flaskHostPortArg"
            }
        } else {
            Write-Warning "Skipping '$name': Unsupported Type '$type'."; continue
        }

        $commandText = "Set-Location -LiteralPath '$escapedDir'; `$host.UI.RawUI.WindowTitle = '$escapedName'; $runCmd; exit `$LASTEXITCODE"
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($commandText))

        if ($wtAvailable) {
            # Try multiple methods to launch Windows Terminal
            $launched = $false
            
            # Method 1: Try using the wt command through cmd
            try {
                $wtCommand = "wt -w 0 new-tab --title `"$name`" --startingDirectory `"$workingDir`" -- $pwshPath -NoLogo -EncodedCommand $encoded"
                cmd /c $wtCommand
                Write-Host "Launched '$name' in Windows Terminal tab (via cmd)"
                $launched = $true
            } catch {
                # Method 2: Try using Start-Process with the direct path
                try {
                    $wtArgs = @('-w', '0', 'new-tab', '--title', $name, '--startingDirectory', $workingDir, '--', $pwshPath, '-NoLogo', '-EncodedCommand', $encoded)
                    Start-Process -FilePath $wtPath -ArgumentList $wtArgs -ErrorAction Stop | Out-Null
                    Write-Host "Launched '$name' in Windows Terminal tab (via Start-Process)"
                    $launched = $true
                } catch {
                    # Method 3: Try using the Windows Terminal protocol
                    try {
                        $wtProtocol = "wt://new-tab --title `"$name`" --startingDirectory `"$workingDir`" -- $pwshPath -NoLogo -EncodedCommand $encoded"
                        Start-Process $wtProtocol
                        Write-Host "Launched '$name' in Windows Terminal tab (via protocol)"
                        $launched = $true
                    } catch {
                        Write-Warning "All Windows Terminal launch methods failed: $($_.Exception.Message)"
                    }
                }
            }
            
            if (-not $launched) {
                Write-Warning "Failed to launch Windows Terminal, falling back to PowerShell window"
                Start-Process -FilePath $pwshPath -ArgumentList @('-NoLogo','-EncodedCommand', $encoded) -WorkingDirectory $workingDir | Out-Null
            }
        } else {
            Write-Host "Windows Terminal not found, launching '$name' in new PowerShell window"
            Start-Process -FilePath $pwshPath -ArgumentList @('-NoLogo','-EncodedCommand', $encoded) -WorkingDirectory $workingDir | Out-Null
        }
    }
}

# Interactive menu if no parameters supplied
$invokedWithParams = $PSBoundParameters.ContainsKey('AppName')
if (-not $invokedWithParams) {
    while ($true) {
        Write-Output "=============================="
        Write-Output "Select an option:"
        Write-Output "1. Start all apps"
        Write-Output "2. Restart an app"
        Write-Output "3. Start an app"
        Write-Output "4. Stop an app"
        Write-Output "5. Update an app from repo"
        Write-Output "6. Add a new app to apps.json"
        Write-Output "7. Update an app in apps.json"
        Write-Output "8. Remove an app from apps.json"
        Write-Output "9. Save the apps list to apps.json"
        Write-Output "10. Generate/Update HTML Dashboard"
        Write-Output "0. Close all idle app tabs"
        Write-Output "=============================="
        $option = Read-Host "Enter option"

        switch ($option) {
            1 {
                $listAll = Get-CurrentAppsList
                Start-AppsList -AppList $listAll
            }
            2 {
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to restart (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -ne $appSel) {
                    # Stop the app's running process and wait for the port to be free
                    Stop-AppByConfig -App $appSel
                    if (Has-NonEmptyField -Object $appSel -Name 'Port') {
                        $null = Wait-ForPortToBeFree -Port ([int](Get-FieldValue -Object $appSel -Name 'Port')) -TimeoutSeconds 10
                    }
                    Start-Sleep -Milliseconds 300
                    # Trigger restart in the same tab by sending Enter
                    $targetName = Get-FieldValue -Object $appSel -Name 'Name'
                    Send-EnterToAppTab -Title $targetName
                }
            }
            3 {
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to start (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -ne $appSel) {
                    Start-AppsList -AppList @($appSel)
                }
            }
            4 {
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to stop (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -ne $appSel) {
                    Stop-AppByConfig -App $appSel
                }
            }
            5 {
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to update (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -ne $appSel) {
                    Update-App -App $appSel
                }
            }
            6 {
                # Add app
                Write-Host "===== Add App Setting ====="
                $appPath = Read-Host ">>> Enter app path (or 'back' to cancel)"
                if ($appPath -ieq 'back') { continue }
                $defaultName = Split-Path -Path $appPath -Leaf
                $appName = Read-Host "Default app name: $defaultName (press Enter to keep or enter new)"
                if (-not $appName) { $appName = $defaultName }
                # Guard: prevent duplicate names (case-insensitive)
                $exists = ($global:apps | Where-Object { (Get-FieldValue -Object $_ -Name 'Name') -ieq $appName })
                if ($exists) {
                    Write-Host "An app named '$appName' already exists. Please choose a different name."
                    break
                }

                $appType = Get-AppType -ProjectDirectory $appPath
                if (-not $appType -or $appType -eq 'Unknown Application Type') {
                    $appType = Read-Host ">>> Enter app type, Streamlit/Django/Flask/Dash (s/d/f/da)"
                }
                $packageManager = Get-PackageManager -ProjectDirectory $appPath
                Write-Host "Detected package manager: $packageManager"

                $venvDirectory = Search-Venv -ProjectDirectory $appPath
                if ($venvDirectory) {
                    $venvPath = Join-Path -Path $appPath -ChildPath $venvDirectory
                } else {
                    $pyprojectFile = Join-Path $appPath "pyproject.toml"
                    if (Test-Path $pyprojectFile) {
                        Write-Host "No venv detected. Found pyproject.toml; running 'uv sync'..."
                        Push-Location $appPath; uv sync; Pop-Location
                        $venvDirectory = Search-Venv -ProjectDirectory $appPath
                        if ($venvDirectory) { $venvPath = Join-Path -Path $appPath -ChildPath $venvDirectory } else { $venvPath = "" }
                    } else {
                        $venvPath = Get-VenvDirectory
                    }
                }

                $indexPath = $null
                if ($appType -ieq "streamlit" -or $appType -ieq "flask" -or $appType -ieq "dash") {
                    $indexPath = Get-IndexPyFile -ProjectDirectory $appPath
                }

                $newApp = [hashtable]@{
                    Name = $appName
                    Type = $appType
                    PackageManager = $packageManager
                    VenvPath = $venvPath
                    AppPath = $appPath
                    IndexPath = $indexPath
                    Port = Get-PortNumber
                }

                if (-not $global:apps) { $global:apps = @(@($newApp)) } else { $global:apps += $newApp }
                Write-Output "App '$appName' added successfully."
                Update-Json
            }
            7 {
                # Update app settings
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to update settings (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -eq $appSel) { continue }

                $app = ConvertTo-Hashtable -Object $appSel
                $nameForIndex = Get-FieldValue -Object $appSel -Name 'Name'
                $updated = $false

                $currName = Get-FieldValue -Object $app -Name 'Name'
                Write-Host "Current app name: $currName"
                $newAppName = Read-Host ">>> Enter app name (press Enter to keep)"
                if ($newAppName -and $newAppName -cne $currName) { Set-FieldValue -Object $app -Name 'Name' -Value $newAppName; $updated = $true }

                $appPathVal = Get-FieldValue -Object $app -Name 'AppPath'
                $detectedType = Get-AppType -ProjectDirectory $appPathVal
                $currType = Get-FieldValue -Object $app -Name 'Type'
                Write-Host "Current type: $currType | Detected: $detectedType"
                if ($detectedType -and $detectedType -ne 'Unknown Application Type' -and $detectedType -ne $currType) {
                    $ans = Read-Host ">>> Update type to '$detectedType'? (y/n)"
                    if ($ans -match '^(?i:y|yes)$') { Set-FieldValue -Object $app -Name 'Type' -Value $detectedType; $updated = $true }
                }
                $manualType = Read-Host ">>> Or manually enter type Streamlit/Django/Flask/Dash (press Enter to keep)"
                if ($manualType) { Set-FieldValue -Object $app -Name 'Type' -Value $manualType; $updated = $true }

                $detectedPM = Get-PackageManager -ProjectDirectory $appPathVal
                $currPM = Get-FieldValue -Object $app -Name 'PackageManager'
                $currentPM = if ($currPM) { $currPM } else { 'Not set' }
                Write-Host "Current package manager: $currentPM | Detected: $detectedPM"
                if (-not $currPM) { Set-FieldValue -Object $app -Name 'PackageManager' -Value $detectedPM; $updated = $true }
                elseif ($detectedPM -ne $currPM) {
                    $ans = Read-Host ">>> Update package manager to '$detectedPM'? (y/n)"
                    if ($ans -match '^(?i:y|yes)$') { Set-FieldValue -Object $app -Name 'PackageManager' -Value $detectedPM; $updated = $true }
                }

                $currAppPath = Get-FieldValue -Object $app -Name 'AppPath'
                Write-Host "Current app path: $currAppPath"
                $newPath = Read-Host ">>> Enter app path (press Enter to keep)"
                if ($newPath) { Set-FieldValue -Object $app -Name 'AppPath' -Value $newPath; $updated = $true }

                $typeVal = Get-FieldValue -Object $app -Name 'Type'
                if ($typeVal -ieq 'streamlit' -or $typeVal -ieq 'flask' -or $typeVal -ieq 'dash') {
                    $currIndex = Get-FieldValue -Object $app -Name 'IndexPath'
                    Write-Host "Current index path: $currIndex"
                    $newIndex = Read-Host ">>> Enter index path (press Enter to keep)"
                    if ($newIndex) { Set-FieldValue -Object $app -Name 'IndexPath' -Value $newIndex; $updated = $true }
                } elseif ($typeVal -ieq 'django') {
                    $hasIndex = Get-FieldValue -Object $app -Name 'IndexPath'
                    if ($hasIndex) {
                        if ($app -is [hashtable]) { $null = $app.Remove('IndexPath') } else { $app.PSObject.Properties.Remove('IndexPath') }
                        $updated = $true
                    }
                }

                $currVenv = Get-FieldValue -Object $app -Name 'VenvPath'
                Write-Host "Current venv path: $currVenv"
                $chgVenv = Read-Host ">>> Update venv path? (y/n)"
                if ($chgVenv -match '^(?i:y|yes)$') {
                    $newVenv = Get-VenvDirectory
                    if ($newVenv) { Set-FieldValue -Object $app -Name 'VenvPath' -Value $newVenv; $updated = $true }
                }

                $currPort = Get-FieldValue -Object $app -Name 'Port'
                Write-Host "Current port: $currPort"
                $chgPort = Read-Host ">>> Update port? (y/n)"
                if ($chgPort -match '^(?i:y|yes)$') {
                    $newPort = Get-PortNumber
                    if ($newPort) { Set-FieldValue -Object $app -Name 'Port' -Value $newPort; $updated = $true }
                }

                if ($updated) {
                    # Update the correct entry by original object identity when possible, fallback to name match
                    $replaced = $false
                    for ($i = 0; $i -lt $global:apps.Count; $i++) {
                        if ((Get-FieldValue -Object $global:apps[$i] -Name 'Name') -ieq $nameForIndex) { $global:apps[$i] = $app; $replaced = $true; break }
                    }
                    if (-not $replaced) {
                        # If not found by name (renamed), replace by new name or append
                        for ($i = 0; $i -lt $global:apps.Count; $i++) {
                            $currAppName = Get-FieldValue -Object $app -Name 'Name'
                            if ((Get-FieldValue -Object $global:apps[$i] -Name 'Name') -ieq $currAppName) { $global:apps[$i] = $app; $replaced = $true; break }
                        }
                        if (-not $replaced) { $global:apps += $app }
                    }
                    Write-Host "App '$nameForIndex' updated successfully."
                    Update-Json
                } else { Write-Host "No changes made." }
            }
            8 {
                # Remove app
                $list = Show-AppsTab
                Write-Host "===================="
                $sel = Read-Host "Enter app name or index to remove (or 'back' to cancel)"
                if ($sel -ieq 'back') { continue }
                $appSel = Get-AppByNameOrIndexTab -InputValue $sel -AppList $list
                if ($null -eq $appSel) { continue }
                $name = Get-FieldValue -Object $appSel -Name 'Name'
                $global:apps = $global:apps | Where-Object { (Get-FieldValue -Object $_ -Name 'Name') -ine $name }
                Write-Host "App '$name' removed successfully."
                Update-Json
            }
            9 {
                Update-Json
            }
            10 {
                Generate-HtmlDashboard
            }
            0 {
                Close-AllIdleAppTabs
            }
            Default { Write-Output "Invalid option. Try again." }
        }
    }
    return
}

# Start apps (for non-menu usage with -AppName parameter)
Start-AppsList -AppList $apps

