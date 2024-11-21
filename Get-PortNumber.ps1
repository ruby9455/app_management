function Get-PortNumber {
    $portResponse = Read-Host "Would you like to assign a random port for this app? (Yes/No)"
    if ($portResponse -ieq "yes") {
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
$port = Get-PortNumber
Write-Host "Selected port: $port"
