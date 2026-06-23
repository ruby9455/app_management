# lib/json_helpers.psm1
# Mirrors json_helpers.sh - apps.json CRUD helpers

function Add-AppToJson {
    param([string]$JsonFile, [hashtable]$AppObj)
    $arr = @()
    if (Test-Path $JsonFile) {
        $arr = @(Get-Content $JsonFile -Raw | ConvertFrom-Json)
    }
    $arr += [pscustomobject]$AppObj
    $arr | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFile -Encoding UTF8
}

function Update-AppInJson {
    param([string]$JsonFile, [string]$AppName, [hashtable]$NewApp)
    $arr = @(Get-Content $JsonFile -Raw | ConvertFrom-Json)
    $updated = $arr | ForEach-Object {
        if ($_.Name -ieq $AppName) { [pscustomobject]$NewApp } else { $_ }
    }
    @($updated) | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFile -Encoding UTF8
}

function Remove-AppFromJson {
    param([string]$JsonFile, [string]$AppName)
    $arr = @(Get-Content $JsonFile -Raw | ConvertFrom-Json)
    $filtered = @($arr | Where-Object { $_.Name -ine $AppName })
    $filtered | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFile -Encoding UTF8
}

function Test-AppNameExists {
    param([string]$JsonFile, [string]$AppName)
    if (-not (Test-Path $JsonFile)) { return $false }
    $arr = @(Get-Content $JsonFile -Raw | ConvertFrom-Json)
    return ($arr | Where-Object { $_.Name -ieq $AppName }).Count -gt 0
}

function Get-DetectedAppType {
    param([string]$ProjectDir)
    $pyproj = Join-Path $ProjectDir 'pyproject.toml'
    if (Test-Path $pyproj) {
        $content = Get-Content $pyproj -Raw
        if ($content -match '(?i)streamlit') { return 'Streamlit' }
        if ($content -match '(?i)django')    { return 'Django' }
        if ($content -match '(?i)flask')     { return 'Flask' }
        if ($content -match '(?i)dash')      { return 'Dash' }
    }
    $req = Get-ChildItem -Path $ProjectDir -Recurse -Depth 2 -Filter 'requirements.txt' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($req) {
        $content = Get-Content $req.FullName -Raw
        if ($content -match '(?i)streamlit') { return 'Streamlit' }
        if ($content -match '(?i)django')    { return 'Django' }
        if ($content -match '(?i)flask')     { return 'Flask' }
        if ($content -match '(?i)dash')      { return 'Dash' }
    }
    return 'Unknown'
}

function Find-PythonFiles {
    param([string]$ProjectDir)
    $venvDirs = Get-ChildItem -Path $ProjectDir -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { (Test-Path (Join-Path $_.FullName 'Scripts\Activate.ps1')) }
    $venvPaths = @($venvDirs | ForEach-Object { $_.FullName })
    return @(Get-ChildItem -Path $ProjectDir -Recurse -Filter '*.py' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $fp = $_.FullName
            -not ($venvPaths | Where-Object { $fp -like "$_*" })
        } | Select-Object -ExpandProperty FullName -Unique | Sort-Object)
}

function Select-IndexFile {
    param([string]$ProjectDir)
    $files = Find-PythonFiles -ProjectDir $ProjectDir
    if ($files.Count -eq 0) { return $null }
    Write-Host "Found Python files:"
    for ($i = 0; $i -lt $files.Count; $i++) {
        try { $rel = [System.IO.Path]::GetRelativePath($ProjectDir, $files[$i]) } catch { $rel = $files[$i] }
        Write-Host ("  {0}) {1}" -f ($i + 1), $rel)
    }
    $sel = Read-Host "Select index file (number or path)"
    if ($sel -match '^\d+$') {
        $idx = [int]$sel - 1
        if ($idx -ge 0 -and $idx -lt $files.Count) {
            try { return [System.IO.Path]::GetRelativePath($ProjectDir, $files[$idx]) } catch { return $files[$idx] }
        }
    }
    return $sel
}

function Get-RandomFreePort {
    $maxAttempts = 50
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        $port = Get-Random -Minimum 3000 -Maximum 9000
        if (-not (Test-PortInUse -Port $port)) { return $port }
    }
    return Get-Random -Minimum 3000 -Maximum 9000
}

function Read-PortNumber {
    $response = Read-Host "Assign a random port? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($response) -or $response -imatch '^(y|yes)$') {
        $port = Get-RandomFreePort
        Write-Host "Assigned port: $port"
        return $port
    }
    do {
        $portStr = Read-Host "Enter port number"
        if ($portStr -match '^\d+$') {
            $port = [int]$portStr
            if (Test-PortInUse -Port $port) {
                Write-Host "Port $port is already in use. Try another."
            } else {
                return $port
            }
        } else {
            Write-Host "Invalid port number."
        }
    } while ($true)
}

function Build-AppJson {
    param(
        [string]$Name, [string]$AppType, [int]$Port,
        [string]$AppPath, [string]$IndexPath = '',
        [string]$VenvPath = '', [string]$PkgManager = '',
        [string]$NginxPath = ''
    )
    $obj = [ordered]@{ Name = $Name; Type = $AppType; Port = $Port; AppPath = $AppPath }
    if ($IndexPath)  { $obj['IndexPath']      = $IndexPath }
    if ($VenvPath)   { $obj['VenvPath']        = $VenvPath }
    if ($PkgManager) { $obj['PackageManager']  = $PkgManager }
    if ($NginxPath)  { $obj['NginxPath']       = $NginxPath }
    return $obj
}

function Build-ProcessJson {
    param(
        [string]$Name, [string]$AppPath, [string]$CustomCommand,
        [string]$VenvPath = '', [string]$PkgManager = ''
    )
    $obj = [ordered]@{ Name = $Name; AppPath = $AppPath; CustomCommand = $CustomCommand }
    if ($VenvPath)   { $obj['VenvPath']       = $VenvPath }
    if ($PkgManager) { $obj['PackageManager'] = $PkgManager }
    return $obj
}

Export-ModuleMember -Function @(
    'Add-AppToJson',
    'Update-AppInJson',
    'Remove-AppFromJson',
    'Test-AppNameExists',
    'Get-DetectedAppType',
    'Find-PythonFiles',
    'Select-IndexFile',
    'Get-RandomFreePort',
    'Read-PortNumber',
    'Build-AppJson',
    'Build-ProcessJson'
)
