# Archys Print Helper

Small Windows service that lets the Archys web app print receipts on the
Premax POS-80 thermal printer with an automatic paper cut, bold text and the
shop logo. It receives raw ESC/POS bytes from the app on `http://127.0.0.1:9101`
and sends them straight to the printer, bypassing the (text-only) driver.

Pure PowerShell, so nothing to install on the laptop besides this folder.

## Install on a laptop
1. Plug in the printer and switch it on.
2. Unzip this folder and double-click `Install.bat` (accepts the Administrator prompt).
3. Answer `Y` to print a test receipt.

The installer adds the "Generic / Text Only" driver and a "Premax POS-80"
printer on the USB port if missing, copies the helper to
`C:\Program Files\ArchysPrintHelper`, and starts it automatically at login.
`Uninstall.bat` removes the helper (the Windows printer entry is kept).

## Settings
Edit `config.json` in the install folder:
- `printerName`: Windows printer name (default `Premax POS-80`). If it isn't found, the helper picks a Text Only printer on a USB port.
- `port`: default `9101`
- `allowedOrigins`: web origins allowed to print, `["*"]` for any

## Troubleshooting
- Health check: open `http://127.0.0.1:9101/health` in a browser.
- Log: `C:\ProgramData\ArchysPrintHelper\helper.log`
- If the helper isn't running, the app falls back to the normal browser print dialog.
