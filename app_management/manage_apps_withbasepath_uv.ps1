# Load the apps list from JSON file if it exists, otherwise create an empty list
$jsonFilePath = "$PSScriptRoot\apps.json"
Write-Host "Reading apps setting from : $jsonFilePath"

if (Test-Path $jsonFilePath) {
    if ((Get-Item $jsonFilePath).Length -eq 0) {
        $global:apps = @()
    } else {
        $global:apps = Get-Content $jsonFilePath | ConvertFrom-Json
        # Ensure that $global:apps is an array after reading back from JSON
        if ($global:apps -isnot [array]) {
            $global:apps = @($global:apps)
        }
        $global:apps = $global:apps | Where-Object { $_.Name -notmatch "deprecated" }
    }    
} else {
    $global:apps = @()
}

# Functions
# Show all apps with indices
function Show-Apps {
    Write-Host "===== All available apps ====="
    $sortedApps = $apps | Sort-Object Name
    for ($i = 0; $i -lt $sortedApps.Count; $i++) {
        Write-Host "$($i+1): $($sortedApps[$i].Name)"
    }
    return $sortedApps
}

# Get app by name or index
function Get-AppByNameOrIndex {
    param(
        [string]$inputValue,
        [array]$appList = $null
    )
    
    # Use provided appList or default to sorted apps
    if ($null -eq $appList) {
        $appList = $apps | Sort-Object Name
    }
    
    # Check if input is a number (index)
    if ($inputValue -match '^\d+$') {
        $index = [int]$inputValue - 1
        if ($index -ge 0 -and $index -lt $appList.Count) {
            return $appList[$index]
        } else {
            Write-Output "Invalid index. Please enter a number between 1 and $($appList.Count)."
            return $null
        }
    } else {
        # Search by name (case-insensitive) in the provided list
        $app = $appList | Where-Object { $_.Name -ieq $inputValue }
        if ($null -eq $app) {
            Write-Output "App '$inputValue' not found."
            return $null
        }
        return $app
    }
}

# Enable the virtual environment - helper function for Start-App
function Enable-Venv {
    param (
        [string]$venvPath
    )

    if (-not (Test-Path $venvPath)) {
        Write-Output "Path '$venvPath' does not exist."
        return
    }

    Write-Output "Activating virtual environment..."
    $activateScript = Join-Path $venvPath "Scripts\Activate.ps1"

    if (-not (Test-Path $activateScript)) {
        Write-Output "Activation script not found at '$activateScript'."
        return
    }

    & $activateScript
}

# Start the Streamlit app - helper function for Start-App
function Start-StreamlitApp {
    param (
        [hashtable]$app  
    )

    $appPath = $app.AppPath
    $appIndexPath = $app.IndexPath
    $appPort = $app.Port
    $venvPath = $app.VenvPath

    if (-not (Test-Path $appPath)) {
        Write-Output "Path '$appPath' does not exist."
        return
    }

    $indexFile = Join-Path $appPath $appIndexPath
    if (-not (Test-Path $indexFile)) {
        Write-Output "Index path '$indexFile' does not exist."
        return
    }

    # Check package manager to determine how to start the app
    $packageManager = if ($app.PackageManager) { $app.PackageManager } else { Get-PackageManager -ProjectDirectory $appPath }
    
    if ($packageManager -eq "uv") {
        Set-Location -Path $appPath
        Write-Output "Starting Streamlit app '$($app.Name)' with uv on port $appPort..."
        $command = "uv run streamlit run $appIndexPath --server.port $appPort"
        if ($app.ContainsKey("BasePath")) {
            $command += " --server.baseUrlPath $($app["BasePath"])"
        }
        if ($app.ContainsKey("ENV")) {
            $envCommand = "set ENV=$($app["ENV"]) && "
            $command = $envCommand + $command
        }
        Start-Process "cmd.exe" -ArgumentList "/k", $command -WorkingDirectory $appPath -WindowStyle Minimized
    } else {
        Enable-Venv -venvPath $venvPath
        Set-Location -Path $appPath
        Write-Output "Starting Streamlit app '$($app.Name)' on port $appPort..."
        $command = "streamlit run $appIndexPath --server.port $appPort"
        if ($app.ContainsKey("BasePath")) {
            $command += " --server.baseUrlPath $($app["BasePath"])"
        }
        if ($app.ContainsKey("ENV")) {
            $envCommand = "set ENV=$($app["ENV"]) && "
            $command = $envCommand + $command
        }
        Start-Process "cmd.exe" -ArgumentList "/k", $command -WorkingDirectory $appPath -WindowStyle Minimized
    }
}

