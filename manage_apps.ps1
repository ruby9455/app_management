# Load the apps list from JSON file if it exists, otherwise create an empty list
$jsonFilePath = "$PSScriptRoot\apps_test.json"

if (Test-Path $jsonFilePath) {
    if ((Get-Item $jsonFilePath).Length -eq 0) {
        $global:apps = @()
    } else {
        $global:apps = Get-Content $jsonFilePath | ConvertFrom-Json
        $global:apps = $global:apps | Where-Object { $_.Name -notmatch "deprecated" }
    }    
} else {
    $global:apps = @()
}

# Functions
# Show all apps
function Show-Apps {
    Write-Host "===== All available apps ====="
    $apps | Sort-Object Name | ForEach-Object { Write-Output $_.Name }
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

    Enable-Venv -venvPath $venvPath
    Set-Location -Path $appPath
    Write-Output "Starting Streamlit app '$($app.Name)' on port $appPort..."
    # Start-Process "streamlit" -ArgumentList "run", $appIndexPath, "--server.port", $appPort
    Start-Process "cmd.exe" -ArgumentList "/k", "streamlit run $appIndexPath --server.port $appPort" -WorkingDirectory $appPath
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

    Enable-Venv -venvPath $venvPath
    Set-Location -Path $appPath
    Write-Output "Starting Django app '$($app.Name)' on port $appPort..."
    # Start-Process "python" -ArgumentList ".\manage.py", "runserver", "0.0.0.0:$appPort" -WorkingDirectory $appPath
    Start-Process "cmd.exe" -ArgumentList "/k", "python .\manage.py runserver 0.0.0.0:$appPort" -WorkingDirectory $appPath
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

    Enable-Venv -venvPath $venvPath
    Set-Location -Path $appPath
    $env:FLASK_APP = $appIndexPath
    $env:FLASK_ENV = "development"
    Write-Output "Starting Flask app '$($app.Name)' on port $appPort..."
    # Start-Process "python" -ArgumentList ".\app.py" -WorkingDirectory $appPath
    Start-Process "cmd.exe" -ArgumentList "/k", "flask run --host=0.0.0.0 --port $appPort" -WorkingDirectory $appPath
}

# Start an app
function Start-App {
    param (
        [string]$appName
    )
    Write-Host "===== Start App ====="
    $app = $apps | Where-Object { $_.Name -ieq $appName } # Case-insensitive comparison
    if ($null -eq $app) {
        Write-Output "App '$appName' not found."
        return
    }
    
    switch ($app.Type) {
        "Streamlit" { Start-StreamlitApp -app $app }  # Pass $app object
        "Django" { Start-DjangoApp -app $app }  # Pass $app object
        "Flask" { Start-FlaskApp -app $app }  # Pass $app object
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
            $commandLine -match "python manage.py runserver .*:$port" -or
            $commandLine -match "flask run --port $port") {
                Write-Host "Found process $($process.Id) with command line: $commandLine"
                return $process.Id
        }
    }
    Write-Host "No process found using port $port."
    return $null
}

