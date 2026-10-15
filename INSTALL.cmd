@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command "Get-ChildItem -LiteralPath '%~dp0deploy' -Filter '*.ps1' -File | Unblock-File; & '%~dp0deploy\Start-Install.ps1' -RepositoryRoot '%~dp0.'"
if errorlevel 1 (
  echo Installation did not complete. Preserve the console message and C:\DSH for diagnosis.
  pause
  exit /b 1
)
