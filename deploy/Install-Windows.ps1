[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepositoryRoot,[SecureString]$ControllerPassword,[string]$ControllerPasswordFile)
$ErrorActionPreference='Stop'
$env:POWERSHELL_TELEMETRY_OPTOUT='1'
if($PSVersionTable.PSVersion.Major -lt 7 -or !$IsWindows){throw 'Bundled PowerShell 7 on Windows is required'}
if(!([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Elevated administrator required'}
$root='C:\DSH';$source=Join-Path $root 'source\deepseek-harness-master'
foreach($name in @('DSHAudit','DSHAgent')){if(Get-LocalUser -Name $name -ErrorAction SilentlyContinue){throw "Local account already exists: $name"}}
if(@(Get-ChildItem -LiteralPath $root -Force|Where-Object Name -ne 'tools').Count){throw 'Installation has progressed beyond preparation; refusing to overwrite'}
. (Join-Path $PSScriptRoot 'Read-Payload.ps1')
if($ControllerPasswordFile){
    if($ControllerPasswordFile -ne 'C:\DSH\tools\bootstrap\controller-password.clixml'){throw 'Unexpected password-transfer path'}
    if((Get-Item -LiteralPath $ControllerPasswordFile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Password transfer must not be redirected'}
    $ControllerPassword=Import-Clixml -LiteralPath $ControllerPasswordFile
    Remove-Item -LiteralPath $ControllerPasswordFile
    if($ControllerPassword -isnot [SecureString]){throw 'Password transfer did not contain a SecureString'}
}
if(!$ControllerPassword){
    Write-Host 'Create a password for the ordinary Windows account DSHAudit. It is stored by Windows, not in this repository.'
    $ControllerPassword=Read-Host 'DSHAudit password' -AsSecureString
}
if($ControllerPassword.Length -eq 0){throw 'The controller password must not be empty'}
foreach($dir in @('admin-evidence','kit','workspace','data','data\temp','logs','tools\ollama','tools\models','source\deepseek-harness-master')){New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force|Out-Null}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmssfff'
Start-Transcript -LiteralPath (Join-Path $root ('admin-evidence\install-'+$stamp+'.txt')) -NoClobber
try {
    foreach($name in @('Runtime','Kit','Ollama','Models','Node')){Get-HarnessPayload -RepositoryRoot $RepositoryRoot -Name $name -Destination (Join-Path $root ('tools\payload-cache\'+$name+$(if($name -eq 'Node'){'.exe'}else{'.zip'})))|Out-Null}
    [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $root 'tools\payload-cache\Runtime.zip'),$source)
    $files=Get-Content -LiteralPath (Join-Path $source 'DEPLOYMENT_FILES.json') -Raw|ConvertFrom-Json
    function Resolve-DeploymentPath([string]$relative){
        $path=[IO.Path]::GetFullPath((Join-Path $source $relative))
        if(!$path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Deployment path escapes source'}
        return $path
    }
    foreach($file in $files){if((Get-FileHash -LiteralPath (Resolve-DeploymentPath $file.path)).Hash.ToLowerInvariant() -ne $file.SHA256){throw ('Runtime file hash mismatch: '+$file.path)}}
    $links=Get-Content -LiteralPath (Join-Path $source 'DEPLOYMENT_LINKS.json') -Raw|ConvertFrom-Json
    foreach($link in $links){
        $path=Resolve-DeploymentPath $link.path;$target=Resolve-DeploymentPath $link.target
        if($link.missingTarget -or !(Test-Path -LiteralPath $target -PathType Container) -or (Test-Path -LiteralPath $path)){throw ('Invalid runtime junction: '+$link.path)}
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($path)) -Force|Out-Null
        New-Item -ItemType Junction -Path $path -Target $target|Out-Null
    }
    foreach($item in @(@('Kit','kit'),@('Ollama','tools\ollama'),@('Models','tools\models'))){[IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $root ('tools\payload-cache\'+$item[0]+'.zip')),(Join-Path $root $item[1]))}
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'deploy\licenses\Ollama-LICENSE.txt') -Destination (Join-Path $root 'tools\ollama\LICENSE')
    $nodeTarget='C:\Program Files\nodejs\node.exe';$nodeSource=Join-Path $root 'tools\payload-cache\Node.exe'
    if((Test-Path -LiteralPath $nodeTarget) -and (Get-FileHash -LiteralPath $nodeTarget).Hash -ne (Get-FileHash -LiteralPath $nodeSource).Hash){throw 'A different Node installation already exists; refusing to overwrite it'}
    New-Item -ItemType Directory -Path 'C:\Program Files\nodejs' -Force|Out-Null
    Copy-Item -LiteralPath $nodeSource -Destination $nodeTarget -Force
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'deploy\licenses\Node.txt') -Destination 'C:\Program Files\nodejs\LICENSE'
    $machinePath=[Environment]::GetEnvironmentVariable('Path','Machine')
    if($machinePath.Split(';') -notcontains 'C:\Program Files\nodejs'){[Environment]::SetEnvironmentVariable('Path',($machinePath+';C:\Program Files\nodejs'),'Machine')}
    $env:Path='C:\Program Files\nodejs;'+$env:Path
    $workerBytes=[Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $workerPassword=ConvertTo-SecureString ([Convert]::ToBase64String($workerBytes)+'Aa1!') -AsPlainText -Force
    & (Join-Path $root 'kit\Initialize-WindowsWorker.ps1') -ConfirmAccountChanges -ControllerPassword $ControllerPassword -WorkerPassword $workerPassword
    & (Join-Path $root 'kit\Freeze-WindowsPermissions.ps1')
    $publicDesktop=[Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $publicDesktop 'Harness-First-Run.lnk'))
    $shortcut.TargetPath='C:\DSH\tools\PowerShell7\pwsh.exe'
    $shortcut.Arguments='-NoLogo -NoProfile -NoExit -ExecutionPolicy RemoteSigned -File "C:\DSH\kit\Setup-User.ps1"'
    $shortcut.WorkingDirectory='C:\DSH\workspace';$shortcut.Description='Sign in as DSHAudit, configure English/Russian input and open local Harness';$shortcut.Save()
    $version=Get-Content -LiteralPath (Join-Path $RepositoryRoot 'deploy\VERSION.json') -Raw|ConvertFrom-Json
    $result=[ordered]@{version=$version.version;os=(Get-CimInstance Win32_OperatingSystem).Caption;cpu=(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors;fileCount=$files.Count;linkCount=$links.Count;controller='DSHAudit';worker='DSHAgent';status='Installed; sign in as DSHAudit and open Harness-First-Run'}
    $result|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'logs\installation.json') -Encoding utf8
    Write-Host 'Installation complete. Sign out, sign in as DSHAudit with your chosen password, and open Harness-First-Run.'
} finally {Stop-Transcript}
