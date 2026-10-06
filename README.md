# OAC Print Helper

Lightweight Windows service that prints receipts on 80mm ESC/POS thermal
printers straight from a web app, with auto-cut, bold text and logo printing,
even when the printer only has a text-only driver.

Browser print dialogs and generic Windows drivers handle thermal receipt
printers badly: plain text, no styling, and far too much blank paper. This
helper runs quietly on `127.0.0.1`, accepts raw ESC/POS bytes from your web app
over a simple HTTP call, and sends them straight to the printer through the
Windows spooler. The result is proper formatting, logos and a clean paper cut.

Pure PowerShell: nothing to install except this folder. Built for the Premax
POS-80 but works with any ESC/POS printer installed in Windows.

## Install on a laptop
1. Plug in the printer and switch it on.
2. Unzip this folder and double-click `Install.bat` (accept the Administrator prompt).
3. Answer `Y` to print a test receipt.

The installer adds the "Generic / Text Only" driver and a "Premax POS-80"
printer on the USB port if missing, copies the helper to
`C:\Program Files\OACPrintHelper`, and starts it automatically at login.
`Uninstall.bat` removes the helper (the Windows printer entry is kept).

## API
All requests go to `http://127.0.0.1:9101` (CORS and Chrome Private Network Access are handled).

| Method | Path      | Body                                        | Result |
|--------|-----------|---------------------------------------------|--------|
| GET    | `/health` | none                                        | `{ ok, printer, printerFound }` |
| POST   | `/print`  | `{ "data": "<base64 ESC/POS bytes>" }`      | `{ ok, printer }` or `{ ok: false, error }` |

Example from a web app:

```js
await fetch("http://127.0.0.1:9101/print", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ data: btoa(String.fromCharCode(...escposBytes)) }),
});
```

## Settings
Edit `config.json` in the install folder (`C:\Program Files\OACPrintHelper`):

- `printerName`: Windows printer name (default `Premax POS-80`). If it isn't found, the helper picks a Text Only printer on a USB port.
- `port`: default `9101`
- `allowedOrigins`: web origins allowed to print. The default `["*"]` lets any website send print jobs to this PC's receipt printer, which is fine on a private shop machine. For anything else, list your app's origin, e.g. `["https://app.example.com"]`.

## Troubleshooting
- Health check: open `http://127.0.0.1:9101/health` in a browser.
- Log: `C:\ProgramData\OACPrintHelper\helper.log`
- If the helper isn't running, your app can fall back to the normal browser print dialog.
- If the printer isn't listed in Windows, replug it, try another USB port, and run `Install.bat` again.

## Support
Built by **OAC Tech Hub**. For help or custom setups, contact us on mobile / WhatsApp: **233200039147**.

## License
[MIT](LICENSE)