# Stop an app
function Stop-App {
    param(
        [string]$appName
    )
    Write-Host "===== Stop App ====="
    $app = $apps | Where-Object { $_.Name -ieq $appName } # Case-insensitive comparison
    if ($null -eq $app) {
        Write-Output "App '$appName' not found."
        return
    }

    $port = $app.Port
    $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($null -eq $connection) {
        Write-Host "No process is using port $port."
    } else {
        $processId = ($connection | Select-Object -First 1).OwningProcess
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $cmdPId = Get-CmdProcessId -port $port

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
    $app = $apps | Where-Object { $_.Name -ieq $appName } # Case-insensitive comparison
    if ($null -eq $app) {
        Write-Output "App '$appName' not found."
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
    $app = $apps | Where-Object { $_.Name -ieq $appName } # Case-insensitive comparison
    if ($null -eq $app) {
        Write-Output "App '$appName' not found."
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

function Update-App {
    param(
        [string]$appName
    )
    Write-Host "===== Update App ====="
    $app = $apps | Where-Object { $_.Name -ieq $appName } # Case-insensitive comparison
    if ($null -eq $app) {
        Write-Output "App '$appName' not found."
        return
    }

    Update-AppRepo -appName $appName
    Restart-App -appName $appName
}

# Get the virtual environment directory containing 'Scripts/activate.bat' - helper function for Add-AppSetting and Update-AppSetting
function Get-VenvDirectory { 
    Param (
        [string]$appPath
    )
    $venvResponse = Read-Host "Is the virtual environment '*venv*' in the app directory? (y/n)"
    if ($venvResponse -ieq 'yes' -or $venvResponse -ieq 'y') {
        $venvDirectories = Get-ChildItem -Path $appPath -Recurse -Directory -Filter "*venv*"
        if ($venvDirectories.Count -eq 0) { # No 'venv' directory found
            Write-Output "No 'venv' directory found in the app directory."
            do { # Keep asking until a valid path is entered
                $venvPath = Read-Host "Enter the virtual environment path containing 'Scripts/activate.bat'"
                if (-not (Test-Path (Join-Path $venvPath "Scripts/activate.bat"))) {
                    Write-Host "The specified virtual environment path '$venvPath' does not contain 'Scripts/activate.bat'. Please enter a valid path."
                }
            } while (-not (Test-Path (Join-Path $venvPath "Scripts/activate.bat")))
            return $venvPath
        } else { # 'venv' directory found
            # Filter directories containing Scripts/activate.bat
            $venvDirectories = $venvDirectories | Where-Object { Test-Path (Join-Path $_.FullName "Scripts/activate.bat") }
            if ($venvDirectories.Count -eq 0) { # No valid 'venv' directory found
                Write-Output "No 'venv' directory containing 'Scripts/activate.bat' found in the app directory."
                do { # Keep asking until a valid path is entered
                    $venvPath = Read-Host "Enter the virtual environment path"
                    if (-not (Test-Path (Join-Path $venvPath "Scripts/activate.bat"))) {
                        Write-Host "The specified virtual environment path '$venvPath' does not contain 'Scripts/activate.bat'. Please enter a valid path."
                    }
                } while (-not (Test-Path (Join-Path $venvPath "Scripts/activate.bat")))
            } else { # Valid 'venv' directory found
                # if only one valid 'venv' directory is found, return it
                if ($venvDirectories.Count -eq 1) {
                    return $venvDirectories[0].FullName
                }
                # if multiple valid 'venv' directories are found, ask the user to select one
                Write-Output "Multiple 'venv' directories containing 'Scripts/activate.bat' found in the app directory."
                Write-Output "Select the virtual environment directory:"
                for ($i = 0; $i -lt $venvDirectories.Count; $i++) {
                    Write-Host "${i}: $($venvDirectories[$i].FullName)"
                }

                do {
                    $selectedIndex = Read-Host "Enter the number of the directory you want to select"
            
                    # Validate the input and get the selected directory
                    if ($selectedIndex -match '^\d+$' -and $selectedIndex -ge 0 -and $selectedIndex -lt $venvDirectories.Count) {
                        $selectedDirectory = $venvDirectories[$selectedIndex]
                        Write-Output "You selected: $($selectedDirectory.FullName)"
                        return $selectedDirectory.FullName
                    } else {
                        Write-Output "Invalid selection. Please enter a valid index number."
                    }
                } while ($true)
            }
        }
    } else {
        do { # Keep asking until a valid path is entered
            $venvPath = Read-Host "Enter the virtual environment path"
            if (-not (Test-Path (Join-Path $venvPath "Scripts/activate.bat"))) {
                Write-Host "The specified virtual environment path '$venvPath' does not contain 'Scripts/activate.bat'. Please enter a valid path."
            }
        } while (-not (Test-Path (Join-Path $venvPath "Scripts/activate.bat")))
        return $venvPath
    }
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

# Update the apps list in the JSON file - helper function for Add-AppSetting and Update-AppSetting
function Update-Json {
    try {
        $global:apps | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFilePath -Encoding UTF8
            Write-Host "Apps list saved successfully to $jsonFilePath."
    } catch {
        Write-Host "Failed to save file: $($_.Exception.Message)"
    }
}

# Add a new app
function Add-AppSetting {
    Write-Host "===== Add App Setting ====="
    $appName = Read-Host ">>> Enter app name"
    $appType = Read-Host ">>> Enter app type, can be either Streamlit/Django/Flask (s/d/f)"
    if ($appType) {
        $appType = $appType.Substring(0, 1).ToUpper() + $appType.Substring(1).ToLower()
    }
    $appPath = Read-Host "Enter app path"
    # if the appType is either Streamlit or Flask
    if ($appType -ieq "streamlit" -or $appType -ieq "flask") {
        $indexPath = Read-Host ">>> Enter index path (main script for the app)"
    }
    $venvPath = Get-VenvDirectory -appPath $appPath
    $portNum = Get-PortNumber

    $newApp = [PSCustomObject]@{
        Name = $appName
        Type = $appType
        VenvPath = $venvPath
        AppPath = $appPath
        IndexPath = $indexPath
        Port = $portNum
    }

    if (-not ($global:apps)) {
        Write-Host "Apps is empty"
        $global:apps = @(@($newApp))
    } else {
        Write-Host "Apps is not empty"
        if ($global:apps -is [PSCustomObject]) {
            Write-Output "global:apps is a PSCustomObject"
            $global:apps = @(@($global:apps))
        }
        $global:apps += $newApp
    }

    Write-Output "App '$appName' added successfully."

    $saveResponse = Read-Host ">>> Would you like to save the updated apps list to the JSON file? (y/n)"
    if ($saveResponse -ieq "yes" -or $saveResponse -ieq "y") {
        Update-Json
    }
}

# Update an existing app
function Update-AppSetting {
    param(
        [string]$appName
    )
    Write-Host "===== Update App Setting ====="
    $app = $apps | Where-Object { $_.Name -ieq $appName } # Case-insensitive comparison
    if ($null -eq $app) {
        Write-Output "App '$appName' not found."
        return
    }

    $updateApp = $false
    Write-Output "Updating app '$appName'..."
    Write-Output "Update the app settings (press Enter to keep the existing value):"

    Write-Host "Current app name: $($app.Name)"
    $newAppName = Read-Host ">>> Enter app name (press Enter to keep the existing value)"
    if ($newAppName -and $newAppName -cne $app.Name) {
        $app.Name = $newAppName
        $updateApp = $true
    }

    Write-Host "Current app type: $($app.Type)"
    $newAppType = Read-Host ">>> Enter app type, can be either Streamlit/Django/Flask (s/d/f) (press Enter to keep the existing value)"
    if ($newAppType -and $newAppType -ne $app.Type) {
        $newAppType = $newAppType.Substring(0, 1).ToUpper() + $newAppType.Substring(1).ToLower()
        $app.Type = $newAppType
        $updateApp = $true
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
        Write-Output "App '$appName' updated successfully."
        $saveResponse = Read-Host ">>> Would you like to save the updated apps list to the JSON file? (y/n)"
        if ($saveResponse -ieq "yes" -or $saveResponse -ieq "y") {
            Update-Json
        }
    } else {
        Write-Output "No changes made to app '$appName'."
    }
}

function Show-Menu {
    Write-Output "=============================="
    Write-Output "Select an option:"
    Write-Output "1. List all apps"
    Write-Output "2. Start all apps"
    Write-Output "3. Restart an app"
    Write-Output "4. Start an app"
    Write-Output "5. Stop an app"
    Write-Output "6. Git pull an app"
    Write-Output "7. Add a new app"
    Write-Output "8. Update an app setting"
    Write-Output "0. Exit"
    Write-Output "=============================="
}

function Main {
    while ($true) {
        Show-Menu
        $option = Read-Host "Enter option"
        switch ($option) {
            1 {
                Show-Apps
            }
            2 {
                $confirmation = Read-Host "Are you sure you want to start all apps? (yes to confirm)"
                if ($confirmation -ieq "yes") {
                    $apps | ForEach-Object { Start-App -appName $_.Name -appType $_.Type }
                } else {
                    Write-Output "Operation cancelled."
                }
            }
            3 {
                Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name to restart (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Restart-App -appName $appName
            }
            4 {
                Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name to start (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Start-App -appName $appName
            }
            5 {
                Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name to stop (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Stop-App -appName $appName
            }
            6 {
                Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name to perform 'git pull' (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Update-AppRepo -appName $appName
            }
            7 {
                Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name to add (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Update-App -appName $appName
            }
            8 {
                Add-AppSetting
            }
            9 {
                Show-Apps
                Write-Host "===================="
                $appName = Read-Host "Enter app name to restart (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Update-AppSetting -appName $appName
            }
            0 {
                Write-Output "Exiting..."
                exit
            }
            default {
                Write-Output "Invalid option. Please try again."
            }
        }
    }
}

Main
