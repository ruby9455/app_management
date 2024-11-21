function Get-VenvDirectory { 
    Param (
        [string]$appPath
    )
    $venvResponse = Read-Host "Is the virtual environment '*venv*' in the app directory? (Yes/No)"
    if ($venvResponse -ieq 'yes') {
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
$venvPath = Get-VenvDirectory -appPath "C:\Users\rchan09\code\yss"
Write-Output "The virtual environment path is: $venvPath"
