# Windows 11 installation only. Requires the already installed PowerShell 7 and Node.
# Admin: apply; standard DSHAudit: run again with -Verify.
# No recursive icacls /T. No directory traversal through reparse points.
# This is deployment ACL repair, not an adversarial runtime sandbox.
# Revision 3.1: caller-owned sandbox roots; confined child grants are unchanged.
[CmdletBinding()]
param([switch]$Verify, [switch]$PlanOnly)
$ErrorActionPreference = 'Stop'
if ($Verify -and $PlanOnly) { throw 'Use either -Verify or -PlanOnly, not both' }
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use C:\Program Files\PowerShell\7\pwsh.exe, not powershell.exe' }
if (-not $IsWindows) { throw 'Windows 11 installation required' }
$PSNativeCommandUseErrorActionPreference = $false
$deployRoot = 'C:\DSH'
$taskSourceRoot = Join-Path $deployRoot 'source\deepseek-harness-master'
$taskCliEntry = Join-Path $taskSourceRoot 'apps\cli\lib\bin.js'
if (!(Test-Path -LiteralPath $taskCliEntry -PathType Leaf)) { $taskCliEntry=Join-Path $taskSourceRoot 'lib\bin.js' }
if (!(Test-Path -LiteralPath $taskCliEntry -PathType Leaf)) { $taskCliEntry=Join-Path $taskSourceRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js' }
# pnpm exposes the CLI through junctions. Place the canary in its physical
# directory, which the planner enumerates once without traversing links.
$taskNode = 'C:\Program Files\nodejs\node.exe'
if (!(Test-Path -LiteralPath $taskNode -PathType Leaf)) { throw 'Installed Node executable is missing' }
$taskResolvedCli = & $taskNode -e 'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' $taskCliEntry
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($taskResolvedCli)) { throw 'Cannot resolve the installed CLI entry' }
$taskCliEntry = [string]$taskResolvedCli
if (!$taskCliEntry.StartsWith($taskSourceRoot+'\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Resolved CLI entry escapes the reviewed source tree' }
$readRoots = @('source','kit','tools') | ForEach-Object { Join-Path $deployRoot $_ }
$writeRoots = @('data','workspace','logs') | ForEach-Object { Join-Path $deployRoot $_ }
$sandboxRoots = @('workspace','data\temp') | ForEach-Object { Join-Path $deployRoot $_ }
$adminOnlyRoots = @('admin-evidence') | ForEach-Object { Join-Path $deployRoot $_ }
$probes = @($readRoots | ForEach-Object { Join-Path $_ '.dsh-acl-canary.txt' })
$probes += Join-Path ([IO.Path]::GetDirectoryName($taskCliEntry)) '.dsh-acl-canary.txt'
$marker = 'SYNTHETIC_DSH_ACL_CANARY_V2'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Verify) {
    if ($elevated -or -not $identity.Name.EndsWith('\DSHAudit', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Verification must run in a normal, non-elevated DSHAudit PowerShell window'
    }
    $verifyLog = Join-Path $deployRoot ('logs\acl-verify-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.txt')
    $failures = 0
    $passed = 0
    function Report([string]$message) {
        Write-Host $message
        Add-Content -LiteralPath $verifyLog -Value $message -Encoding utf8
    }
    Report ('Account: ' + $identity.Name + '; elevated: false')
    foreach ($file in $probes) {
        if ([IO.File]::ReadAllText($file) -ne $marker) { throw "Missing or changed synthetic canary: $file" }
        if (([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReadOnly) -ne 0) {
            throw "ReadOnly attribute makes this ACL test inconclusive: $file"
        }
        try {
            $handle = [IO.File]::Open($file, [IO.FileMode]::Open, [IO.FileAccess]::Write,
                ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $handle.Dispose()
            Report "FAIL: write handle allowed: $file"
            $failures++
        } catch [UnauthorizedAccessException] {
            Report "PASS: canary readable, write handle denied: $file"
            $passed++
        }
        $parent = [IO.Path]::GetDirectoryName($file)
        $trial = Join-Path $parent ('.dsh-acl-dir-test-' + [guid]::NewGuid().ToString('N'))
        try {
            [IO.Directory]::CreateDirectory($trial) | Out-Null
            Report "FAIL: directory creation allowed: $parent"
            $failures++
            [IO.Directory]::Delete($trial, $false)
        } catch [UnauthorizedAccessException] {
            if (Test-Path -LiteralPath $trial) { throw "Unexpected test directory remains: $trial" }
            Report "PASS: directory creation denied: $parent"
            $passed++
        }
    }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DshDirectoryRights {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
    public static void Check(string path) {
        IntPtr h=CreateFileW(path, 0x000C0000, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
        if (h==new IntPtr(-1)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        if (!CloseHandle(h)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
}
"@
    foreach ($dir in $sandboxRoots) {
        $owner=(Get-Acl -LiteralPath $dir).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($owner -ne $identity.User.Value) { throw "Sandbox root is not caller-owned: $dir" }
        [DshDirectoryRights]::Check($dir)
        Report "PASS: caller-owned directory opens with WRITE_DAC and WRITE_OWNER: $dir"
        $passed++
    }
    foreach ($dir in $writeRoots) {
        $trial = Join-Path $dir ('.dsh-acl-rw-test-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($trial) | Out-Null
        $file = Join-Path $trial 'synthetic.txt'
        [IO.File]::WriteAllText($file, $marker)
        [IO.File]::AppendAllText($file, '-APPEND')
        if ([IO.File]::ReadAllText($file) -ne ($marker + '-APPEND')) { throw "Read/write mismatch: $dir" }
        [IO.File]::Delete($file)
        [IO.Directory]::Delete($trial, $false)
        Report "PASS: create/read/append/delete: $dir"
        $passed++
    }
    if ($failures -ne 0) { throw "ACL verification failed: $failures failures. Log: $verifyLog" }
    Report "ACL_VERIFIED: $passed checks. Log: $verifyLog"
    Report 'Scope: synthetic canaries only; not every installation file, hard-link case or model tool.'
    return
}

if (-not $elevated) { throw 'Open PowerShell 7 as administrator on the target Windows installation' }
if ($env:NODE_OPTIONS) { throw 'NODE_OPTIONS must be absent in this preparation window' }
if (Get-Process -Name icacls -ErrorAction SilentlyContinue) { throw 'An icacls operation is still running. Stop the old operation first.' }
if (Get-Process -Name node -ErrorAction SilentlyContinue) { throw 'Existing Node processes must be inspected and stopped before ACL repair.' }
$user = Get-LocalUser -Name DSHAudit
if (-not $user.Enabled) { throw 'DSHAudit is disabled' }
$sid = $user.SID.Value
$worker = Get-LocalUser -Name DSHAgent
$workerSid = $worker.SID.Value
if (-not $worker.Enabled) { throw 'DSHAgent is disabled' }
if (Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { $_.SID.Value -eq $workerSid }) { throw 'DSHAgent must not be Administrator' }
$admins = Get-LocalGroup -SID 'S-1-5-32-544'
if (Get-LocalGroupMember -Group $admins.Name | Where-Object { $_.SID.Value -eq $sid }) {
    throw 'DSHAudit must NOT belong to Administrators'
}
foreach ($dir in $sandboxRoots) { if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Create ordinary sandbox root before planning: $dir" } }
foreach ($file in @($taskCliEntry,'C:\Program Files\nodejs\node.exe')) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required file is missing: $file" }
}

# Read-only planning uses lstat, not a recursive Windows ACL walk.
# Resolve link targets for containment checks; never enqueue those targets.
# The complete uploaded scan identified four links to two absent optional packages.
$planner = @'
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
function buildPlan(root) {
  const ro = ['source','kit','tools'].map(n => path.join(root,n));
  const rw = ['data','workspace','logs'].map(n => path.join(root,n));
  const within = (p,b) => p.toLowerCase() === b.toLowerCase() || p.toLowerCase().startsWith(b.toLowerCase()+path.sep);
  const same = (a,b) => a.toLowerCase() === b.toLowerCase();
  if (fs.lstatSync(root).isSymbolicLink()) throw Error('Deployment root is a link');
  const base = fs.realpathSync(root);
  const directories = [], links = [];
  let files = 0, hardLinkedFiles = 0;
  function knownMissingOptional(p, originalError) {
    const store = path.join(root,'source','deepseek-harness-master','node_modules','.pnpm');
    const reviewed = [
      {
        mainPackage:'@anthropic-ai/claude-agent-sdk',version:'0.3.263',
        optionalName:'@anthropic-ai/claude-agent-sdk-win32-x64',optionalSpec:'0.3.263',
        targetParts:['@anthropic-ai+claude-agent-sdk-win32-x64@0.3.263','node_modules','@anthropic-ai','claude-agent-sdk-win32-x64'],
        linkParts:[
          ['node_modules','@anthropic-ai','claude-agent-sdk-win32-x64'],
          ['@anthropic-ai+claude-agent-_d28c5258171e04b4bc6aca7166a6f5a1','node_modules','@anthropic-ai','claude-agent-sdk-win32-x64']
        ]
      },
      {
        mainPackage:'@openai/codex',version:'0.153.4',
        optionalName:'@openai/codex-win32-x64',optionalSpec:'npm:@openai/codex@0.153.4-win32-x64',
        targetParts:['@openai+codex@0.153.4-win32-x64','node_modules','@openai','codex'],
        linkParts:[
          ['node_modules','@openai','codex-win32-x64'],
          ['@openai+codex@0.153.4','node_modules','@openai','codex-win32-x64']
        ]
      }
    ];
    const spec=reviewed.find(r=>r.linkParts.some(parts=>same(p,path.join(store,...parts))));
    if (originalError.code !== 'ENOENT' || !spec) {
      throw Error('Unresolved link requires review: '+p+'; '+originalError.message);
    }
    const expected=path.join(store,...spec.targetParts);
    const rawTarget = fs.readlinkSync(p);
    const target = path.resolve(path.dirname(p),rawTarget);
    if (!same(target,expected)) throw Error('Unexpected optional-package link target: '+p+' -> '+target);
    const storeStat = fs.lstatSync(store);
    if (!storeStat.isDirectory() || storeStat.isSymbolicLink() ||
        !same(fs.realpathSync(store),store) || !ro.some(r=>within(store,r))) {
      throw Error('Optional-package store is not an ordinary contained directory: '+store);
    }
    // Every existing target prefix must be an ordinary directory. In particular,
    // do not accept ENOENT caused by an ancestor link pointing outside the tree.
    let prefix=store, missing=false;
    for (const segment of spec.targetParts) {
      prefix=path.join(prefix,segment);
      let st;
      try { st=fs.lstatSync(prefix); }
      catch(e) { if(e.code==='ENOENT') { missing=true; break; } throw e; }
      if (st.isSymbolicLink() || !st.isDirectory()) throw Error('Invalid optional-package target prefix: '+prefix);
    }
    if (!missing) throw Error('Optional target exists but resolution failed: '+p);
    const mainAlias=path.join(store,'node_modules',...spec.mainPackage.split('/'));
    const mainTarget=fs.realpathSync(mainAlias);
    if (!within(mainTarget,store)) throw Error('Provider manifest is outside its pnpm store: '+spec.mainPackage);
    const manifest=path.join(mainTarget,'package.json');
    const manifestStat=fs.lstatSync(manifest);
    if (!manifestStat.isFile() || manifestStat.isSymbolicLink()) throw Error('Provider manifest is not an ordinary file: '+manifest);
    const pkg=JSON.parse(fs.readFileSync(manifest,'utf8'));
    if (pkg.name!==spec.mainPackage || pkg.version!==spec.version ||
        pkg.optionalDependencies?.[spec.optionalName]!==spec.optionalSpec) {
      throw Error('Unexpected provider manifest or optional-package version: '+spec.mainPackage);
    }
    return {path:p,target,rawTarget,missingTarget:true,
      optionalPackage:spec.optionalName,mainVersion:spec.version,
      reason:'Reviewed absent optional binary; ACL applies to link itself; Claude/Codex tools must remain disabled'};
  }
  for (const top of [...ro,...rw]) {
    const st = fs.lstatSync(top);
    if (!st.isDirectory() || st.isSymbolicLink() || !within(fs.realpathSync(top),base)) throw Error('Invalid root: '+top);
    const writable = rw.includes(top);
    const queue = [top];
    for (let i=0;i<queue.length;i++) {
      const dir=queue[i];
      const names=fs.readdirSync(dir);
      directories.push({path:dir,childCount:names.length,writable});
      for (const name of names) {
        const p=path.join(dir,name), s=fs.lstatSync(p);
        if (s.isSymbolicLink()) {
          if (writable) throw Error('Link in writable tree requires review: '+p);
          let target;
          try { target=fs.realpathSync(p); }
          catch(e) { links.push(knownMissingOptional(p,e)); continue; }
          if (!ro.some(r=>within(target,r))) throw Error('Link target is outside read-only deployment trees: '+p+' -> '+target);
          links.push({path:p,target});
        } else if (s.isDirectory()) queue.push(p);
        else if (s.isFile()) { files++; if(s.nlink>1) hardLinkedFiles++; }
        else throw Error('Unsupported filesystem entry: '+p);
      }
    }
  }
  const source=path.join(root,'source','deepseek-harness-master');
  if (!same(fs.realpathSync(source),source)) throw Error('Source directory is redirected');
  const sourceHashes=JSON.parse(fs.readFileSync(path.join(root,'kit','source-version.json'),'utf8'));
  const versionFiles=['pnpm-lock.yaml','pnpm-workspace.yaml','package.json'];
  if(Object.keys(sourceHashes).sort().join('|')!==versionFiles.sort().join('|')||Object.values(sourceHashes).some(v=>typeof v!=='string'||!/^[a-f0-9]{64}$/.test(v)))throw Error('Invalid reviewed source version manifest');
  for(const [name,expectedHash] of Object.entries(sourceHashes)) {
    const p=path.join(source,name),st=fs.lstatSync(p);
    if(!st.isFile()||st.isSymbolicLink()) throw Error('Source version file is not ordinary: '+p);
    const actual=crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
    if(actual!==expectedHash) throw Error('Source dependency/configuration version changed: '+p);
  }
  return {revision:'2.2',directories,links,files,hardLinkedFiles,sourceHashes};
}
try { process.stdout.write(JSON.stringify(buildPlan(process.argv[1]))); }
catch(e) { console.error(e.message); process.exitCode=1; }
'@
$planText = & 'C:\Program Files\nodejs\node.exe' -e $planner $deployRoot 2>&1
$planExit = $LASTEXITCODE
if ($planExit -ne 0) { throw ('Read-only planning failed BEFORE ACL changes: ' + ($planText -join "`n")) }
$plan = ConvertFrom-Json -InputObject ($planText -join "`n")
$knownMissing = @($plan.links | Where-Object { $_.missingTarget -eq $true })
foreach ($link in $knownMissing) {
    Write-Host ('KNOWN_MISSING_OPTIONAL: ' + $link.path + ' -> ' + $link.target)
}
if ($knownMissing.Count -gt 0) {
    Write-Host 'Optional Claude/Codex binaries remain absent. Keep both tools disabled in the offline configuration.'
}
if ($PlanOnly) {
    Write-Host "PLAN_OK: ordinary directories=$($plan.directories.Count); links=$($plan.links.Count); known missing optional links=$($knownMissing.Count). No ACL changes."
    return
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$logDir = Join-Path $deployRoot ('logs\acl-v2-' + $stamp)
New-Item -ItemType Directory -Path $logDir | Out-Null
$aclLog = Join-Path $logDir 'operations.txt'
[IO.File]::WriteAllText((Join-Path $logDir 'plan.json'), ($plan | ConvertTo-Json -Depth 6))
$snapshots = foreach ($dir in @($deployRoot) + @($readRoots) + @($writeRoots)) {
    [pscustomobject]@{path=$dir; sddl=(Get-Acl -LiteralPath $dir).Sddl}
}
$snapshots | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logDir 'root-acl-before.json') -Encoding utf8
# This snapshot contains root ACLs only, not a complete recursive rollback.
if (Test-Path -LiteralPath 'C:\DSH\logs\permissions.txt') {
    Move-Item -LiteralPath 'C:\DSH\logs\permissions.txt' -Destination ('C:\DSH\logs\permissions-v1-' + $stamp + '.txt')
}
foreach ($file in $probes) {
    $parent = [IO.Path]::GetDirectoryName($file)
    $row = @($plan.directories | Where-Object { $_.path -eq $parent })
    if ($row.Count -ne 1) { throw "Canary parent is not a planned ordinary directory: $parent" }
    if (Test-Path -LiteralPath $file) {
        if (((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Canary is a link: $file" }
        if ([IO.File]::ReadAllText($file) -ne $marker) { throw "Refusing to overwrite an existing non-canary file: $file" }
    } else {
        [IO.File]::WriteAllText($file, $marker)
        $row[0].childCount++
    }
}

function Invoke-Acl([string]$path, [string[]]$arguments) {
    $nativePath = '\\?\' + $path
    $output = & 'C:\Windows\System32\icacls.exe' $nativePath @arguments 2>&1
    $code = $LASTEXITCODE
    Add-Content -LiteralPath $aclLog -Value ("PATH: $path`n" + ($output -join "`n")) -Encoding utf8
    if ($code -ne 0) { throw "ACL operation failed, exit $code. Path: $path. Log: $aclLog" }
}
# Confirm native long-path support without changing ACLs.
$longParent = Join-Path $logDir (('a' * 90) + '\' + ('b' * 90) + '\' + ('c' * 90))
[IO.Directory]::CreateDirectory($longParent) | Out-Null
$longProbe = Join-Path $longParent 'synthetic.txt'
[IO.File]::WriteAllText($longProbe, $marker)
Invoke-Acl $longProbe @('/verify','/L','/Q')
[IO.File]::Delete($longProbe)
[IO.Directory]::Delete($longParent, $false)
[IO.Directory]::Delete([IO.Path]::GetDirectoryName($longParent), $false)
[IO.Directory]::Delete((Join-Path $logDir ('a' * 90)), $false)

function Set-RootPolicy([string]$path, [bool]$writable, [bool]$adminOnly = $false) {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    if ($adminOnly -or -not $writable) { $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')) }
    $acl.SetAccessRuleProtection($true, $false)
    $flags = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach ($id in @('S-1-5-18','S-1-5-32-544',$sid,$workerSid)) {
        if ($adminOnly -and $id -in @($sid,$workerSid)) { continue }
        if ($id -eq $workerSid -and $path -in @('C:\DSH\data','C:\DSH\logs')) { continue }
        $rights = if ($id -in @('S-1-5-18','S-1-5-32-544')) { [Security.AccessControl.FileSystemRights]::FullControl }
                  elseif ($writable -and ($id -eq $sid -or $path -eq 'C:\DSH\workspace')) { [Security.AccessControl.FileSystemRights]::Modify }
                  else { [Security.AccessControl.FileSystemRights]::ReadAndExecute }
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($id), $rights, $flags,
            [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $path -AclObject $acl
    Add-Content -LiteralPath $aclLog -Value "ROOT_POLICY: $path; writable=$writable" -Encoding utf8
}
# Preserve private administrator evidence before changing inherited root rights.
foreach ($dir in $adminOnlyRoots) {
    if (Test-Path -LiteralPath $dir) {
        $item = Get-Item -LiteralPath $dir -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Invalid administrator-only root: $dir" }
        Set-RootPolicy $dir $false $true
    }
}
Set-RootPolicy $deployRoot $false
foreach ($dir in $readRoots) { Set-RootPolicy $dir $false }
foreach ($dir in $writeRoots) { Set-RootPolicy $dir $true }

# One directory level per call. /L acts on links themselves. No /T or /C.
$processed = 0
foreach ($dir in $plan.directories) {
    if ($dir.childCount -gt 0) { Invoke-Acl (Join-Path $dir.path '*') @('/reset','/L','/Q') }
    $processed++
    if ($processed % 100 -eq 0) { Write-Host "Processed ordinary directories: $processed / $($plan.directories.Count)" }
}
Write-Host "ACL_APPLIED. Ordinary directories: $processed. Links: $($plan.links.Count). Log: $aclLog"
Write-Host "Files with multiple hard links: $($plan.hardLinkedFiles). Their ACLs may also affect the installation pnpm store."
# Only the sandbox provisioning roots receive host-user FullControl. The child
# capability GRANT_MASK in sandbox-windows-acl still excludes WRITE_DAC/WRITE_OWNER.
foreach ($dir in $sandboxRoots) {
    $item=Get-Item -LiteralPath $dir -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Invalid sandbox provisioning root: $dir" }
    $acl=Get-Acl -LiteralPath $dir
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($sid))
    $flags=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),[Security.AccessControl.FileSystemRights]::FullControl,$flags,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
    $acl.SetAccessRule($rule)
    $workerRule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($workerSid),[Security.AccessControl.FileSystemRights]::Modify,$flags,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
    $acl.SetAccessRule($workerRule)
    Set-Acl -LiteralPath $dir -AclObject $acl
    Add-Content -LiteralPath $aclLog -Value "SANDBOX_HOST_ROOT: $dir; caller owner; host FullControl; child grant unchanged" -Encoding utf8
}
Write-Host 'Next: sign out of Admin; sign in as DSHAudit; run this script with -Verify in a normal PowerShell 7 window.'
Write-Host 'DSHAgent gets Modify only within workspace/data-temp, no controller data/log grants. Native worker token separately intersects writes and lowers integrity.'
Write-Host 'This does not certify runtime tools, every installation file, or all runtime isolation.'
