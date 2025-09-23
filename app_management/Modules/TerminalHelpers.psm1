# Requires -Version 7.0
# TerminalHelpers.psm1 (relocated under Modules)

function Select-TerminalTabByTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    try { } catch { }
    return $false
}

function Select-WindowsTerminalTabByUIA {
    param([Parameter(Mandatory = $true)][string]$Title)
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
    } catch { Write-Host "UIA focus failed: $($_.Exception.Message)" }
    return $null
}

function Set-Win32SendTypes {
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
}

function Invoke-AppTabEnter {
    param([Parameter(Mandatory = $true)][string]$Title)
    try {
    Set-Win32SendTypes
        Start-Sleep -Milliseconds 300
    $wtProc = Select-WindowsTerminalTabByUIA -Title $Title
        if (-not $wtProc) {
            $wtProc = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        }
        if ($wtProc) {
            [Win32Send]::ShowWindow($wtProc.MainWindowHandle, [Win32Send]::SW_RESTORE) | Out-Null
            [Win32Send]::SetForegroundWindow($wtProc.MainWindowHandle) | Out-Null
            Start-Sleep -Milliseconds 200
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            Write-Host "Sent Enter via SendKeys to Windows Terminal for '$Title'."
            return
        }
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
    } catch { Write-Warning "Failed to send Enter to '$Title': $($_.Exception.Message)" }
}

function Stop-AppTabByTitle {
    param([Parameter(Mandatory=$true)][string]$Title,[switch]$DryRun)
    if ($DryRun) { Write-Host "[DryRun] Would close tab/window titled '$Title'"; return }
    $wtProc = Select-WindowsTerminalTabByUIA -Title $Title
    if ($wtProc) {
        try {
            Set-Win32SendTypes
            [Win32Send]::ShowWindow($wtProc.MainWindowHandle, [Win32Send]::SW_RESTORE) | Out-Null
            [Win32Send]::SetForegroundWindow($wtProc.MainWindowHandle) | Out-Null
            Start-Sleep -Milliseconds 150
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait("^+w")
            Write-Host "Sent Ctrl+Shift+W to close Windows Terminal tab '$Title'."
            Start-Sleep -Milliseconds 200
            return
        } catch { Write-Host "WT UIA close failed for '$Title': $($_.Exception.Message)" }
    }
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
    } catch { Write-Warning "Failed to close window '$Title': $($_.Exception.Message)" }
}

function Stop-PSWindowByTitle {
    param([Parameter(Mandatory = $true)][string]$Title)
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
                $isTargetApp = $false
                if ($windowTitle -eq $Title) { $isTargetApp = $true }
                if ($decodedCommand -and $decodedCommand -match "streamlit run.*$Title|flask run.*$Title|manage\.py runserver.*$Title|python.*$Title") { $isTargetApp = $true }
                if ($decodedCommand -and $decodedCommand -match "WindowTitle.*=.*'$Title'") { $isTargetApp = $true }
                if ($isTargetApp) {
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    Start-Sleep -Milliseconds 2000
                }
            } catch { continue }
        }
    } catch { Write-Warning "Failed to close window '$Title': $($_.Exception.Message)" }
}

function Get-WindowsTerminalPath {
    $wtPaths = @(
        "wt.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe",
        "C:\\Program Files\\WindowsApps\\Microsoft.WindowsTerminal_*\\wt.exe"
    )
    foreach ($path in $wtPaths) {
        if ($path -like "*\\*") {
            $found = Get-ChildItem $path -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return [pscustomobject]@{ Available=$true; Path=$found.FullName } }
        } else {
            $cmd = Get-Command $path -ErrorAction SilentlyContinue
            if ($cmd) { return [pscustomobject]@{ Available=$true; Path=$cmd.Source } }
        }
    }
    return [pscustomobject]@{ Available=$false; Path=$null }
}

function New-WindowsTerminalTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Title,
        [Parameter(Mandatory=$true)] [string]$StartingDirectory,
        [Parameter(Mandatory=$true)] [string]$EncodedCommand,
        [Parameter(Mandatory=$true)] [string]$PwshPath
    )

    $wtInfo = Get-WindowsTerminalPath
    if (-not $wtInfo.Available) { return $false }
    $wtPath = $wtInfo.Path

    $launched = $false
    try {
        $wtCommand = "wt -w 0 new-tab --title `"$Title`" --startingDirectory `"$StartingDirectory`" -- $PwshPath -NoLogo -EncodedCommand $EncodedCommand"
        cmd /c $wtCommand
        $launched = $true
    } catch {
        try {
            $wtArgs = @('-w','0','new-tab','--title',$Title,'--startingDirectory',$StartingDirectory,'--',$PwshPath,'-NoLogo','-EncodedCommand',$EncodedCommand)
            Start-Process -FilePath $wtPath -ArgumentList $wtArgs -ErrorAction Stop | Out-Null
            $launched = $true
        } catch {
            try {
                $wtProtocol = "wt://new-tab --title `"$Title`" --startingDirectory `"$StartingDirectory`" -- $PwshPath -NoLogo -EncodedCommand $EncodedCommand"
                Start-Process $wtProtocol | Out-Null
                $launched = $true
            } catch {
                $launched = $false
            }
        }
    }
    return $launched
}

Export-ModuleMember -Function @(
    'Select-TerminalTabByTitle',
    'Select-WindowsTerminalTabByUIA',
    'Set-Win32SendTypes',
    'Invoke-AppTabEnter',
    'Stop-AppTabByTitle',
    'Stop-PSWindowByTitle',
    'Get-WindowsTerminalPath',
    'New-WindowsTerminalTab'
)

