# Windows installation: run only on the intended target machine, as administrator.
# Review before use: creates/resets two local accounts and grants controller process rights.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][switch]$ConfirmAccountChanges,
    [Parameter(Mandatory)][SecureString]$ControllerPassword,
    [Parameter(Mandatory)][SecureString]$WorkerPassword,
    [string]$DeploymentRoot = 'C:\DSH',
    [string]$Controller = 'DSHAudit',
    [string]$Worker = 'DSHAgent'
)
$ErrorActionPreference = 'Stop'
if (!$ConfirmAccountChanges) { throw 'Explicit account-change confirmation is required.' }
$taskAdmin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$taskAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Elevated administrator required.' }
if ($Controller -eq $Worker) { throw 'Controller and worker must have different identities.' }
$taskRoot = [IO.Path]::GetFullPath($DeploymentRoot).TrimEnd('\')
if ($taskRoot -eq [IO.Path]::GetPathRoot($taskRoot).TrimEnd('\')) { throw 'A volume root is not a deployment directory.' }
$taskEvidence = Join-Path $taskRoot 'admin-evidence'
if (!(Test-Path -LiteralPath $taskRoot -PathType Container) -or ((Get-Item -LiteralPath $taskRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Deployment root must be an existing ordinary directory.' }
if ((Test-Path -LiteralPath $taskEvidence) -and (((Get-Item -LiteralPath $taskEvidence -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or !(Test-Path -LiteralPath $taskEvidence -PathType Container))) { throw 'Administrator evidence directory must not be a reparse point or file.' }
New-Item -ItemType Directory -Force -Path $taskEvidence | Out-Null
# Protect the directory BEFORE writing exported policy, additions or databases.
# The controller and worker do not receive access to administrator policy evidence.
$taskEvidenceAcl = [Security.AccessControl.DirectorySecurity]::new()
$taskEvidenceAcl.SetAccessRuleProtection($true, $false)
$taskEvidenceAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
foreach ($taskEvidenceSid in @('S-1-5-18','S-1-5-32-544')) {
    $taskEvidenceAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($taskEvidenceSid),[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
}
Set-Acl -LiteralPath $taskEvidence -AclObject $taskEvidenceAcl
$taskStamp = (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '-' + [guid]::NewGuid().ToString('N')
$taskBackup = Join-Path $taskEvidence "userrights-before-$taskStamp.inf"
& secedit.exe /export /cfg $taskBackup /areas USER_RIGHTS /quiet
if ($LASTEXITCODE -ne 0) { throw "secedit export failed: $LASTEXITCODE" }

foreach ($taskAccount in @(@{Name=$Controller; Password=$ControllerPassword}, @{Name=$Worker; Password=$WorkerPassword})) {
    $taskExisting = Get-LocalUser -Name $taskAccount.Name -ErrorAction SilentlyContinue
    if (!$taskExisting) {
        New-LocalUser -Name $taskAccount.Name -Password $taskAccount.Password -PasswordNeverExpires -AccountNeverExpires | Out-Null
    } else {
        Set-LocalUser -Name $taskAccount.Name -Password $taskAccount.Password -PasswordNeverExpires $true
        Enable-LocalUser -Name $taskAccount.Name
    }
    $taskUser = Get-LocalUser -Name $taskAccount.Name
    $taskAdmins = @(Get-LocalGroupMember -SID 'S-1-5-32-544')
    if ($taskAdmins.SID.Value -contains $taskUser.SID.Value) { throw "$($taskAccount.Name) is an administrator; refusing this deployment." }
    $taskUsers = @(Get-LocalGroupMember -SID 'S-1-5-32-545')
    if ($taskUsers.SID.Value -notcontains $taskUser.SID.Value) { Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $taskUser }
}
$taskControllerSid = (Get-LocalUser -Name $Controller).SID
$taskWorkerSid = (Get-LocalUser -Name $Worker).SID

# Exported local policy is preserved in full; only these two entries are extended.
# These are privileged process rights, even though DSHAudit is not an Administrator.
$taskPolicy = Get-Content -LiteralPath $taskBackup
$taskAdditions = @()
foreach ($taskRight in @('SeAssignPrimaryTokenPrivilege','SeIncreaseQuotaPrivilege')) {
    $taskIndex = -1
    for ($taskI=0; $taskI -lt $taskPolicy.Count; $taskI++) { if ($taskPolicy[$taskI] -match "^$taskRight\s*=") { $taskIndex=$taskI; break } }
    $taskExistingSids = if ($taskIndex -ge 0) { @(($taskPolicy[$taskIndex] -split '=',2)[1].Trim().Split(',') | Where-Object { $_ }) } else { @() }
    $taskPrincipal = '*' + $taskControllerSid.Value
    if ($taskExistingSids -notcontains $taskPrincipal) {
        $taskLine = "$taskRight = " + (($taskExistingSids + $taskPrincipal) -join ',')
        if ($taskIndex -ge 0) { $taskPolicy[$taskIndex] = $taskLine } else {
            $taskSection = [Array]::IndexOf($taskPolicy, '[Privilege Rights]')
            if ($taskSection -lt 0) { throw 'Export has no Privilege Rights section.' }
            $taskPolicy = @($taskPolicy[0..$taskSection]) + $taskLine + @($taskPolicy[($taskSection+1)..($taskPolicy.Count-1)])
        }
        $taskAdditions += @{Right=$taskRight; Account=$Controller; Sid=$taskControllerSid.Value}
    }
}
$taskPolicyPath = Join-Path $taskEvidence "userrights-after-$taskStamp.inf"
$taskPolicy | Set-Content -LiteralPath $taskPolicyPath -Encoding Unicode
# Assign only the two controller rights; the full export and INF remain review evidence.
. (Join-Path $PSScriptRoot 'Controller-Rights.ps1')
$taskControllerBinary = [byte[]]::new($taskControllerSid.BinaryLength)
$taskControllerSid.GetBinaryForm($taskControllerBinary, 0)
$taskWorkerBinary = [byte[]]::new($taskWorkerSid.BinaryLength)
$taskWorkerSid.GetBinaryForm($taskWorkerBinary, 0)
$taskDirectBefore = @([DshProvisionRights]::Read($taskControllerBinary))
[DshProvisionRights]::Grant($taskControllerBinary)
$taskDirectAfter = @([DshProvisionRights]::Read($taskControllerBinary))
$taskWorkerDirect = @([DshProvisionRights]::Read($taskWorkerBinary))
foreach ($taskRight in @('SeAssignPrimaryTokenPrivilege','SeIncreaseQuotaPrivilege')) {
    if ($taskDirectAfter -notcontains $taskRight -or $taskWorkerDirect -contains $taskRight) { throw 'Controller/worker direct rights verification failed.' }
}
@{Method='LsaAddAccountRights';ControllerSid=$taskControllerSid.Value;Before=$taskDirectBefore;After=$taskDirectAfter;WorkerSid=$taskWorkerSid.Value;WorkerDirectRights=$taskWorkerDirect} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskEvidence "userrights-direct-$taskStamp.json") -Encoding UTF8
$taskAdditions | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskEvidence "userrights-additions-$taskStamp.json") -Encoding UTF8

function Set-PrivateControllerAcl([string]$taskPath, [bool]$taskDirectory) {
    $taskAcl = if ($taskDirectory) { [Security.AccessControl.DirectorySecurity]::new() } else { [Security.AccessControl.FileSecurity]::new() }
    $taskAcl.SetAccessRuleProtection($true, $false)
    $taskAcl.SetOwner($taskControllerSid)
    foreach ($taskSid in @($taskControllerSid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'), [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
        $taskInheritance = if ($taskDirectory) { [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' } else { [Security.AccessControl.InheritanceFlags]::None }
        $taskAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($taskSid, [Security.AccessControl.FileSystemRights]::FullControl, $taskInheritance, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow))
    }
    Set-Acl -LiteralPath $taskPath -AclObject $taskAcl
}
foreach ($taskPrivate in @('data','logs')) {
    $taskPath = Join-Path $taskRoot $taskPrivate
    if ((Test-Path -LiteralPath $taskPath) -and (((Get-Item -LiteralPath $taskPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or !(Test-Path -LiteralPath $taskPath -PathType Container))) { throw "Controller-private path must be an ordinary directory: $taskPath" }
    New-Item -ItemType Directory -Force -Path $taskPath | Out-Null
    Set-PrivateControllerAcl $taskPath $true
    # No recursive changes here: existing child ACLs require their own review/provisioning.
}
$taskCredentialPath = Join-Path $taskRoot 'data\worker-credentials.json'
if ((Test-Path -LiteralPath $taskCredentialPath) -and (((Get-Item -LiteralPath $taskCredentialPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or !(Test-Path -LiteralPath $taskCredentialPath -PathType Leaf))) { throw 'Worker credential path must be an ordinary file.' }
# Create the protected empty file before publishing the credential bytes.
New-Item -ItemType File -Force -Path $taskCredentialPath | Out-Null
Set-PrivateControllerAcl $taskCredentialPath $false
$taskPasswordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($WorkerPassword)
try {
    $taskCredential = @{username=$Worker; domain=$env:COMPUTERNAME; password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($taskPasswordPtr); expectedSid=$taskWorkerSid.Value}
    [IO.File]::WriteAllText($taskCredentialPath, ($taskCredential | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskPasswordPtr)
    $taskCredential = $null
}

[pscustomobject]@{
    Controller=$Controller; ControllerSid=$taskControllerSid.Value; Worker=$Worker; WorkerSid=$taskWorkerSid.Value
    UserRightsBackup=$taskBackup; UserRightsAfter=$taskPolicyPath; Additions=$taskAdditions
    WorkerCredentials=$taskCredentialPath
    RequiredNextStep='Start a fresh DSHAudit logon after provisioning. Provision source/tools ReadAndExecute and workspace/private-temp ordinary worker write rights plus restricting-SID grants. Verify existing child ACLs separately.'
    Risk='Controller receives SeAssignPrimaryTokenPrivilege and SeIncreaseQuotaPrivilege. Worker receives neither. Protect controller executable/source/config/credential storage from worker writes; both accounts must remain outside Administrators.'
} | ConvertTo-Json -Depth 5
