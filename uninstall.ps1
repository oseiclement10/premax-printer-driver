# Removes the OAC Print Helper (the Windows printer entry is left alone).
$ErrorActionPreference = 'SilentlyContinue'
$dest = Join-Path $env:ProgramFiles 'OACPrintHelper'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like "*$dest*helper.ps1*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item (Join-Path ([Environment]::GetFolderPath('CommonStartup')) 'OAC Print Helper.lnk') -Force
Remove-Item (Join-Path $env:ProgramData 'OACPrintHelper') -Recurse -Force

# This script may be running from the folder being removed, so delete it last via cmd.
Start-Process cmd.exe -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$dest`"" -WindowStyle Hidden
Write-Host 'OAC Print Helper removed.'
