[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(!$identity.Name.EndsWith('\DSHAudit',[StringComparison]::OrdinalIgnoreCase)){throw 'Use the ordinary DSHAudit account'}
$exe='C:\DSH\tools\ollama\ollama.exe';$pidFile='C:\DSH\data\owned-ollama.json'
try{$existing=Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 2}catch{$existing=$null}
if($existing){
    if(!(Test-Path -LiteralPath $pidFile)){throw 'Port 11434 belongs to an unrecorded server; inspect it before launch'}
    $owned=Get-Content -LiteralPath $pidFile -Raw|ConvertFrom-Json
    $process=Get-Process -Id $owned.processId -ErrorAction Stop
    if($process.Path -ne $exe){throw 'Recorded model PID belongs to a different executable'}
    $listeners=@(Get-NetTCPConnection -State Listen -LocalPort 11434 -ErrorAction Stop)
    if($listeners.Count -ne 1 -or $listeners[0].LocalAddress -ne '127.0.0.1' -or $listeners[0].OwningProcess -ne $process.Id){throw 'The model listener does not match the recorded loopback process'}
    return
}
$env:OLLAMA_NO_CLOUD='1';$env:OLLAMA_HOST='127.0.0.1:11434';$env:OLLAMA_MODELS='C:\DSH\tools\models'
$env:OLLAMA_CONTEXT_LENGTH='8192';$env:OLLAMA_NUM_PARALLEL='1';$env:OLLAMA_MAX_LOADED_MODELS='1'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmssfff'
$process=Start-Process -FilePath $exe -ArgumentList serve -WindowStyle Hidden -RedirectStandardOutput ('C:\DSH\logs\ollama-'+$stamp+'.stdout.log') -RedirectStandardError ('C:\DSH\logs\ollama-'+$stamp+'.stderr.log') -PassThru
@{processId=$process.Id;executable=$exe;bind='127.0.0.1:11434';cloudDisabled=$true}|ConvertTo-Json|Set-Content -LiteralPath $pidFile -Encoding utf8
$ready=$false
for($attempt=0;$attempt -lt 45;$attempt++){
    try{Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 2|Out-Null;$ready=$true;break}catch{Start-Sleep -Seconds 1}
}
if(!$ready){throw 'Ollama did not become ready; inspect its log files'}
$models=Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5
if('qwen3:0.6b' -notin $models.models.name){throw 'Bundled qwen3:0.6b is absent; no download is attempted'}