# Helper function to find the directory containing manage.py under AppPath
function Get-ManagePyDirectory {
    param (
        [string]$AppPath
    )
    $manageFile = Get-ChildItem -Path $AppPath -Recurse -Filter "manage.py" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($manageFile) {
        $relativeDir = $manageFile.DirectoryName.Substring($AppPath.Length).TrimStart('\','/')
        return $relativeDir
    } else {
        return $null
    }
}

# Start the Django app - helper function for Start-App
function Start-DjangoApp {
    param (
        [hashtable]$app  
    )

    $appPath = $app.AppPath
    $appPort = $app.Port
    $venvPath = $app.VenvPath

    if (-not (Test-Path $appPath)) {
        Write-Output "Path '$appPath' does not exist."
        return
    }

    # Find manage.py directory relative to appPath
    $manageDir = Get-ManagePyDirectory -AppPath $appPath
    if ($null -eq $manageDir) {
        Write-Output "manage.py not found under '$appPath'."
        return
    }
    if ($manageDir) {
        $managePyPath = Join-Path $manageDir "manage.py"
    } else {
        $managePyPath = "manage.py"
    }

    # Check package manager to determine how to start the app
    $packageManager = if ($app.PackageManager) { $app.PackageManager } else { Get-PackageManager -ProjectDirectory $appPath }
    
    if ($packageManager -eq "uv") {
        Set-Location -Path $appPath
        if ($app.ContainsKey("CustomCommand") -and $app.CustomCommand) {
            $customCmd = $app.CustomCommand
            Write-Output "Starting Django app '$($app.Name)' with uv and custom command: $customCmd ..."
            $command = "uv run $managePyPath $customCmd"
        } else {
            Write-Output "Starting Django app '$($app.Name)' with uv on port $appPort..."
            $command = "uv run $managePyPath runserver 0.0.0.0:$appPort"
        }
    } else {
        Enable-Venv -venvPath $venvPath
        Set-Location -Path $appPath
        if ($app.ContainsKey("CustomCommand") -and $app.CustomCommand) {
            $customCmd = $app.CustomCommand
            Write-Output "Starting Django app '$($app.Name)' with python and custom command: $customCmd ..."
            $command = "python $managePyPath $customCmd"
        } else {
            Write-Output "Starting Django app '$($app.Name)' on port $appPort..."
            $command = "python $managePyPath runserver 0.0.0.0:$appPort"
        }
    }
    # Write-Host "DEBUG: Start-Process 'cmd.exe' -ArgumentList '/k $command' -WorkingDirectory $appPath -WindowStyle Minimized"
    Start-Process "cmd.exe" -ArgumentList "/k $command" -WorkingDirectory $appPath -WindowStyle Minimized
}

# Start the Flask app - helper function for Start-App
function Start-FlaskApp {
    param (
        [hashtable]$app  
    )

    $appPath = $app.AppPath
    $appIndexPath = $app.IndexPath
    $venvPath = $app.VenvPath
    $appPort = $app.Port

    if (-not (Test-Path $appPath)) {
        Write-Output "Path '$appPath' does not exist."
        return
    }

    # Check package manager to determine how to start the app
    $packageManager = if ($app.PackageManager) { $app.PackageManager } else { Get-PackageManager -ProjectDirectory $appPath }
    
    if ($packageManager -eq "uv") {
        Set-Location -Path $appPath
        $env:FLASK_APP = $appIndexPath
        $env:FLASK_ENV = "development"
        Write-Output "Starting Flask app '$($app.Name)' with uv on port $appPort..."
        Start-Process "cmd.exe" -ArgumentList "/k", "uv run flask run --host=0.0.0.0 --port $appPort" -WorkingDirectory $appPath -WindowStyle Minimized
    } else {
        Enable-Venv -venvPath $venvPath
        Set-Location -Path $appPath
        $env:FLASK_APP = $appIndexPath
        $env:FLASK_ENV = "development"
        Write-Output "Starting Flask app '$($app.Name)' on port $appPort..."
        Start-Process "cmd.exe" -ArgumentList "/k", "flask run --host=0.0.0.0 --port $appPort" -WorkingDirectory $appPath -WindowStyle Minimized
    }
}

function Start-DashApp {
    param (
        [hashtable]$app  
    )

    $appPath = $app.AppPath
    $appIndexPath = $app.IndexPath
    $venvPath = $app.VenvPath
    $appPort = $app.Port

    if (-not (Test-Path $appPath)) {
        Write-Output "Path '$appPath' does not exist."
        return
    }

    # Check package manager to determine how to start the app
    $packageManager = if ($app.PackageManager) { $app.PackageManager } else { Get-PackageManager -ProjectDirectory $appPath }
    
    if ($packageManager -eq "uv") {
        Set-Location -Path $appPath
        Write-Output "Starting Dash app '$($app.Name)' with uv on port $appPort..."
        Start-Process "cmd.exe" -ArgumentList "/k", "uv run python $appIndexPath $appPort" -WorkingDirectory $appPath -WindowStyle Minimized
    } else {
        Enable-Venv -venvPath $venvPath
        Set-Location -Path $appPath
        Write-Output "Starting Dash app '$($app.Name)' on port $appPort..."
        Start-Process "cmd.exe" -ArgumentList "/k", "python $appIndexPath $appPort" -WorkingDirectory $appPath -WindowStyle Minimized
    }
}

# Convert a PSObject to a hashtable
function ConvertTo-Hashtable {
    param (
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Object
    )

    $hashtable = @{}
    foreach ($property in $Object.PSObject.Properties) {
        $hashtable[$property.Name] = $property.Value
    }
    return $hashtable
}

# Start an app
function Start-App {
    param (
        [string]$appName
    )
    Write-Host "===== Start App ====="
    $app = Get-AppByNameOrIndex -inputValue $appName
    if ($null -eq $app) {
        return
    }

    # Convert $app to a hashtable
    $app = ConvertTo-Hashtable -Object $app

    if (-not ($app -is [hashtable])) {
        Write-Output "Failed to convert app to hashtable."
        return
    }

    switch ($app.Type) {
        "Streamlit" { Start-StreamlitApp -app $app }  # Pass $app object
        "Django" { Start-DjangoApp -app $app }  # Pass $app object
        "Flask" { Start-FlaskApp -app $app }  # Pass $app object
        "Dash" { Start-DashApp -app $app }  # Pass $app object
        default { Write-Output "Unknown app type '$($app.Type)'." }
    }
}

# Get the process ID of the cmd process running the app - helper function for Stop-App
function Get-CmdProcessId {
    param (
        [int]$port
    )

    $cmdProcesses = Get-Process -Name cmd -ErrorAction SilentlyContinue
    foreach ($process in $cmdProcesses) {
        $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)").CommandLine
        if ($commandLine -match "streamlit run .* --server.port $port" -or
            $commandLine -match "python .*manage.py runserver .*:$port" -or
            $commandLine -match "flask run --port $port") {
                Write-Host "Found process $($process.Id) with command line: $commandLine"
                return $process.Id
        }
    }
    Write-Host "No process found using port $port."
    return $null
}

