$global:apps = @()

$newApp1 = [hashtable]@{
    Name = "YSS"
    Type = "Streamlit"
    VenvPath = "C:\Users\user_name\code\preoject2\venv"
    AppPath = "C:\Users\user_name\code\preoject2"
    IndexPath = "app\preoject2_app.py"
    Port = 6989
}

if (-not ($global:apps)) {
    Write-Host "Apps is empty"
    $global:apps = @(@($newApp1))
} else {
    Write-Host "Apps is not empty"
    $global:apps += $newApp1
}

Write-Output "App '$($newApp1.Name)' added successfully."

$jsonApps = $global:apps | ConvertTo-Json -Depth 3
Write-Output "Original apps in JSON format: $jsonApps"
Write-Output "Original apps: $($global:apps)"
Write-Output "Length of apps: $($global:apps.Length)"
Write-Output "Count of apps: $($global:apps.Count)"

# Read the JSON string back into global:apps
$global:apps = $jsonApps | ConvertFrom-Json

# Ensure that $global:apps is an array after reading back from JSON
if ($global:apps -isnot [array]) {
    $global:apps = @($global:apps)
}

Write-Output "Apps read back from JSON:"
Write-Output $global:apps
Write-Output "Type of global:apps: $($global:apps.GetType().FullName)"

if ($global:apps -is [hashtable]) {
    Write-Output "global:apps is a hashtable"
    $global:apps = @(@($global:apps))
}
Write-Output "Apps after conversion: $($global:apps)"

$newApp2 = [hashtable]@{
    Name = "LOS"
    Type = "Streamlit"
    VenvPath = "C:\Users\user_name\code\project1\venv"
    AppPath = "C:\Users\user_name\code\project1"
    IndexPath = "app\app.py"
    Port = 8937
}

$global:apps += $newApp2

Write-Output $global:apps
$jsonApps = $global:apps | ConvertTo-Json -Depth 3
Write-Output "Original apps in JSON format: $jsonApps"