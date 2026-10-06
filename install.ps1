# OAC Print Helper installer. Run via Install.bat (it elevates to Administrator).
# 1. Copies the helper to Program Files
# 2. Makes sure the Premax receipt printer exists in Windows (creates it if missing)
# 3. Starts the helper now and at every login
# 4. Optionally prints a test receipt
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:ProgramFiles 'OACPrintHelper'
$printerName = 'Premax POS-80'
$driverName = 'Generic / Text Only'

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "    OK  $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    !!  $msg" -ForegroundColor Yellow }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Please run Install.bat (it asks for Administrator permission).' }

# ── 1. Stop any running helper, copy files ──────────────────────────────────
Step 'Installing print helper'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*helper.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Path $dest -Force | Out-Null
foreach ($f in 'helper.ps1', 'start-hidden.vbs', 'uninstall.ps1', 'Uninstall.bat') {
  Copy-Item (Join-Path $src $f) $dest -Force
}
# Keep local settings if the helper was installed before.
if (-not (Test-Path (Join-Path $dest 'config.json'))) { Copy-Item (Join-Path $src 'config.json') $dest }
Get-ChildItem $dest -File | Unblock-File
Ok "Installed to $dest"

# ── 2. Receipt printer in Windows ───────────────────────────────────────────
Step "Checking printer '$printerName'"
$existing = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
if ($existing) {
  Ok "Already set up (port $($existing.PortName))"
} else {
  if (-not (Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue)) {
    Add-PrinterDriver -Name $driverName
    Ok "Added driver '$driverName'"
  }
  # USB printer ports (USB001, USB002...) only exist once Windows has seen the printer.
  $usedPorts = @(Get-Printer | ForEach-Object { $_.PortName })
  $usbPorts = @(Get-PrinterPort | Where-Object { $_.Name -like 'USB*' } | ForEach-Object { $_.Name })
  $free = @($usbPorts | Where-Object { $usedPorts -notcontains $_ })
  $port = if ($free.Count -gt 0) { $free[0] } elseif ($usbPorts.Count -gt 0) { $usbPorts[0] } else { $null }

  if ($port) {
    Add-Printer -Name $printerName -DriverName $driverName -PortName $port
    Ok "Created '$printerName' on $port"
    if ($free.Count -gt 1) { Warn "Several unused USB ports found ($($free -join ', ')). If the test receipt does not print, tell your admin." }
  } else {
    Warn 'No USB printer port found. Plug the printer in, switch it on, wait 15 seconds,'
    Warn 'then run Install.bat again. (The helper is installed and will find the printer once it exists.)'
  }
}

# ── 3. Start now and at every login (all users) ─────────────────────────────
Step 'Setting up auto-start'
$lnk = Join-Path ([Environment]::GetFolderPath('CommonStartup')) 'OAC Print Helper.lnk'
$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath = 'wscript.exe'
$s.Arguments = "`"$(Join-Path $dest 'start-hidden.vbs')`""
$s.WorkingDirectory = $dest
$s.Save()
Start-Process wscript.exe -ArgumentList "`"$(Join-Path $dest 'start-hidden.vbs')`""
Ok 'Helper starts automatically at login'

# ── 4. Verify ───────────────────────────────────────────────────────────────
Step 'Checking the helper'
$health = $null
for ($i = 0; $i -lt 10 -and -not $health; $i++) {
  Start-Sleep -Milliseconds 700
  try { $health = Invoke-RestMethod 'http://127.0.0.1:9101/health' -TimeoutSec 2 } catch { }
}
if (-not $health) { throw 'The helper did not start. See C:\ProgramData\OACPrintHelper\helper.log' }
if ($health.printerFound) {
  Ok "Helper running, printer: $($health.printer)"
  $answer = Read-Host 'Print a test receipt now? (Y/N)'
  if ($answer -match '^[Yy]') {
    # ESC @ init, centered; GS ! 0x11 = double size; ESC E = bold; ESC d 4 = feed; GS V B = cut.
    $ascii = [Text.Encoding]::ASCII
    $bytes = [byte[]](0x1B, 0x40, 0x1B, 0x61, 1, 0x1D, 0x21, 0x11) +
      $ascii.GetBytes("SETUP OK`n") + [byte[]](0x1D, 0x21, 0) +
      $ascii.GetBytes("OAC Print Helper installed`n`n") +
      [byte[]](0x1B, 0x45, 1) + $ascii.GetBytes("OAC TECH HUB`n") + [byte[]](0x1B, 0x45, 0) +
      $ascii.GetBytes("Contact us via mail & mobile`n") +
      $ascii.GetBytes("233200039147`n") +
      [byte[]](0x1B, 0x64, 4, 0x1D, 0x56, 0x42, 0)
    $body = @{ data = [Convert]::ToBase64String($bytes) } | ConvertTo-Json
    Invoke-RestMethod 'http://127.0.0.1:9101/print' -Method Post -ContentType 'application/json' -Body $body | Out-Null
    Ok 'Test receipt sent'
  }
} else {
  Warn 'Helper is running but no receipt printer was found yet. Plug it in and run Install.bat again.'
}

Write-Host "`nDone. You can now print receipts from your app." -ForegroundColor Green
