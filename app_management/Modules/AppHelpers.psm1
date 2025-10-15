# Requires -Version 7.0
# AppHelpers.psm1 (relocated under Modules)
# Re-export by referencing original file to avoid duplication; include content inline for simplicity

# Dedupe by name (case-insensitive)
function Select-UniqueAppsByName {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$Apps
    )
    return @($Apps | Group-Object { $_.Name.ToString().ToLowerInvariant() } | ForEach-Object { $_.Group | Select-Object -First 1 })
}

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

function Test-FieldHasValue {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Object,
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    $value = Get-FieldValue -Object $Object -Name $Name
    return ($null -ne $value -and ([string]::IsNullOrWhiteSpace([string]$value) -eq $false))
}

function ConvertTo-NormalizedAppsList {
    param(
        [AllowNull()]
        $Apps
    )
    $arr = @()
    if ($null -ne $Apps) {
        if ($Apps -is [array]) { $arr = $Apps } else { $arr = @($Apps) }
    }
    $supported = @('Streamlit','Django','Dash','Flask')
    $filtered = $arr | Where-Object { $_ -and $_.Type -and ($supported -contains $_.Type) }
    return (Select-UniqueAppsByName -Apps @($filtered))
}

function ConvertTo-Hashtable {
    param (
        [Parameter(Mandatory=$true)]
        [object]$Object
    )

    if ($null -eq $Object) { return @{} }
    if ($Object -is [hashtable]) {
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

function Test-Venv {
    param(
        [string]$Directory
    )
    $venvPath = Join-Path -Path $Directory -ChildPath "Scripts/activate.bat"
    if (-not (Test-Path $venvPath)) { $venvPath = Join-Path -Path $Directory -ChildPath "Scripts\Activate.ps1" }
    return (Test-Path $venvPath)
}

function Find-Venv {
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

function Get-VenvDirectory { 
    do {
        $venvPath = Read-Host "Enter the absoulte path for directory containing 'Scripts/activate.bat'"
        if (-not (Test-Venv -Directory $venvPath)) {
            Write-Host "The specified path '$venvPath' does not contain a valid venv."
        }
    } while (-not (Test-Venv -Directory $venvPath))
    return $venvPath
}

function Get-RequirementsContent {
    param (
        [string]$ProjectDirectory
    )
    $requirementsFile = Get-ChildItem -Path $ProjectDirectory -Recurse -Filter "requirements.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($requirementsFile) { return Get-Content $requirementsFile.FullName } else { return "No requirements.txt found" }
}

function Get-PackageManager {
    param (
        [string]$ProjectDirectory
    )
    $pyprojectFile = Join-Path $ProjectDirectory "pyproject.toml"
    if (Test-Path $pyprojectFile) { return "uv" } else { return "pip" }
}

function Get-AppType {
    param (
        [string]$ProjectDirectory
    )
    $packageManager = Get-PackageManager -ProjectDirectory $ProjectDirectory
    if ($packageManager -eq "uv") {
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

    # Build a display list with indices and relative paths for user-friendly output
    $items = @()
    for ($i = 0; $i -lt $allPyFiles.Length; $i++) {
        $fullPath = $allPyFiles[$i]
        $displayPath = $fullPath -replace [regex]::Escape($ProjectDirectory), '~'
        $displayPath = $displayPath -replace '\\', '/'
        $relative = $fullPath.Substring($ProjectDirectory.Length + 1)
        $items += [pscustomobject]@{
            Index    = $i + 1
            FullPath = $fullPath
            Relative = $relative
            Display  = $displayPath
        }
    }

    # Initial full list
    foreach ($it in $items) {
        Write-Host ("{0}: {1}" -f $it.Index, $it.Display)
    }

    # Helper to perform a simple fuzzy (subsequence) match, case-insensitive
    function Invoke-FuzzyMatch {
        param(
            [Parameter(Mandatory=$true)][string]$Query,
            [Parameter(Mandatory=$true)][object[]]$SourceItems
        )
        # If the query contains path separators or a dot, prefer simple substring search to reduce overmatching
        if ($Query -match "[\\/\.]") {
            $q = $Query.ToLowerInvariant()
            return @(
                $SourceItems | Where-Object {
                    ($_.Relative -replace '\\','/').ToLowerInvariant().Contains($q) -or $_.Display.ToLowerInvariant().Contains($q)
                }
            )
        }

        # Otherwise, use a subsequence regex: abc -> a.*b.*c (case-insensitive)
        $pattern = ($Query.ToCharArray() | ForEach-Object { [regex]::Escape($_) }) -join '.*'
        if ([string]::IsNullOrWhiteSpace($pattern)) { return @() }
        $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        return @($SourceItems | Where-Object { $regex.IsMatch(($_.Relative -replace '\\','/')) -or $regex.IsMatch($_.Display) })
    }

    $chosen = $null
    do {
        $input = Read-Host "Enter the index of the index python file (or type to fuzzy-search; 'q' to cancel)"
        if ($null -eq $input) { continue }
        $input = [string]$input

        if ($input -match '^(?i:q|quit|exit)$') { return $null }

        if ($input -match '^\d+$') {
            $idx = [int]$input
            if ($idx -ge 1 -and $idx -le $items.Count) {
                $chosen = $items[$idx - 1]
                break
            } else {
                Write-Host "Invalid index. Please enter a number between 1 and $($items.Count)."
                continue
            }
        }

        # Fuzzy search branch
        $fuzzyMatches = Invoke-FuzzyMatch -Query $input -SourceItems $items
        if ($fuzzyMatches.Count -eq 0) {
            Write-Host "No matches found for '$input'. Try again."
            continue
        }
        if ($fuzzyMatches.Count -eq 1) {
            $chosen = $fuzzyMatches[0]
            break
        }

        # Multiple matches: show a compact list and allow picking or refining
        Write-Host ("Multiple matches found ($($fuzzyMatches.Count)):")
        for ($i = 0; $i -lt $fuzzyMatches.Count; $i++) {
            Write-Host ("[{0}] {1}" -f ($i+1), $fuzzyMatches[$i].Display)
        }
        $sub = Read-Host "Enter a number 1..$($fuzzyMatches.Count) to pick, or type more text to refine"
        if ($sub -match '^\d+$') {
            $subIdx = [int]$sub
            if ($subIdx -ge 1 -and $subIdx -le $fuzzyMatches.Count) {
                $chosen = $fuzzyMatches[$subIdx - 1]
                break
            } else {
                Write-Host "Invalid selection."
                continue
            }
        } elseif (-not [string]::IsNullOrWhiteSpace($sub)) {
            # Treat as a refined query and loop again
            $input = $sub
            continue
        } else {
            continue
        }
    } while ($true)

    # Return the relative path like original implementation
    $selectedPyFile = $chosen.FullPath
    $selectedPyFile = $selectedPyFile.Substring($ProjectDirectory.Length + 1)
    return $selectedPyFile
}

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
                $portCheck = Test-NetConnection -ComputerName "localhost" -Port $port
                if ($portCheck.TcpTestSucceeded -eq $true) { Write-Host "Port $port is already in use. Please enter a different port." }
            }
        } while ($portCheck.TcpTestSucceeded -eq $true)
        return $port
    }
}

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

