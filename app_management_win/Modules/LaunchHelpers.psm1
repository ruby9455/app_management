Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Caches to avoid repeated filesystem checks when launching many apps
$script:PyProjectCache = @{}
$script:VenvActivateCache = @{}
$script:ManagePyCache = @{}

# Ensure field access helpers are available
try {
    if (-not (Get-Command -Name Get-FieldValue -ErrorAction SilentlyContinue)) {
        Import-Module -Force (Join-Path $PSScriptRoot 'AppHelpers.psm1') -ErrorAction Stop
    }
} catch {
    function Get-FieldValue {
        param(
            [Parameter(Mandatory=$true)][object]$Object,
            [Parameter(Mandatory=$true)][string]$Name
        )
        if ($null -eq $Object) { return $null }
        if ($Object -is [hashtable]) { if ($Object.ContainsKey($Name)) { return $Object[$Name] } else { return $null } }
        if ($Object.PSObject -and $Object.PSObject.Properties.Match($Name).Count -gt 0) { return $Object.$Name }
        return $null
    }
}

function ConvertTo-SingleQuotedLiteral {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return $null }
    return ($Text -replace "'", "''")
}

function Get-AppsFromInput {
    <#
    .SYNOPSIS
    Parses comma-separated app input and returns matching app objects from a list.
    
    .DESCRIPTION
    Handles comma-separated selection (flexible separators: ',', ', ', ' , ').
    Special inputs: '0' or 'all' returns all apps.
    Supports app indices (1-N), app names, or port numbers.
    
    .PARAMETER InputValue
    The user input string (comma-separated indices/names/ports, or '0'/'all').
    
    .PARAMETER AppList
    Array of app objects to select from.
    
    .OUTPUTS
    Array of matching app objects.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$InputValue,
        [Parameter(Mandatory=$true)][array]$AppList
    )
    
    $resultApps = @()
    
    # Check if input is "all" or "0"
    if ($InputValue -eq "0" -or $InputValue -ieq "all") {
        return $AppList
    }
    
    # Split by comma and handle various separator formats: ',', ', ', ' , '
    $items = $InputValue -split '\s*,\s*' | Where-Object { $_ -ne "" }
    
    foreach ($item in $items) {
        $item = $item.Trim()
        if ($item -ne "") {
            $app = $null
            
            # Try to match by index or port number
            if ($item -match '^\d+$') {
                $idx = [int]$item - 1
                if ($idx -ge 0 -and $idx -lt $AppList.Count) {
                    $app = $AppList[$idx]
                } else {
                    # If not a valid index, try to find by port number
                    $portNum = [int]$item
                    $app = $AppList | Where-Object { (Get-FieldValue -Object $_ -Name 'Port') -eq $portNum }
                }
            } else {
                # Try to match by name (case-insensitive)
                $app = $AppList | Where-Object { (Get-FieldValue -Object $_ -Name 'Name') -ieq $item }
            }
            
            if ($null -ne $app) {
                $resultApps += $app
            }
        }
    }
    
    return $resultApps
}

function Get-ManagePyRelative {
    param([Parameter(Mandatory)] [string]$WorkingDir)
    if ($script:ManagePyCache.ContainsKey($WorkingDir)) { return $script:ManagePyCache[$WorkingDir] }
    $direct = Join-Path $WorkingDir 'manage.py'
    if (Test-Path -Path $direct) { $script:ManagePyCache[$WorkingDir] = 'manage.py'; return 'manage.py' }
    $mf = Get-ChildItem -Path $WorkingDir -Filter 'manage.py' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($mf) {
        try { $rel = [System.IO.Path]::GetRelativePath($WorkingDir, $mf.FullName) } catch { $rel = 'manage.py' }
        $script:ManagePyCache[$WorkingDir] = $rel
        return $rel
    }
    return $null
}

