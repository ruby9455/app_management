$global:apps = @()

# Function to check if a directory contains a virtual environment
function Test-Venv {
    param(
        [string]$Directory
    )

    # Check if 'Scripts\activate.bat' exists in the specified directory
    $venvPath = Join-Path -Path $Directory -ChildPath "Scripts\activate.bat"
    return Test-Path $venvPath
}

# Function to return the name of the virtual environment directory containing Scripts\activate.bat
function Get-VenvDirectory {
    param (
        [string]$ProjectDirectory
    )
    
    # Search for subdirectories containing 'Scripts\activate.bat'
    $venvDir = Get-ChildItem -Path $ProjectDirectory -Recurse -Directory | Where-Object {
        Test-Path "$($_.FullName)\Scripts\activate.bat"
    }
    Write-Host "Found virtual environment in $ProjectDirectory"
    Write-Host "Number of virtual environments found: $($venvDir.Count)"
    if ($venvDir.Count -eq 1) {
        return $venvDir.Name
    } elseif ($venvDir.Count -gt 1) {
        Write-Host "Multiple virtual environments found in $ProjectDirectory"
        for ($i = 0; $i -lt $venvDir.Count; $i++) {
            Write-Host "$($i+1): $($venvDir[$i].FullName)"
        }
        $index = [int](Read-Host "Enter the index of the virtual environment to use") - 1
        return $venvDir[$index].Name
    } else {
        # Write-Host "No virtual environment found in $ProjectDirectory"
        return $null
    }
}

# Function to find the project directories that contain a virtual environment
function Get-ProjectDirectories {
    $projectDirectories = Get-ChildItem -Directory -Recurse | Where-Object {
        # Check if the directory contains 'Scripts\activate.bat' (virtual environment)
        Test-Path "$($_.FullName)\Scripts\activate.bat"
    } | ForEach-Object {
        # Return the parent directory of the venv
        $_.Parent.FullName
    } | Select-Object -Unique

    Write-Host "Found the following project directories: $projectDirectories"
    return $projectDirectories
}

# Function to get the content of requirements.txt file
function Get-RequirementsContent {
    param (
        [string]$ProjectDirectory
    )
    
    # Search for requirements.txt file in the project directory and its subdirectories
    $requirementsFile = Get-ChildItem -Path $ProjectDirectory -Recurse -Filter "requirements.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($requirementsFile) {
        return Get-Content $requirementsFile.FullName
    } else {
        return "No requirements.txt found"
    }
}

# Function to determine the application type based on the content of requirements.txt
function Get-AppType {
    param (
        [string]$ProjectDirectory
    )
    $RequirementsContent = Get-RequirementsContent -ProjectDirectory $ProjectDirectory

    # Join all the lines and remove any unwanted spaces at the start and end
    $requirementsText = ($RequirementsContent -join "`n").Trim()

    # Split into individual lines
    $requirementsList = $requirementsText -split "`n" | Where-Object { $_.Trim() -ne "" }

    # Extract package names (before '==') and remove extra spaces
    $packageNames = $requirementsList | ForEach-Object {
        $line = $_.Trim()
        $packageName = $line.Split('==')[0].Trim()  # Extract the package name (before '==')
        return $packageName
    }

    # Check for specific packages
    if ($packageNames -contains "flask") {
        return "Flask"
    } elseif ($packageNames -contains "django") {
        return "Django"
    } elseif ($packageNames -contains "streamlit") {
        return "Streamlit"
    } else {
        return "Unknown Application Type"
    }
}

# Function to get all unique .py files in the project directory excluding virtual environment

function Get-AllUniquePyFile {
    param (
        [string]$ProjectDirectory
    )

    # Find all virtual environment directories
    $venvDirectories = Get-ChildItem -Path $ProjectDirectory -Recurse -Directory | Where-Object {
        Test-Venv -Directory $_.FullName
    }
    
    # Construct the full paths to the virtual environment directories
    $venvPaths = $venvDirectories | ForEach-Object { $_.FullName }
    
    # Get all Python files, excluding those in the virtual environment directories
    $allPyFiles = Get-ChildItem -Path $ProjectDirectory -Recurse -Filter *.py | Where-Object {
        $filePath = $_.FullName
        $isInVenv = $false
        foreach ($venvPath in $venvPaths) {
            if ($filePath -like "$venvPath*") {
                $isInVenv = $true
                break
            }
        }
        -not $isInVenv
    } | Select-Object -ExpandProperty FullName -Unique
    
    return $allPyFiles
}

