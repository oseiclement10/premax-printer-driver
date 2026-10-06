# OAC Print Helper
# Local service that lets the web app send raw ESC/POS bytes to the receipt
# printer (auto-cut, bold, logo). Listens on 127.0.0.1 only. Pure PowerShell:
# nothing to install besides Windows itself.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Config (config.json next to this script, all keys optional) ──────────────
$config = @{ printerName = 'Premax POS-80'; port = 9101; allowedOrigins = @('*') }
$cfgFile = Join-Path $here 'config.json'
if (Test-Path $cfgFile) {
  $j = Get-Content $cfgFile -Raw | ConvertFrom-Json
  if ($j.printerName) { $config.printerName = [string]$j.printerName }
  if ($j.port) { $config.port = [int]$j.port }
  if ($j.allowedOrigins) { $config.allowedOrigins = @($j.allowedOrigins) }
}

$logDir = Join-Path $env:ProgramData 'OACPrintHelper'
$logFile = Join-Path $logDir 'helper.log'
function Write-Log([string]$msg) {
  try {
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 512KB) { Remove-Item $logFile -Force }
    Add-Content -Path $logFile -Value ("{0:s}  {1}" -f (Get-Date), $msg)
  } catch { }
}

# ── Raw printing through the Windows spooler ────────────────────────────────
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class RawPrinter {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public class DOCINFOA {
    [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
  }
  [DllImport("winspool.Drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true)]
  public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);
  [DllImport("winspool.Drv", SetLastError = true, ExactSpelling = true)]
  public static extern bool ClosePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true)]
  public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);
  [DllImport("winspool.Drv", SetLastError = true, ExactSpelling = true)]
  public static extern bool EndDocPrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", SetLastError = true, ExactSpelling = true)]
  public static extern bool StartPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", SetLastError = true, ExactSpelling = true)]
  public static extern bool EndPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", SetLastError = true, ExactSpelling = true)]
  public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

  public static void Send(string printer, byte[] bytes) {
    IntPtr h;
    if (!OpenPrinter(printer, out h, IntPtr.Zero))
      throw new Exception("Cannot open printer '" + printer + "' (error " + Marshal.GetLastWin32Error() + ")");
    try {
      DOCINFOA di = new DOCINFOA { pDocName = "Receipt", pDataType = "RAW" };
      if (!StartDocPrinter(h, 1, di)) throw new Exception("StartDocPrinter failed (error " + Marshal.GetLastWin32Error() + ")");
      try {
        StartPagePrinter(h);
        IntPtr p = Marshal.AllocCoTaskMem(bytes.Length);
        try {
          Marshal.Copy(bytes, 0, p, bytes.Length);
          int written;
          if (!WritePrinter(h, p, bytes.Length, out written) || written != bytes.Length)
            throw new Exception("WritePrinter failed (error " + Marshal.GetLastWin32Error() + ")");
        } finally { Marshal.FreeCoTaskMem(p); }
        EndPagePrinter(h);
      } finally { EndDocPrinter(h); }
    } finally { ClosePrinter(h); }
  }
}
'@

# The configured printer if it exists, otherwise the first thermal-looking one
# (a "Generic / Text Only" printer on a USB port, or a name like POS/Premax/receipt).
function Resolve-Printer {
  $all = @(Get-Printer -ErrorAction SilentlyContinue)
  $match = $all | Where-Object { $_.Name -eq $config.printerName } | Select-Object -First 1
  if (-not $match) {
    $match = $all | Where-Object { $_.DriverName -eq 'Generic / Text Only' -and $_.PortName -like 'USB*' } | Select-Object -First 1
  }
  if (-not $match) {
    $match = $all | Where-Object { $_.Name -match 'POS|Premax|receipt|thermal' } | Select-Object -First 1
  }
  if ($match) { return $match.Name }
  return $null
}

# ── HTTP server ──────────────────────────────────────────────────────────────
$MaxBytes = 512KB
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$($config.port)/")
try {
  $listener.Start()
} catch {
  Write-Log "Could not listen on port $($config.port) (already running?): $($_.Exception.Message)"
  exit 1
}
Write-Log "Started on 127.0.0.1:$($config.port)"

function Test-OriginAllowed([string]$origin) {
  if ($config.allowedOrigins -contains '*') { return $true }
  return [bool]($origin -and ($config.allowedOrigins -contains $origin))
}

function Send-Json($res, [int]$status, $obj) {
  $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
  $res.StatusCode = $status
  $res.ContentType = 'application/json'
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

while ($listener.IsListening) {
  try { $ctx = $listener.GetContext() } catch { break }
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $origin = $req.Headers['Origin']
    if ($origin -and (Test-OriginAllowed $origin)) {
      $res.Headers.Add('Access-Control-Allow-Origin', $(if ($config.allowedOrigins -contains '*') { '*' } else { $origin }))
      $res.Headers.Add('Vary', 'Origin')
    }
    $res.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $res.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    # Chrome requires this when a public website calls a localhost service.
    $res.Headers.Add('Access-Control-Allow-Private-Network', 'true')

    $path = $req.Url.AbsolutePath
    if ($req.HttpMethod -eq 'OPTIONS') {
      $res.StatusCode = 204
    }
    elseif ($origin -and -not (Test-OriginAllowed $origin)) {
      Send-Json $res 403 @{ ok = $false; error = 'Origin not allowed' }
    }
    elseif ($req.HttpMethod -eq 'GET' -and $path -eq '/health') {
      $p = Resolve-Printer
      Send-Json $res 200 @{ ok = $true; printer = $p; printerFound = [bool]$p }
    }
    elseif ($req.HttpMethod -eq 'POST' -and $path -eq '/print') {
      if ($req.ContentLength64 -gt $MaxBytes) {
        Send-Json $res 413 @{ ok = $false; error = 'Payload too large' }
      } else {
        $reader = New-Object System.IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd() | ConvertFrom-Json
        if (-not $body.data) {
          Send-Json $res 400 @{ ok = $false; error = "Missing base64 'data'" }
        } else {
          $printer = Resolve-Printer
          if (-not $printer) {
            Write-Log 'Print failed: no receipt printer found'
            Send-Json $res 500 @{ ok = $false; error = 'No receipt printer found. Check it is plugged in and installed.' }
          } else {
            [RawPrinter]::Send($printer, [Convert]::FromBase64String([string]$body.data))
            Send-Json $res 200 @{ ok = $true; printer = $printer }
          }
        }
      }
    }
    else {
      Send-Json $res 404 @{ ok = $false; error = 'Not found' }
    }
  } catch {
    Write-Log "Request failed: $($_.Exception.Message)"
    try { Send-Json $res 500 @{ ok = $false; error = $_.Exception.Message } } catch { }
  } finally {
    try { $res.Close() } catch { }
  }
}
