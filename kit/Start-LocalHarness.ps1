[CmdletBinding()]
param([ValidateSet('web','headless','sdk','acp')][string]$Profile='web',[string]$Task,[string[]]$ProfileArguments=@())
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(!$identity.Name.EndsWith('\DSHAudit',[StringComparison]::OrdinalIgnoreCase) -or ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use the ordinary DSHAudit user'}
$env:PATH='C:\Program Files\nodejs;'+$env:PATH
$env:POWERSHELL_TELEMETRY_OPTOUT='1'
& 'C:\DSH\kit\Start-LocalModel.ps1'
& 'C:\DSH\kit\Run-Harness.ps1' -Profile $Profile -Task $Task -ProfileArguments $ProfileArguments