# Function to get the index of the Python file to be used as the main program
function Get-IndexPyFile {
    param (
        [string]$ProjectDirectory
    )
    
    $allPyFiles = Get-AllUniquePyFile -ProjectDirectory $ProjectDirectory
    for ($i = 0; $i -lt $allPyFiles.Length; $i++) {
        Write-Host "$($i+1): $($allPyFiles[$i])"
    }
    $indexPage = [int](Read-Host "Enter the index of the index python file")
    $indexPage = $indexPage - 1
    $selectedPyFile = $allPyFiles[$indexPage]
    $selectedPyFile = $selectedPyFile.Substring($ProjectDirectory.Length + 1)
    return $selectedPyFile
}

# Function to check if a port is already assigned to an app in the global apps list
function Test-PortAvailability {
    param (
        [int]$Port
    )

    foreach ($app in $global:apps) {
        if ($app.Port -eq $Port) {
            return $true
        }
    }
    return $false
}

# Get the port number for the app - helper function for Add-AppSetting and Update-AppSetting
function Get-PortNumber {
    $portResponse = Read-Host "Would you like to assign a random port for this app? (y/n)"
    if ($portResponse -ieq "yes" -or $portResponse -ieq "y") {
        do { # Keep generating a random port until an unused port is found
            $port = Get-Random -Minimum 3000 -Maximum 9000
            $portCheck = Test-NetConnection -ComputerName "localhost" -Port $port
        } while ($portCheck.TcpTestSucceeded -eq $true -or (Test-PortAvailability -Port $port))
        return $port
    } else {
        do { # Keep asking until an unused port is entered
            $port = Read-Host "Enter a specific port number (or 'help' to use a random port)"
            if ($port -eq "help") {
                Write-Host "Generating a random port number..."
                do {
                    $port = Get-Random -Minimum 3000 -Maximum 9000
                    $portCheck = Test-NetConnection -ComputerName "localhost" -Port $port
                } while ($portCheck.TcpTestSucceeded -eq $true -or (Is-PortAssigned -Port $port))
            } else {
                $port = [int]$port
                $portCheck = Test-NetConnection -ComputerName "localhost" -Port $Port
                if ($portCheck.TcpTestSucceeded -eq $true) {
                    Write-Host "Port $Port is already in use. Please enter a different port."
                }
            }
        } while ($portCheck.TcpTestSucceeded -eq $true -or (Is-PortAssigned -Port $port))
        return $port
    }
}

# Function to save as JSON file
function Set-Json {
    param (
        [string]$jsonFilePath = "apps.json"
    )

    try {
        if (Test-Path $jsonFilePath) {
            $response = Read-Host "The file $jsonFilePath already exists. Do you want to overwrite (o) or extend (e) it? (o/e)"
            if ($response -ieq "o") {
                # Overwrite the file
                $global:apps | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFilePath -Encoding UTF8
                Write-Host "Apps list saved successfully to $jsonFilePath."
            } elseif ($response -ieq "e") {
                # Extend the file
                $existingContent = Get-Content -Path $jsonFilePath | ConvertFrom-Json
                # Check if the existing content is an array
                if ($existingContent -is [array]) {
                    $global:apps = $global:apps + $existingContent
                } else {
                    $global:apps = $global:apps + @($existingContent)
                }
                $global:apps | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFilePath -Encoding UTF8
                Write-Host "Apps list extended and saved successfully to $jsonFilePath."
            } else {
                Write-Host "Invalid option. No changes made to $jsonFilePath."
            }
        } else {
            # Create the file
            $global:apps | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFilePath -Encoding UTF8
            Write-Host "Apps list saved successfully to $jsonFilePath."
        }
    } catch {
        Write-Host "Failed to save file: $($_.Exception.Message)"
    }
}

# Main script
$projectDirectories = Get-ProjectDirectories
foreach ($projectDirectory in $projectDirectories) {
    $venvDirectory = Get-VenvDirectory -ProjectDirectory $projectDirectory
    
    if (-not $venvDirectory) {
        Write-Host "No virtual environment found in $projectDirectory. Skipping..."
        continue
    }
    
    $newApp = [PSCustomObject]@{
        Name = Split-Path -Leaf $projectDirectory
        Type = Get-AppType -ProjectDirectory $projectDirectory
        VenvPath = Join-Path -Path $projectDirectory -ChildPath $venvDirectory
        AppPath = $projectDirectory
        IndexPath = Get-IndexPyFile -ProjectDirectory $projectDirectory -VenvDirectory $venvDirectory
        Port = Get-PortNumber
    }

    Write-Host "Adding the following app to the configuration:"
    $newApp | Format-List

    # Add the new app to the global list of apps
    $global:apps += $newApp
}

Set-Json -jsonFilePath "apps.json"
Write-Host "Configuration saved successfully."
