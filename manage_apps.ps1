# Load the apps list from JSON file if it exists, otherwise create an empty list
$jsonFilePath = "$PSScriptRoot\apps.json"

if (Test-Path $jsonFilePath) {
    $global:apps = Get-Content -Path $jsonFilePath | ConvertFrom-Json
} else {
    $global:apps = @()
}

# Functions
# Show all apps
function Show-Apps {
    $apps | ForEach-Object { Write-Output $_.Name }
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

    $app = $apps | Where-Object { $_.Name -ieq $appName } # Case-insensitive comparison
    if ($null -eq $app) {
        Write-Output "App '$appName' not found."
        return
    }

    Stop-App -appName $appName
    Start-App -appName $appName
}

# Update an app using 'git pull'
function Update-App {
    param(
        [string]$appName
    )

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

# Add a new app
function Add-App {
    $appName = Read-Host "Enter app name"
    $appType = Read-Host "Enter app type (Streamlit/Django/Flask)"
    $appPath = Read-Host "Enter app path"
    $indexPath = Read-Host "Enter index path (main script for the app)"

    # Search for virtual environment directory
    $venvResponse = Read-Host "Is virtual environment directory named 'venv'? (Yes/No)"
    if ($venvResponse -ieq "yes") {
        $venvDirectories = Get-ChildItem -Path $appPath -Recurse -Directory -Filter "venv"
        if ($venvDirectories) {
            $venvPath = Join-Path $appPath $venvDirectories[0].FullName
        } else {
            Write-Host "No 'venv' directory found in '$appPath'. Please specify the virtual environment path."
            $venvPath = Read-Host "Enter the virtual environment path"
        }
    } else {
        $venvResponse = Read-Host "Enter the name of the virtual environment directory"
        $venvDirectories = Get-ChildItem -Path $appPath -Recurse -Directory -Filter $venvResponse
        if ($venvDirectories) {
            $venvPath = Join-Path $appPath $venvDirectories[0].FullName
        } else {
            Write-Host "No '$venvResponse' directory found in '$appPath'. Please specify the virtual environment path."
            $venvPath = Read-Host "Enter virtual environment path"
        }
    }
    
    # Set the port number
    $portResponse = Read-Host "Would you like to assign a random port for this app? (Yes/No)"
    if ($portResponse -ieq "yes") {
        do {
            $port = Get-Random -Minimum 3000 -Maximum 9000
            $portCheck = Test-NetConnection -ComputerName "localhost" -Port $port
        } while ($portCheck.TcpTestSucceeded -eq $true)
    } else {
        do {
            $port = [int](Read-Host "Enter a specific port number")
            $portCheck = Test-NetConnection -ComputerName "localhost" -Port $Port
            if ($portCheck.TcpTestSucceeded -eq $true) {
                Write-Host "Port $Port is already in use. Please enter a different port."
            }
        } while ($portCheck.TcpTestSucceeded -eq $true)
    }

    $newApp = @{
        Name = $appName
        Type = $appType
        VenvPath = $venvPath
        AppPath = $appPath
        IndexPath = $indexPath
        Port = $port
    }

    $global:apps += $newApp
    Write-Output "App '$appName' added successfully."

    # Ask if the user wants to save the updated ps1 file
    $currentFilePath = $MyInvocation.MyCommand.Path
    $saveResponse = Read-Host "Would you like to save the updated apps list to the JSON file? (Yes/No)"
    if ($saveResponse -ieq "yes") {
        try {
            $global:apps | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFilePath -Encoding UTF8
            Write-Host "Apps list saved successfully to $jsonFilePath."
        } catch {
            Write-Host "Failed to save file: $($_.Exception.Message)"
        }
    }
}

# Show the menu
function Show-Menu {
    Write-Output "Select an option:"
    Write-Output "1. List all apps"
    Write-Output "2. Start all apps"
    Write-Output "3. Restart an app"
    Write-Output "4. Start an app"
    Write-Output "5. Stop an app"
    Write-Output "6. Git pull an app"
    Write-Output "7. Add a new app"
    Write-Output "0. Exit"
}

# Main function
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
                $appName = Read-Host "Enter app name to restart (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Restart-App -appName $appName
            }
            4 {
                Show-Apps
                $appName = Read-Host "Enter app name to start (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Start-App -appName $appName
            }
            5 {
                Show-Apps
                $appName = Read-Host "Enter app name to stop (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Stop-App -appName $appName
            }
            6 {
                Show-Apps
                $appName = Read-Host "Enter app name to perform 'git pull' (or 'back' to go back to menu)"
                if ($appName -ieq "back") {
                    continue
                }
                Update-App -appName $appName
            }
            7{
                Add-App
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