function Update-Venv {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App
    )
    
    $name = $App.Name
    $appPath = $App.AppPath
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
        $requirementsFile = $null
        if ($App.PSObject.Properties.Match('appRequirements').Count -gt 0 -and ([string]::IsNullOrWhiteSpace([string]$App.appRequirements) -eq $false)) {
            Write-Host "Using requirements file from app settings..."
            $requirementsFile = [string]$App.appRequirements
        } else {
            $requirementsFile = Get-ChildItem -Path $appPath -Recurse -Filter "requirements.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
        }

        if ($null -eq $requirementsFile) {
            Write-Warning "requirements.txt not found in '$appPath' for app '$name'."
            return
        }

        $requirementsFilePath = if ($requirementsFile -is [string]) { $requirementsFile } else { $requirementsFile.FullName }
        
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

# Export only approved-verb functions
Export-ModuleMember -Function @(
    'Get-FieldValue',
    'Set-FieldValue',
    'Test-FieldHasValue',
    'ConvertTo-Hashtable',
    'ConvertTo-NormalizedAppsList',
    'Select-UniqueAppsByName',
    'Test-Venv',
    'Find-Venv',
    'Get-VenvDirectory',
    'Get-RequirementsContent',
    'Get-PackageManager',
    'Get-AppType',
    'Get-AllUniquePyFile',
    'Get-IndexPyFile',
    'Get-PortNumber',
    'Update-AppRepo',
    'Update-Venv'
)
