# Removes the Archys Print Helper (the Windows printer entry is left alone).
$ErrorActionPreference = 'SilentlyContinue'
$dest = Join-Path $env:ProgramFiles 'ArchysPrintHelper'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*helper.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item (Join-Path ([Environment]::GetFolderPath('CommonStartup')) 'Archys Print Helper.lnk') -Force
Remove-Item (Join-Path $env:ProgramData 'ArchysPrintHelper') -Recurse -Force

# This script may be running from the folder being removed, so delete it last via cmd.
Start-Process cmd.exe -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$dest`"" -WindowStyle Hidden
Write-Host 'Archys Print Helper removed.'
