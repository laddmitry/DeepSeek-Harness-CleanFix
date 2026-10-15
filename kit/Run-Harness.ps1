[CmdletBinding()]
param(
  [ValidateSet('web','headless','sdk','acp')][string]$Profile='web',
  [string]$Task,
  [string]$DeploymentRoot='C:\DSH',
  [string]$ModelBaseUrl='http://127.0.0.1:11434/v1',
  [string]$ModelName='qwen3:0.6b',
  [ValidateRange(2048,1048576)][int]$ContextWindow=8192,
  [ValidateRange(1,1048576)][int]$MaxTokens=2048,
  [string[]]$ProfileArguments=@()
)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath($DeploymentRoot)
$entry=Join-Path $taskRoot 'source\deepseek-harness-master\apps\cli\lib\bin.js'
if (!(Test-Path -LiteralPath $entry -PathType Leaf)) { $entry=Join-Path $taskRoot 'source\deepseek-harness-master\lib\bin.js' }
if (!(Test-Path -LiteralPath $entry -PathType Leaf)) { $entry=Join-Path $taskRoot 'source\deepseek-harness-master\node_modules\@deepseek-ai\dsh\lib\bin.js' }
if (!(Test-Path -LiteralPath $entry)) { throw 'Build/install Harness first.' }
if ($env:NODE_OPTIONS) { throw 'Use a clean launch environment without NODE_OPTIONS.' }
if ($Profile -eq 'headless' -and !$Task) { throw 'Headless requires a task.' }
$taskCredential=Join-Path $taskRoot 'data\worker-credentials.json'
if (!(Test-Path -LiteralPath $taskCredential -PathType Leaf)) { throw 'Provision the authenticated Windows worker with Initialize-WindowsWorker.ps1 before launch.' }
if ($MaxTokens -ge $ContextWindow) { throw 'MaxTokens must be smaller than ContextWindow.' }
if (!(Test-Path -LiteralPath (Join-Path $taskRoot 'workspace') -PathType Container)) { throw 'Deployment workspace is missing.' }
$taskEnvironment=@{
  DSH_LOCAL_MODEL_BASE_URL=$ModelBaseUrl; DSH_LOCAL_MODEL_NAME=$ModelName
  DSH_LOCAL_MODEL_CONTEXT_WINDOW=[string]$ContextWindow; DSH_LOCAL_MODEL_MAX_TOKENS=[string]$MaxTokens
  DSH_WORKER_CREDENTIAL_FILE=$taskCredential; DSH_NETWORK_LOG=(Join-Path $taskRoot 'logs\network.jsonl')
  DSH_HOME=(Join-Path $taskRoot 'data\home')
}
$taskPrevious=@{}
foreach($taskName in $taskEnvironment.Keys) {
  $taskPrevious[$taskName]=[Environment]::GetEnvironmentVariable($taskName,'Process')
  [Environment]::SetEnvironmentVariable($taskName,$taskEnvironment[$taskName],'Process')
}
Push-Location (Join-Path $taskRoot 'workspace')
try {
  if ($Profile -eq 'headless') { & node $entry --profile headless @ProfileArguments $Task }
  else { & node $entry --profile $Profile @ProfileArguments }
  if ($LASTEXITCODE -ne 0) { throw "Harness exit: $LASTEXITCODE" }
} finally {
  Pop-Location
  foreach($taskName in $taskPrevious.Keys) { [Environment]::SetEnvironmentVariable($taskName,$taskPrevious[$taskName],'Process') }
}