# Helper for stopping Dash app
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class User32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@

function Get-CmdWindowHandle {
    param (
        [int]$processId
    )
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        Write-Host "Process with PID $processId not found."
        return $null
    }
    $mainWindowHandle = $process.MainWindowHandle
    if ($mainWindowHandle -eq [IntPtr]::Zero) {
        Write-Host "Main window handle not found for process with PID $processId."
        return $null
    }
    return $mainWindowHandle
}

function Show-CmdWindow {
    param (
        [int]$processId
    )
    $hWnd = Get-CmdWindowHandle -processId $processId
    if ($null -ne $hWnd) {
        [User32]::ShowWindowAsync($hWnd, 1) | Out-Null
        [User32]::SetForegroundWindow($hWnd) | Out-Null
        Write-Host "Brought command prompt window for PID $processId to the foreground. Please close it manually."
    }
}

# Stop an app
function Stop-App {
    param(
        [string]$appName
    )
    Write-Host "===== Stop App ====="
    $app = Get-AppByNameOrIndex -inputValue $appName
    if ($null -eq $app) {
        return
    }
    $appType = $app.Type
    $port = $app.Port
    $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($null -eq $connection) {
        Write-Host "No process is using port $port."
    } else {
        $processId = ($connection | Select-Object -First 1).OwningProcess
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $cmdPId = Get-CmdProcessId -port $port
        if (-not ($appType -eq 'Dash')) {
            if ($null -eq $process) {
                Write-Host "Process with PID $processId not found."
            } else {
                Write-Host "Stopping app '$appName' (PID: $processId) using port $port..."
                Stop-Process -Id $processId -Force
                Write-Host "App '$appName' stopped."

                if ($null -ne $cmdPId) {
                    Write-Host "Stopping cmd process with PID $cmdPId..."
                    Stop-Process -Id $cmdPId -Force
                    Write-Host "Cmd process stopped."
                } else {
                    Write-Host "No cmd process found for port $port."
                }
            }
        } else {
            if ($null -ne $cmdPId) {
                Show-CmdWindow -processId $cmdPId
            } else {
                Write-Host "No cmd process found for port $port."
            }
        }
    }
}

