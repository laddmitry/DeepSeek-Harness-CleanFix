[CmdletBinding()]
param([switch]$NoLaunch)
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(!$identity.Name.EndsWith('\DSHAudit',[StringComparison]::OrdinalIgnoreCase) -or ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Sign in as the ordinary DSHAudit user'}
$env:PATH='C:\Program Files\nodejs;'+$env:PATH
& ($env:WINDIR+'\System32\WindowsPowerShell\v1.0\powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File 'C:\DSH\kit\Configure-Keyboard.ps1'
if($LASTEXITCODE -ne 0){throw 'Keyboard configuration failed'}
& 'C:\DSH\kit\Freeze-WindowsPermissions.ps1' -Verify
$desktop=[Environment]::GetFolderPath('Desktop');New-Item -ItemType Directory -Path $desktop -Force|Out-Null
$shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Harness-Local.lnk'))
$shortcut.TargetPath='C:\DSH\tools\PowerShell7\pwsh.exe'
$shortcut.Arguments='-NoLogo -NoProfile -NoExit -ExecutionPolicy RemoteSigned -File "C:\DSH\kit\Start-LocalHarness.ps1"'
$shortcut.WorkingDirectory='C:\DSH\workspace';$shortcut.Description='Local Ollama and Harness Web with token authentication';$shortcut.Save()
@{ordinaryUser=$true;keyboardConfigured=$true;aclVerified=$true;shortcut='Harness-Local.lnk'}|ConvertTo-Json|Set-Content -LiteralPath 'C:\DSH\logs\user-setup.json' -Encoding utf8
if(!$NoLaunch){& 'C:\DSH\kit\Start-LocalHarness.ps1'}
