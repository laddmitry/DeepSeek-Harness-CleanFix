[CmdletBinding()]
param([string]$RepositoryRoot=(Split-Path $PSScriptRoot),[SecureString]$ControllerPassword)
$ErrorActionPreference='Stop'
$RepositoryRoot=[IO.Path]::GetFullPath($RepositoryRoot)
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    $script=Join-Path $RepositoryRoot 'deploy\Start-Install.ps1'
    if($ControllerPassword){throw 'Run an elevated console before passing an automated password'}
    $elevatedArguments='-NoLogo -NoProfile -NoExit -ExecutionPolicy RemoteSigned -File "'+$script+'" -RepositoryRoot "'+$RepositoryRoot+'"'
    $process=Start-Process -FilePath ($env:WINDIR+'\System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $elevatedArguments -Verb RunAs -PassThru -Wait
    if($process.ExitCode -ne 0){throw 'Administrator installer failed'}
    return
}
if(![Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell'}
if((Get-CimInstance Win32_OperatingSystem).Caption -notmatch 'Windows 11 Pro'){throw 'This installer supports clean Windows 11 Pro x64'}
if(Test-Path -LiteralPath 'C:\DSH'){throw 'C:\DSH already exists. This installer only accepts a fresh installation; inspect the existing deployment separately.'}
foreach($name in @('DSHAudit','DSHAgent')){if(Get-LocalUser -Name $name -ErrorAction SilentlyContinue){throw "Local account already exists: $name"}}
. (Join-Path $PSScriptRoot 'Read-Payload.ps1')
New-Item -ItemType Directory -Path 'C:\DSH'|Out-Null
$acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @('S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
Set-Acl -LiteralPath 'C:\DSH' -AclObject $acl
New-Item -ItemType Directory -Path 'C:\DSH\tools\payload-cache','C:\DSH\tools\PowerShell7','C:\DSH\tools\bootstrap'|Out-Null
Get-HarnessPayload -RepositoryRoot $RepositoryRoot -Name PowerShell -Destination 'C:\DSH\tools\payload-cache\PowerShell.zip'|Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory('C:\DSH\tools\payload-cache\PowerShell.zip','C:\DSH\tools\PowerShell7')
foreach($name in @('Read-Payload.ps1','Install-Windows.ps1')){Copy-Item -LiteralPath (Join-Path $RepositoryRoot ('deploy\'+$name)) -Destination ('C:\DSH\tools\bootstrap\'+$name)}
$stageArguments=@('-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-File','C:\DSH\tools\bootstrap\Install-Windows.ps1','-RepositoryRoot',$RepositoryRoot)
$passwordExport='C:\DSH\tools\bootstrap\controller-password.clixml'
try {
    if($ControllerPassword){
        $ControllerPassword|Export-Clixml -LiteralPath $passwordExport
        $stageArguments+=@('-ControllerPasswordFile',$passwordExport)
    }
    & 'C:\DSH\tools\PowerShell7\pwsh.exe' @stageArguments
    if($LASTEXITCODE -ne 0){throw "Installation failed: $LASTEXITCODE. Preserve C:\DSH for diagnosis."}
} finally {if(Test-Path -LiteralPath $passwordExport){Remove-Item -LiteralPath $passwordExport}}