# Restart an app
function Restart-App {
    param(
        [string]$appName
    )

    Write-Host "===== Restart App ====="
    $app = Get-AppByNameOrIndex -inputValue $appName
    if ($null -eq $app) {
        return
    }

    Stop-App -appName $appName
    Start-App -appName $appName
}

# Update an app using 'git pull'
function Update-AppRepo {
    param(
        [string]$appName
    )
    Write-Host "===== Update App Repo ====="
    $app = Get-AppByNameOrIndex -inputValue $appName
    if ($null -eq $app) {
        return
    }

    $appPath = $app.AppPath
    if (-not (Test-Path $appPath)) {
        Write-Output "Path '$appPath' does not exist."
        return
    }

    Write-Output "Updating app '$appName' via 'git pull'..."
    Push-Location $appPath
    git pull
    Pop-Location
    Write-Output "App '$appName' updated successfully with 'git pull'."
}

function Update-Venv {
    param(
        [string]$appName
    )

    Write-Host "===== Update Virtual Environment ====="
    $app = Get-AppByNameOrIndex -inputValue $appName
    if ($null -eq $app) {
        return
    }

    $appPath = $app.AppPath
    $venvPath = $app.VenvPath
    $packageManager = if ($app.PackageManager) { $app.PackageManager } else { Get-PackageManager -ProjectDirectory $appPath }
    
    if ($packageManager -eq "uv") {
        Write-Output "Using uv to update dependencies from pyproject.toml..."
        Set-Location -Path $appPath
        uv sync
        Write-Output "Dependencies updated successfully with uv sync."
    } else {
        # Check if $app.appRequirements is set
        if ($app.appRequirements) {
            Write-Host "Using requirements file from app settings..."
            $requirementsFile = $app.appRequirements
            $requirementsFilePath = $requirementsFile
        } else { # Search for requirements.txt file in the project directory and its subdirectories
            $requirementsFile = Get-ChildItem -Path $appPath -Recurse -Filter "requirements.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
        }

        if ($null -eq $requirementsFile) {
            Write-Output "requirements.txt not found in '$appPath'."
            $addRequirementsResponse = Read-Host "Do you want to add the requirements file to the app settings? (y/n)"
            if ($addRequirementsResponse -ieq "yes" -or $addRequirementsResponse -ieq "y") {
                $requirementsFilePath = Read-Host "Enter the absolute path for the requirements file (e.g., 'C:\path\to\requirements.txt')"
                if (-not (Test-Path $requirementsFilePath)) {
                    Write-Output "Path '$requirementsFilePath' does not exist."
                    return
                }
                $app | Add-Member -MemberType NoteProperty -Name "appRequirements" -Value $requirementsFilePath
                Update-Json
                $requirementsFile = Get-Item -Path $requirementsFilePath
            } else {
                Write-Output "Operation cancelled."
                return
            }
        }

        $requirementsFilePath = $requirementsFile.FullName
        Write-Output "Activating virtual environment and installing dependencies from '$requirementsFilePath'..."
        & "$venvPath\Scripts\Activate.ps1"
        pip install -r $requirementsFilePath
        Write-Output "Deactivating virtual environment..."
        & "deactivate"
        Write-Output "Virtual environment updated and deactivated successfully."
    }
}

function Update-App {
    param(
        [string]$appName
    )

    Write-Host "===== Update App ====="
    $app = Get-AppByNameOrIndex -inputValue $appName
    if ($null -eq $app) {
        return
    }

    Update-AppRepo -appName $appName
    Update-Venv -appName $appName
    Restart-App -appName $appName
}