function Get-PackageContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$App,
        [Parameter(Mandatory)] [string]$WorkingDir
    )
    # Determine package manager
    $pm = $null
    $pmField = Get-FieldValue -Object $App -Name 'PackageManager'
    if ($App -and -not [string]::IsNullOrWhiteSpace([string]$pmField)) {
        $pm = [string]$pmField
    } else {
        if (-not $script:PyProjectCache.ContainsKey($WorkingDir)) {
            $script:PyProjectCache[$WorkingDir] = Test-Path (Join-Path $WorkingDir 'pyproject.toml')
        }
        $pm = if ($script:PyProjectCache[$WorkingDir]) { 'uv' } else { 'pip' }
    }

    $venvActivatePrefix = ''
    $bootstrapPrefix = ''
    if ($pm -ieq 'pip') {
        if (-not $script:VenvActivateCache.ContainsKey($WorkingDir)) {
            $venvPathFromApp = Get-FieldValue -Object $App -Name 'VenvPath'
            $targetVenvPath = if (-not [string]::IsNullOrWhiteSpace([string]$venvPathFromApp)) { [string]$venvPathFromApp } else { Join-Path $WorkingDir '.venv' }
            $activateScript = Join-Path $targetVenvPath 'Scripts/Activate.ps1'
            if (-not (Test-Path $activateScript)) { $activateScript = Join-Path $targetVenvPath 'Scripts\Activate.ps1' }
            $script:VenvActivateCache[$WorkingDir] = $activateScript
        }
        $activateScript = $script:VenvActivateCache[$WorkingDir]

        if (-not (Test-Path $activateScript)) {
            # Bootstrap .venv and optionally install requirements
            $reqAtRoot = Join-Path $WorkingDir 'requirements.txt'
            $escapedReq = $null
            if (Test-Path $reqAtRoot) {
                $escapedReq = ConvertTo-SingleQuotedLiteral $reqAtRoot
            } else {
                $req = Get-ChildItem -Path $WorkingDir -Recurse -Depth 2 -Filter 'requirements.txt' -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($req) { $escapedReq = ConvertTo-SingleQuotedLiteral $req.FullName }
            }
            $bootstrapPrefix = "py -m venv .venv; & '.\\.venv\\Scripts\\Activate.ps1'; "
            if ($escapedReq) { $bootstrapPrefix += "python -m pip install -r '$escapedReq'; " }
            $activateScript = Join-Path $WorkingDir '.venv\Scripts\Activate.ps1'
        }

        if (Test-Path $activateScript) {
            $venvActivatePrefix = "& '$(ConvertTo-SingleQuotedLiteral $activateScript)'; "
        }
    }

    return [pscustomobject]@{
        PackageManager   = $pm
        VenvActivate     = $venvActivatePrefix
        Bootstrap        = $bootstrapPrefix
    }
}

function New-EncodedPwshCommand {
    param(
        [Parameter(Mandatory)] [string]$WorkingDir,
        [Parameter(Mandatory)] [string]$WindowTitle,
        [Parameter(Mandatory)] [string]$RunCmd
    )
    $escapedDir = ConvertTo-SingleQuotedLiteral $WorkingDir
    $escapedTitle = ConvertTo-SingleQuotedLiteral $WindowTitle
    $commandText = "Set-Location -LiteralPath '$escapedDir'; `$host.UI.RawUI.WindowTitle = '$escapedTitle'; $RunCmd; exit `$LASTEXITCODE"
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($commandText))
}

