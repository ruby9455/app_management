# lib/app_helpers.psm1
# Mirrors app_helpers.sh - app run command building and port utilities

function Test-VenvExists {
    param([string]$VenvPath)
    return (Test-Path (Join-Path $VenvPath 'Scripts\Activate.ps1')) -or
           (Test-Path (Join-Path $VenvPath 'Scripts\activate.bat'))
}

function Find-Venv {
    param([string]$ProjectDir)
    foreach ($name in @('.venv', 'venv', 'env', '.env')) {
        $candidate = Join-Path $ProjectDir $name
        if (Test-VenvExists -VenvPath $candidate) { return $candidate }
    }
    # Search recursively up to depth 3
    $found = Get-ChildItem -Path $ProjectDir -Recurse -Depth 3 -Filter 'Activate.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*\Scripts\Activate.ps1' } |
        Select-Object -First 1
    if ($found) { return (Split-Path (Split-Path $found.FullName)) }
    return $null
}

function Get-DetectedPackageManager {
    param([string]$ProjectDir)
    if (Test-Path (Join-Path $ProjectDir 'pyproject.toml')) { return 'uv' }
    return 'pip'
}

function Find-ManagePy {
    param([string]$WorkingDir)
    $direct = Join-Path $WorkingDir 'manage.py'
    if (Test-Path $direct) { return 'manage.py' }
    $found = Get-ChildItem -Path $WorkingDir -Filter 'manage.py' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        try { return [System.IO.Path]::GetRelativePath($WorkingDir, $found.FullName) } catch { return 'manage.py' }
    }
    return $null
}

function Find-Requirements {
    param([string]$ProjectDir)
    $root = Join-Path $ProjectDir 'requirements.txt'
    if (Test-Path $root) { return $root }
    $found = Get-ChildItem -Path $ProjectDir -Recurse -Depth 2 -Filter 'requirements.txt' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    return $found?.FullName
}

