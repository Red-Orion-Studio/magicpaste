# MagicPaste — Windows client

Receives screenshots from the MagicPaste Android app over your local WiFi and
puts them straight on your Windows clipboard. Press **Ctrl+V** to paste.

## Quick start (test it on your PC right now — no phone needed)

```powershell
# 1. Install dependencies
pip install -r requirements.txt

# 2. Start the client (a tray icon appears)
python magicpaste.py

# 3. In a SECOND terminal, simulate the phone:
python test_client.py
```

Then press **Ctrl+V** in Paint / Word / any chat box. You should see the
"MagicPaste test image — paste worked!" picture. That confirms the entire
Windows receive → clipboard pipeline works.

Send your own image:

```powershell
python test_client.py --image C:\path\to\screenshot.png
```

Run without a tray icon (headless, useful for debugging over SSH/terminal):

```powershell
python magicpaste.py --no-tray --verbose
```

## Tray menu

- **Show pairing info** — opens a page with your PC's IP + a QR code to scan
- **Start with Windows** — toggle launching MagicPaste at login
- **Quit**

## Build a standalone .exe

```powershell
pip install pyinstaller
pyinstaller --onefile --windowed --name=MagicPaste magicpaste.py
# result: dist\MagicPaste.exe  (no Python needed to run it)
```

## Files

| File           | Purpose                                  |
|----------------|------------------------------------------|
| `magicpaste.py`| entry point (server + mDNS + tray)       |
| `server.py`    | TCP listener & protocol dispatch         |
| `clipboard.py` | writes images to the Windows clipboard   |
| `discovery.py` | mDNS/zeroconf advertisement              |
| `tray.py`      | system tray UI + pairing info + autostart|
| `protocol.py`  | shared binary protocol definitions       |
| `test_client.py`| simulates the phone for local testing   |
