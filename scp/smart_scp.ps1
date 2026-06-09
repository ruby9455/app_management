function Invoke-SmartSCP {
    param (
        [Parameter(Mandatory=$true)] [string]$Project,
        [Parameter(Mandatory=$true)] [string]$HostName,  # e.g., p5
        [Parameter(Mandatory=$true)] [string]$FileRelativePath, # e.g., data/file.csv
        [ValidateSet("Upload", "Download")] [string]$Direction = "Upload"
    )

    $configPath = "C:\Users\rchan09\code\app_management\scp\scp_config.json"
    $config = Get-Content $configPath | ConvertFrom-Json
    
    # Get current machine name (SAH0267888)
    $localHost = $env:COMPUTERNAME
    
    $localBase = $config.$Project.$localHost
    $remoteBase = $config.$Project.$HostName

    if (-not $localBase -or -not $remoteBase) {
        Write-Error "Project or Host not found in config."
        return
    }

    $localPath = Join-Path $localBase $FileRelativePath
    $remotePath = "shcc@$($HostName):$remoteBase/$FileRelativePath"

    if ($Direction -eq "Upload") {
        Write-Host "🚀 Uploading to $HostName..." -ForegroundColor Cyan
        scp $localPath $remotePath
    } else {
        Write-Host "Wait... 📥 Downloading from $HostName..." -ForegroundColor Yellow
        scp $remotePath $localPath
    }
}

# Create an alias for speed
Set-Alias sscp Invoke-SmartSCP