function Start-AppsList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$AppList,
        [Parameter(Mandatory)] [string]$PwshPath,
        [switch]$DryRun
    )
    $wtInfo = Get-WindowsTerminalPath
    $wtAvailable = $wtInfo.Available

    foreach ($app in $AppList) {
        $name = Get-FieldValue -Object $app -Name 'Name'
        $appPath = Get-FieldValue -Object $app -Name 'AppPath'
        $type = Get-FieldValue -Object $app -Name 'Type'
        $indexRel = Get-FieldValue -Object $app -Name 'IndexPath'

        if (-not $name) { Write-Warning "Skipping app with missing Name."; continue }
        if (-not $appPath) { Write-Warning "Skipping '$name': missing AppPath."; continue }
        $isWebType = ($type -ieq 'Streamlit' -or $type -ieq 'Flask' -or $type -ieq 'Dash')
        if ($isWebType -and -not $indexRel) { Write-Warning "Skipping '$name': missing IndexPath."; continue }
        if (-not (Test-Path -Path $appPath)) { Write-Warning "Skipping '$name': AppPath '$appPath' not found."; continue }
        if ($isWebType) {
            $indexFull = if ($indexRel -and [System.IO.Path]::IsPathRooted($indexRel)) { $indexRel } else { Join-Path $appPath $indexRel }
            if (-not (Test-Path -Path $indexFull)) { Write-Warning "Skipping '$name': IndexPath '$indexFull' not found."; continue }
        }

        $workingDir = (Resolve-Path -Path $appPath).Path

        $escapedIndex = ConvertTo-SingleQuotedLiteral $indexRel
        $portArg = ''
        if ($type -ieq 'Streamlit') {
            $portVal = Get-FieldValue -Object $app -Name 'Port'
            if ($portVal) { $portArg = " --server.port $([string]$portVal)" } else { Write-Warning "Skipping '$name': missing Port for Streamlit app."; continue }
        }
        $basePathArg = ''
        if ($type -ieq 'Streamlit') {
            $basePathVal = Get-FieldValue -Object $app -Name 'BasePath'
            if (-not [string]::IsNullOrWhiteSpace([string]$basePathVal)) {
                $escapedBasePath = (ConvertTo-SingleQuotedLiteral $basePathVal)
            $basePathArg = " --server.baseUrlPath '$escapedBasePath'"
            }
        }
        $dashPortArg = ''
        if ($type -ieq 'Dash') {
            $dashPortVal = Get-FieldValue -Object $app -Name 'Port'
            if ($dashPortVal) { $dashPortArg = " --server.port $dashPortVal" }
        }
        $flaskHostPortArg = ''
        if ($type -ieq 'Flask') {
            $flaskPort = Get-FieldValue -Object $app -Name 'Port'
            if ($flaskPort) { $flaskHostPortArg = " --host=0.0.0.0 --port $flaskPort" }
        }

        $ctx = Get-PackageContext -App $app -WorkingDir $workingDir
        $packageManager = $ctx.PackageManager
        $venvActivatePrefix = $ctx.VenvActivate
        $bootstrapPrefix = $ctx.Bootstrap

        if ($type -ieq 'Streamlit') {
            if ($packageManager -ieq 'uv') { $runCmd = "uv run streamlit run '$escapedIndex'$portArg$basePathArg" }
            else { $runCmd = "${bootstrapPrefix}${venvActivatePrefix}streamlit run '$escapedIndex'$portArg$basePathArg" }
        } elseif ($type -ieq 'Django') {
            $manageRel = Get-ManagePyRelative -WorkingDir $workingDir
            if (-not $manageRel) { Write-Warning "Skipping '$name': manage.py not found under '$workingDir'."; continue }
            $escapedManage = $manageRel -replace "'", "''"
            $runserverPortArg = ''
            $djangoPort = Get-FieldValue -Object $app -Name 'Port'
            if ($djangoPort) { $runserverPortArg = " $djangoPort" }
            if ($packageManager -ieq 'uv') { $runCmd = "uv run '$escapedManage' runserver$runserverPortArg" }
            else { $runCmd = "${bootstrapPrefix}${venvActivatePrefix}py '$escapedManage' runserver$runserverPortArg" }
        } elseif ($type -ieq 'Dash') {
            if ($packageManager -ieq 'uv') { $runCmd = "uv run python '$escapedIndex'$dashPortArg" }
            else { $runCmd = "${bootstrapPrefix}${venvActivatePrefix}python '$escapedIndex'$dashPortArg" }
        } elseif ($type -ieq 'Flask') {
            $flaskEnvPrefix = "`$env:FLASK_APP = '$escapedIndex'; `$env:FLASK_ENV = 'development'; "
            if ($packageManager -ieq 'uv') { $runCmd = "$flaskEnvPrefix" + "uv run flask run$flaskHostPortArg" }
            else { $runCmd = "${bootstrapPrefix}${venvActivatePrefix}$flaskEnvPrefix" + "flask run$flaskHostPortArg" }
        } else {
            Write-Warning "Skipping '$name': Unsupported Type '$type'."; continue
        }

        $encoded = New-EncodedPwshCommand -WorkingDir $workingDir -WindowTitle $name -RunCmd $runCmd
        if ($DryRun) { Write-Host "[DryRun] Would start '$name' in '$workingDir' with: $runCmd"; continue }

        if ($wtAvailable) {
            $launched = New-WindowsTerminalTab -Title $name -StartingDirectory $workingDir -EncodedCommand $encoded -PwshPath $PwshPath
            if ($launched) { Write-Host "Launched '$name' in Windows Terminal tab" }
            else { Write-Warning "Failed to launch Windows Terminal, falling back to PowerShell window"; Start-Process -FilePath $PwshPath -ArgumentList @('-NoLogo','-EncodedCommand', $encoded) -WorkingDirectory $workingDir | Out-Null }
        } else {
            Write-Host "Windows Terminal not found, launching '$name' in new PowerShell window"
            Start-Process -FilePath $PwshPath -ArgumentList @('-NoLogo','-EncodedCommand', $encoded) -WorkingDirectory $workingDir | Out-Null
        }
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-SingleQuotedLiteral',
    'Get-AppsFromInput',
    'Get-ManagePyRelative',
    'Get-PackageContext',
    'New-EncodedPwshCommand',
    'Start-AppsList'
)