# Get the default app name from the app path
function Get-AppName {
    param (
        [string]$appPath
    )

    $appName = $appPath.Split("\")[-1]
    return $appName
}

# Function to check if a virtual environment exists in the specified directory
function Test-Venv {
    param(
        [string]$Directory
    )

    # Check if 'Scripts\activate.bat' exists in the specified directory
    $venvPath = Join-Path -Path $Directory -ChildPath "Scripts\activate.bat"
    return Test-Path $venvPath
}

# Function to search for virtual environments in the specified directory
function Search-Venv {
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

# Get the virtual environment directory containing 'Scripts/activate.bat' - helper function for Add-AppSetting and Update-AppSetting
function Get-VenvDirectory { 
    do { # Keep asking until a valid path is entered
        $venvPath = Read-Host "Enter the absoulte path for directory containing 'Scripts/activate.bat'"
        if (-not (Test-Venv -Directory $venvPath)) {
            Write-Host "The specified path '$venvPath' does not contain 'Scripts/activate.bat'. Please enter a valid path."
        }
    } while (-not (Test-Venv -Directory $venvPath))
    return $venvPath
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

# Function to get dependencies from pyproject.toml
function Get-PyProjectDependencies {
    param (
        [string]$ProjectDirectory
    )
    
    $pyprojectFile = Join-Path $ProjectDirectory "pyproject.toml"
    if (-not (Test-Path $pyprojectFile)) {
        return @()
    }
    
    try {
        $pyprojectContent = Get-Content $pyprojectFile -Raw
        # Simple parsing to extract dependencies - this is basic and may need improvement
        $dependencies = @()
        
        # Look for [project] section dependencies
        if ($pyprojectContent -match '\[project\][\s\S]*?dependencies\s*=\s*\[([\s\S]*?)\]') {
            $depsSection = $matches[1]
            # Extract quoted strings from the dependencies array
            $depsSection -split "`n" | ForEach-Object {
                $line = $_.Trim()
                if ($line -match '"([^"]+)"') {
                    $dependencies += $matches[1]
                }
            }
        }
        
        # Look for [dependency-groups] section dependencies
        # First, find the start of the dependency-groups section
        $depGroupsStart = $pyprojectContent.IndexOf('[dependency-groups]')
        if ($depGroupsStart -ge 0) {            
            # Find the end of the dependency-groups section (next [ or end of file)
            $remainingContent = $pyprojectContent.Substring($depGroupsStart)
            $nextSectionStart = $remainingContent.IndexOf("`n[", 1)
            if ($nextSectionStart -eq -1) {
                $depGroupsSection = $remainingContent
            } else {
                $depGroupsSection = $remainingContent.Substring(0, $nextSectionStart)
            }
            
            
            # Extract all dependency groups (e.g., dev, test, etc.)
            # Split by lines and process each group
            $lines = $depGroupsSection -split "`n"
            $inGroup = $false
            $currentGroup = ""
            $groupDependencies = @()
            
            foreach ($line in $lines) {
                $trimmedLine = $line.Trim()
                
                # Check if this line starts a new group (e.g., "dev = [")
                if ($trimmedLine -match '^(\w+)\s*=\s*\[') {
                    $inGroup = $true
                    $currentGroup = $matches[1]
                    continue
                }
                
                # If we're in a group and this line contains a dependency
                if ($inGroup -and $trimmedLine -match '"([^"]+)"') {
                    $groupDependencies += $matches[1]
                }
                
                # Check if this line ends the current group (closing bracket)
                if ($inGroup -and $trimmedLine -eq ']') {
                    $inGroup = $false
                    $currentGroup = ""
                }
            }
            
            # Add group dependencies to main dependencies
            $dependencies += $groupDependencies
        }
        
        # Look for [tool.poetry] section dependencies
        if ($pyprojectContent -match '\[tool\.poetry\][\s\S]*?\[tool\.poetry\.dependencies\][\s\S]*?python\s*=\s*"[^"]*"([\s\S]*?)(?=\[|$)') {
            $depsSection = $matches[1]
            $depsSection -split "`n" | ForEach-Object {
                $line = $_.Trim()
                if ($line -match '^([^=]+)\s*=') {
                    $dependencies += $matches[1].Trim()
                }
            }
        }
        
        return $dependencies
    } catch {
        Write-Warning "Failed to parse pyproject.toml: $($_.Exception.Message)"
        return @()
    }
}

# Function to determine the application type based on dependencies
function Get-AppType {
    param (
        [string]$ProjectDirectory
    )
    
    $packageManager = Get-PackageManager -ProjectDirectory $ProjectDirectory
    $packageNames = @()
    
    if ($packageManager -eq "uv") {
        # Get dependencies from pyproject.toml
        $packageNames = Get-PyProjectDependencies -ProjectDirectory $ProjectDirectory
    } else {
        # Get dependencies from requirements.txt
        $RequirementsContent = Get-RequirementsContent -ProjectDirectory $ProjectDirectory
        
        if ($RequirementsContent -ne "No requirements.txt found") {
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
        }
    }
    
    # Check for specific packages (handle version constraints)
    foreach ($package in $packageNames) {
        $packageName = $package.Split('>=')[0].Split('==')[0].Split('<=')[0].Split('~')[0].Split('!')[0].Split('>')[0].Split('<')[0].Trim()
        
        if ($packageName -eq "dash") {
            return "Dash"
        } elseif ($packageName -eq "flask") {
            return "Flask"
        } elseif ($packageName -eq "django") {
            return "Django"
        } elseif ($packageName -eq "streamlit") {
            return "Streamlit"
        }
    }
    
    return "Unknown Application Type"
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
    $allPyFiles = @(Get-ChildItem -Path $ProjectDirectory -Recurse -Filter *.py | Where-Object {
        $filePath = $_.FullName
        $isInVenv = $false
        foreach ($venvPath in $venvPaths) {
            if ($filePath -like "$venvPath*") {
                $isInVenv = $true
                break
            }
        }
        -not $isInVenv
    } | Select-Object -ExpandProperty FullName -Unique)
    
    return $allPyFiles
}

# Function to get the index of the Python file to be used as the main program
function Get-IndexPyFile {
    param (
        [string]$ProjectDirectory
    )
    
    $allPyFiles = Get-AllUniquePyFile -ProjectDirectory $ProjectDirectory

    if ($allPyFiles -isnot [array]) {
        $allPyFiles = @($allPyFiles)
    }
    
    for ($i = 0; $i -lt $allPyFiles.Length; $i++) {
        $relativePath = $allPyFiles[$i] -replace [regex]::Escape($ProjectDirectory), '~'
        $relativePath = $relativePath -replace '\\', '/'
        Write-Host "$($i+1): $relativePath"
    }
    $indexPage = [int](Read-Host "Enter the index of the index python file")
    $indexPage = $indexPage - 1
    $selectedPyFile = $allPyFiles[$indexPage]
    $selectedPyFile = $selectedPyFile.Substring($ProjectDirectory.Length + 1)
    return $selectedPyFile
}

# Get the port number for the app - helper function for Add-AppSetting and Update-AppSetting
function Get-PortNumber {
    $portResponse = Read-Host "Would you like to assign a random port for this app? (y/n)"
    if ($portResponse -ieq "yes" -or $portResponse -ieq "y") {
        do { # Keep generating a random port until an unused port is found
            $port = Get-Random -Minimum 3000 -Maximum 9000
            $portCheck = Test-NetConnection -ComputerName "localhost" -Port $port
        } while ($portCheck.TcpTestSucceeded -eq $true)
        return $port
    } else {
        do { # Keep asking until an unused port is entered
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
                if ($portCheck.TcpTestSucceeded -eq $true) {
                    Write-Host "Port $Port is already in use. Please enter a different port."
                }
            }
        } while ($portCheck.TcpTestSucceeded -eq $true)
        return $port
    }
}

# Check if a port is already assigned to an app in the global apps list
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

# Update the apps list in the JSON file - helper function for Add-AppSetting and Update-AppSetting
function Update-Json {
    $saveResponse = Read-Host ">>> Would you like to save the updated apps list to the JSON file? (y/n)"
    if ($saveResponse -ieq "yes" -or $saveResponse -ieq "y") {
        try {
            $global:apps | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFilePath -Encoding UTF8
                Write-Host "Apps list saved successfully to $jsonFilePath."
        } catch {
            Write-Host "Failed to save file: $($_.Exception.Message)"
        }
    }
}

# Add a new app
function Add-AppSetting {
    Write-Host "===== Add App Setting ====="
    $appPath = Read-Host ">>> Enter app path"
    $appName = Read-Host "Default app name: $(Get-AppName -appPath $appPath) (press Enter to keep the default value, or enter a new name)"
    if (-not($appName)) {
        $appName = Get-AppName -appPath $appPath
    }

    $appType = Get-AppType -ProjectDirectory $appPath
    if (-not($appType)) {
        $appType = Read-Host ">>> Enter app type, can be either Streamlit/Django/Flask (s/d/f)"
    }

    $packageManager = Get-PackageManager -ProjectDirectory $appPath
    Write-Host "Detected package manager: $packageManager"

    $venvDirectory = Search-Venv -ProjectDirectory $appPath
    if ($venvDirectory) {
        $venvPath = Join-Path -Path $appPath -ChildPath $venvDirectory
    } else {
        $venvPath = Get-VenvDirectory
    }
    
    if ($appType -ieq "streamlit" -or $appType -ieq "flask") {
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

    if (-not ($global:apps)) {
        $global:apps = @(@($newApp))
    } else {
        if ($global:apps -is [System.Management.Automation.PSCustomObject]) {
            $global:apps = @($global:apps | ForEach-Object { ConvertTo-Hashtable -Object $_ })
        }
        $global:apps += $newApp
    }

    Write-Output "App '$appName' added successfully."

    Update-Json
}

# Update an existing app
function Update-AppSetting {
    param(
        [string]$appName
    )
    Write-Host "===== Update App Setting ====="
    $app = Get-AppByNameOrIndex -inputValue $appName
    if ($null -eq $app) {
        return
    }

    # Convert $app to a hashtable to allow property modifications
    $app = ConvertTo-Hashtable -Object $app

    $updateApp = $false
    Write-Output "Updating app '$appName'..."
    Write-Output "Update the app settings (press Enter to keep the existing value):"

    Write-Host "Current app name: $($app.Name)"
    $newAppName = Read-Host ">>> Enter app name (press Enter to keep the existing value)"
    if ($newAppName -and $newAppName -cne $app.Name) {
        $app.Name = $newAppName
        $updateApp = $true
    }

    # Check and update app type
    $detectedAppType = Get-AppType -ProjectDirectory $app.AppPath
    Write-Host "Current app type: $($app.Type)"
    Write-Host "Detected app type: $detectedAppType"
    
    if ($detectedAppType -ne $app.Type -and $detectedAppType -ne "Unknown Application Type") {
        $updateAppType = Read-Host ">>> App type changed from '$($app.Type)' to '$detectedAppType'. Update? (y/n)"
        if ($updateAppType -ieq "yes" -or $updateAppType -ieq "y") {
            $app.Type = $detectedAppType
            $updateApp = $true
        }
    } else {
        Write-Host ">>> App type is already correct: $($app.Type)"
    }
    
    $newAppType = Read-Host ">>> Or manually enter app type, can be either Streamlit/Django/Flask (s/d/f) (press Enter to keep the current value)"
    if ($newAppType -and $newAppType -ne $app.Type) {
        $newAppType = $newAppType.Substring(0, 1).ToUpper() + $newAppType.Substring(1).ToLower()
        $app.Type = $newAppType
        $updateApp = $true
    }

    # Check and update package manager
    $currentPackageManager = if ($app.PackageManager) { $app.PackageManager } else { "Not set" }
    $detectedPackageManager = Get-PackageManager -ProjectDirectory $app.AppPath
    Write-Host "Current package manager: $currentPackageManager"
    Write-Host "Detected package manager: $detectedPackageManager"
    
    if (-not $app.PackageManager) {
        Write-Host ">>> Package manager field is missing. Setting to detected value: $detectedPackageManager"
        $app.PackageManager = $detectedPackageManager
        $updateApp = $true
    } elseif ($detectedPackageManager -ne $app.PackageManager) {
        $updatePackageManager = Read-Host ">>> Package manager changed from $($app.PackageManager) to $detectedPackageManager. Update? (y/n)"
        if ($updatePackageManager -ieq "yes" -or $updatePackageManager -ieq "y") {
            $app.PackageManager = $detectedPackageManager
            $updateApp = $true
        }
    } else {
        Write-Host ">>> Package manager is already correct: $detectedPackageManager"
    }

    Write-Host "Current app path: $($app.AppPath)"
    $newAppPath = Read-Host ">>> Enter app path (press Enter to keep the existing value)"
    if ($newAppPath -and $newAppPath -ne $app.AppPath) {
        $app.AppPath = $newAppPath
        $updateApp = $true
    }

    if ($app.Type -ieq "streamlit" -or $app.Type -ieq "flask") {
        Write-Host "Current index path: $($app.IndexPath)"
        $newIndexPath = Read-Host ">>> Enter index path (main script for the app) (press Enter to keep the existing value)"
        if ($newIndexPath -and $newIndexPath -ne $app.IndexPath) {
            $app.IndexPath = $newIndexPath
            $updateApp = $true
        }
    } elseif ($app.Type -ieq "django") {
        if ($app.IndexPath) {
            $app.PSObject.Properties.Remove("IndexPath")
            $updateApp = $true
        }
    }

    Write-Host "Current virtual environment path: $($app.VenvPath)"
    $venvPathResponse = Read-Host ">>> Would you like to update the virtual environment path? (y/n)"
    if ($venvPathResponse -ieq "yes" -or $venvPathResponse -ieq "y") {
        $newVenvPath = Get-VenvDirectory -appPath $app.AppPath
        if ($newVenvPath -and $newVenvPath -ne $app.VenvPath) {
            $app.VenvPath = $newVenvPath
            $updateApp = $true
        }
    }
    
    Write-Host "Current port number: $($app.Port)"
    $portResponse = Read-Host ">>> Would you like to update the port number? (y/n)"
    if ($portResponse -ieq "yes" -or $portResponse -ieq "y") {
        $newPortNum = Get-PortNumber
        if ($newPortNum -and $newPortNum -ne $app.Port) {
            $app.Port = $newPortNum
            $updateApp = $true
        }
    }

    if ($updateApp) {
        # Update the app in the global apps array
        $appIndex = -1
        for ($i = 0; $i -lt $global:apps.Count; $i++) {
            if ($global:apps[$i].Name -ieq $appName) {
                $appIndex = $i
                break
            }
        }
        
        if ($appIndex -ge 0) {
            $global:apps[$appIndex] = $app
        }
        
        Write-Output "App '$appName' updated successfully."
        Update-Json
    } else {
        Write-Output "No changes made to app '$appName'."
    }
}

# Remove an app
function Remove-AppSetting {
    param(
        [string]$appName
    )

    $app = Get-AppByNameOrIndex -inputValue $appName -appList $global:apps
    if ($null -eq $app) {
        Write-Output "App '$appName' not found."
        continue
    } else {
        $global:apps = $global:apps | Where-Object { $_.Name -ine $app.Name } # Case-insensitive comparison
        Write-Output "App '$($app.Name)' removed successfully."
        Update-Json
    }
}

# Close all idle cmd windows
function Close-IdleCmdWindows {
    Write-Host "===== Stopping Idle cmd.exe Processes ====="

    # Get all cmd.exe processes
    $cmdProcesses = Get-Process cmd -ErrorAction SilentlyContinue

    if ($null -eq $cmdProcesses) {
        Write-Host "No cmd.exe processes found."
        return
    }

    foreach ($process in $cmdProcesses) {
        try {
            # Get the command line of the process and trim it
            $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)").CommandLine.Trim()

            # Check if the command line matches idle or minimal criteria
            if ([string]::IsNullOrWhiteSpace($commandLine) -or 
                $commandLine -ieq 'cmd.exe' -or 
                $commandLine -ieq '"C:\windows\system32\cmd.exe"') {
                Write-Host "Stopping idle cmd.exe process with PID $($process.Id). CommandLine: '$commandLine'"
                Stop-Process -Id $process.Id -Force
            } else {
                Write-Host "Skipping active cmd.exe process with PID $($process.Id). CommandLine: '$commandLine'"
            }
        } catch {
            Write-Warning "Failed to process cmd.exe with PID $($process.Id): $_"
        }
    }

    Write-Host "===== Done ====="
}

# Pull the app cmd window to the foreground
function Pull-CmdWindowToForeground {
    param(
        [string]$appName
    )
    Write-Host "===== Pulling App Command Window ====="
    $app = Get-AppByNameOrIndex -inputValue $appName
    if ($null -eq $app) {
        return
    }

    $port = $app.Port
    $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue

    if ($null -eq $connection) {
        Write-Output "App '$appName' is not running."
        return
    }
    
    $processId = ($connection | Select-Object -First 1).OwningProcess
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    $cmdPId = Get-CmdProcessId -port $port

    if ($null -ne $cmdPId) {
        Show-CmdWindow -processId $cmdPId
    } else {
        Write-Host "No cmd process found for app port $port."
    }
}

function Show-Menu {
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
    Write-Output "0. Close all idle cmd windows"
    Write-Output "=============================="
}

function Main {
    while ($true) {
        Show-Menu
        $option = Read-Host "Enter option"
        switch ($option) {
            1 {
                $confirmation = Read-Host "Are you sure you want to start all apps? (yes to confirm)"
                if ($confirmation -ieq "yes") {
                    $apps | ForEach-Object { Start-App -appName $_.Name -appType $_.Type }
                } else {
                    Write-Output "Operation cancelled."
                }
            }
            2 {
                $appList = Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name or index to restart (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                $app = Get-AppByNameOrIndex -inputValue $appName -appList $appList
                if ($null -ne $app) {
                    Restart-App -appName $app.Name
                }
            }
            3 {
                $appList = Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name or index to start (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                $app = Get-AppByNameOrIndex -inputValue $appName -appList $appList
                if ($null -ne $app) {
                    Start-App -appName $app.Name
                }
            }
            4 {
                $appList = Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name or index to stop (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                $app = Get-AppByNameOrIndex -inputValue $appName -appList $appList
                if ($null -ne $app) {
                    Stop-App -appName $app.Name
                }
            }
            5 {
                $appList = Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name or index to update (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                $app = Get-AppByNameOrIndex -inputValue $appName -appList $appList
                if ($null -ne $app) {
                    Update-App -appName $app.Name
                }
            }
            6 {
                Add-AppSetting
            }
            7 {
                $appList = Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name or index to update settings (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                $app = Get-AppByNameOrIndex -inputValue $appName -appList $appList
                if ($null -ne $app) {
                    Update-AppSetting -appName $app.Name
                }
            }
            8 {
                $appList = Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name or index to remove (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                $app = Get-AppByNameOrIndex -inputValue $appName -appList $appList
                if ($null -ne $app) {
                    Remove-AppSetting -appName $app.Name
                }
            }
            9 {
                Update-Json
            }
            0 {
                Close-IdleCmdWindows
            }
            default {
                Write-Output "Invalid option. Please try again."
            }
        }
    }
}

Main
