[CmdletBinding()]
param([switch]$SkipRealModel)
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(!$identity.Name.EndsWith('\DSHAudit',[StringComparison]::OrdinalIgnoreCase) -or ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run verification as ordinary DSHAudit'}
& (Join-Path $PSScriptRoot 'Setup-User.ps1') -NoLaunch
& (Join-Path $PSScriptRoot 'Start-LocalModel.ps1')
$run='C:\DSH\logs\verification-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')
New-Item -ItemType Directory -Path $run|Out-Null
$tests=@('FullRuntimeSmoke','HeadlessRuntimeSmoke','AcpRuntimeSmoke','SubagentRuntimeSmoke','WebRuntimeSmoke')
if(!$SkipRealModel){$tests+= 'RealModelTools'}
$results=@()
foreach($name in $tests){
    @{phase='running';test=$name;run=$run;completed=$results}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath 'C:\DSH\logs\verification-latest.json' -Encoding utf8
    $started=Get-Date
    $process=Start-Process -FilePath 'C:\Program Files\nodejs\node.exe' -ArgumentList (Join-Path $PSScriptRoot ('verification\'+$name+'.mjs')) -WorkingDirectory 'C:\DSH\workspace' -WindowStyle Hidden -RedirectStandardOutput (Join-Path $run ($name+'.stdout.log')) -RedirectStandardError (Join-Path $run ($name+'.stderr.log')) -PassThru
    $testTimeoutMs=if($name -eq 'RealModelTools'){720000}else{240000}
    $timedOut=!$process.WaitForExit($testTimeoutMs)
    if($timedOut){$process.Kill($true);$process.WaitForExit()}
    $results+=[ordered]@{test=$name;exitCode=$process.ExitCode;timedOut=$timedOut;durationSeconds=[math]::Round(((Get-Date)-$started).TotalSeconds,3);passed=(!$timedOut -and $process.ExitCode -eq 0)}
}
$passed=@($results|Where-Object {!$_.passed}).Count -eq 0
$summary=[ordered]@{phase='complete';passed=$passed;run=$run;ordinaryUser=$true;tests=$results;realModelIncluded=(!$SkipRealModel)}
$summary|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $run 'summary.json') -Encoding utf8
$summary|ConvertTo-Json -Depth 5|Set-Content -LiteralPath 'C:\DSH\logs\verification-latest.json' -Encoding utf8
if(!$passed){throw "One or more checks failed. Evidence: $run"}
Write-Output "Verification passed. Evidence: $run"
