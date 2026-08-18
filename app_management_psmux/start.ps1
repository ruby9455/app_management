[CmdletBinding()]
param([Parameter(Position=0)][string]$Command = 'manager')

$manager = Join-Path $PSScriptRoot 'manager.ps1'
$landing = Join-Path $PSScriptRoot 'landing_page.ps1'
switch ($Command.ToLowerInvariant()) {
    'all'     { & $manager -All }
    'attach'  { & $manager -Attach }
    'stop'    { Import-Module (Join-Path $PSScriptRoot 'Modules\PsmuxHelpers.psm1') -Force; Stop-AllPsmuxWindows }
    'list'    { Import-Module (Join-Path $PSScriptRoot 'Modules\PsmuxHelpers.psm1') -Force; Show-PsmuxWindows }
    'manager' { & $manager }
    'landing' { & $landing }
    'help'    { & $manager -Help }
    default   { & $manager -AppName $Command }
}