function Get-VenvActivatePrefix {
    param([string]$VenvPath)
    if ([string]::IsNullOrWhiteSpace($VenvPath)) { return '' }
    $activate = Join-Path $VenvPath 'Scripts\Activate.ps1'
    if (Test-Path $activate) { return "& '$($activate -replace "'","''")'; " }
    return ''
}

function Build-AppRunCommand {
    param(
        [hashtable]$App,
        [string]$WorkingDir
    )

    $appType      = $App['Type']
    $port         = $App['Port']
    $indexPath    = $App['IndexPath']
    $basePath     = $App['BasePath']
    $nginxPath    = $App['NginxPath']
    $venvPath     = $App['VenvPath']
    $pkgManager   = $App['PackageManager']
    $customCmd    = $App['CustomCommand']

    if ([string]::IsNullOrWhiteSpace($pkgManager)) {
        $pkgManager = Get-DetectedPackageManager -ProjectDir $WorkingDir
    }

    $activatePrefix = ''
    if ($pkgManager -ieq 'pip') {
        if ([string]::IsNullOrWhiteSpace($venvPath)) {
            $venvPath = Find-Venv -ProjectDir $WorkingDir
        }
        $activatePrefix = Get-VenvActivatePrefix -VenvPath $venvPath
    }

    $escapedIndex = if ($indexPath) { $indexPath -replace "'", "''" } else { '' }

    switch -Wildcard ($appType) {
        'Streamlit' {
            $portArg = if ($port) { " --server.port $port" } else { '' }
            $effectiveBase = $basePath
            if ([string]::IsNullOrWhiteSpace($effectiveBase) -and -not [string]::IsNullOrWhiteSpace($nginxPath)) {
                $effectiveBase = $nginxPath
            }
            $effectiveBase = $effectiveBase?.TrimStart('/')
            $baseArg = if ($effectiveBase) { " --server.baseUrlPath '$effectiveBase'" } else { '' }
            if ($pkgManager -ieq 'uv') { return "uv run streamlit run '$escapedIndex'$portArg$baseArg" }
            return "${activatePrefix}streamlit run '$escapedIndex'$portArg$baseArg"
        }
        'Django' {
            $managePy = Find-ManagePy -WorkingDir $WorkingDir
            if (-not $managePy) { throw "manage.py not found under '$WorkingDir'" }
            $escapedManage = $managePy -replace "'", "''"
            if (-not [string]::IsNullOrWhiteSpace($customCmd)) {
                if ($pkgManager -ieq 'uv') { return "uv run python '$escapedManage' $customCmd" }
                return "${activatePrefix}python '$escapedManage' $customCmd"
            }
            $portArg = if ($port) { " $port" } else { '' }
            if ($pkgManager -ieq 'uv') { return "uv run python '$escapedManage' runserver$portArg" }
            return "${activatePrefix}python '$escapedManage' runserver$portArg"
        }
        'Dash' {
            $portArg = if ($port) { " --server.port $port" } else { '' }
            if ($pkgManager -ieq 'uv') { return "uv run python '$escapedIndex'$portArg" }
            return "${activatePrefix}python '$escapedIndex'$portArg"
        }
        'Flask' {
            $portArg = if ($port) { " --host=0.0.0.0 --port $port" } else { '' }
            $flaskEnv = "`$env:FLASK_APP = '$escapedIndex'; `$env:FLASK_ENV = 'development'; "
            if ($pkgManager -ieq 'uv') { return "${flaskEnv}uv run flask run$portArg" }
            return "${flaskEnv}${activatePrefix}flask run$portArg"
        }
        default {
            if (-not [string]::IsNullOrWhiteSpace($customCmd)) {
                $firstToken = ($customCmd -split '\s+')[0]
                $isFullCmd = ($firstToken -match '[/\\]') -or ($firstToken -match '^(python|uv|pip|pwsh|py)$')
                if ($isFullCmd) {
                    if ($pkgManager -ieq 'uv' -and $firstToken -notmatch '^uv$') { return "uv run $customCmd" }
                    return "${activatePrefix}$customCmd"
                }
                $managePy = Find-ManagePy -WorkingDir $WorkingDir
                if ($managePy) {
                    $escapedManage = $managePy -replace "'", "''"
                    if ($pkgManager -ieq 'uv') { return "uv run python '$escapedManage' $customCmd" }
                    return "${activatePrefix}python '$escapedManage' $customCmd"
                }
                if ($pkgManager -ieq 'uv') { return "uv run $customCmd" }
                return "${activatePrefix}$customCmd"
            }
            throw "Unsupported app type: $appType"
        }
    }
}

function Test-PortInUse {
    param([int]$Port)
    try {
        $conns = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
        return ($null -ne $conns -and @($conns).Count -gt 0)
    } catch { return $false }
}

function Get-PidsOnPort {
    param([int]$Port)
    try {
        $conns = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
        if (-not $conns) { return @() }
        return @($conns | Select-Object -ExpandProperty OwningProcess -Unique)
    } catch { return @() }
}

function Stop-Port {
    param([int]$Port)
    $pids = Get-PidsOnPort -Port $Port
    foreach ($pid in $pids) {
        try { Stop-Process -Id $pid -Force -ErrorAction Stop } catch { }
    }
    Start-Sleep -Seconds 1
}

function Wait-ForPortFree {
    param([int]$Port, [int]$TimeoutSec = 10)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-PortInUse -Port $Port)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

Export-ModuleMember -Function @(
    'Test-VenvExists',
    'Find-Venv',
    'Get-DetectedPackageManager',
    'Find-ManagePy',
    'Find-Requirements',
    'Get-VenvActivatePrefix',
    'Build-AppRunCommand',
    'Test-PortInUse',
    'Get-PidsOnPort',
    'Stop-Port',
    'Wait-ForPortFree'
)
