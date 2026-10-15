$ErrorActionPreference='Stop'
if(![Security.Principal.WindowsIdentity]::GetCurrent().Name.EndsWith('\DSHAudit',[StringComparison]::OrdinalIgnoreCase)){throw 'Configure input under DSHAudit'}
$languages=Get-WinUserLanguageList
$hasEnglish=$false;$hasRussian=$false
foreach($language in $languages){
    if($language.LanguageTag -eq 'en-US'){$hasEnglish=$true;if($language.InputMethodTips -notcontains '0409:00000409'){$language.InputMethodTips.Add('0409:00000409')}}
    if($language.LanguageTag -match '^ru(?:-|$)'){$hasRussian=$true;if($language.InputMethodTips -notcontains '0419:00000419'){$language.InputMethodTips.Add('0419:00000419')}}
}
if(!$hasEnglish){$languages.Add('en-US')}
if(!$hasRussian){$languages.Add('ru-RU')}
Set-WinUserLanguageList -LanguageList $languages -Force
$rows=@(foreach($language in (Get-WinUserLanguageList)){[ordered]@{language=$language.LanguageTag;inputMethodTips=@($language.InputMethodTips)}})
$tips=@(foreach($row in $rows){foreach($tip in $row.inputMethodTips){$tip}})
if('0409:00000409' -notin $tips -or '0419:00000419' -notin $tips){throw 'English/Russian input configuration failed'}
$rows|ConvertTo-Json -Depth 3|Set-Content -LiteralPath 'C:\DSH\logs\keyboard-layouts.json' -Encoding utf8
Write-Output 'English US and Russian input are configured. Use Win+Space after sign-in.'
