# Changelog

All notable changes to MagicPaste are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.1.0-beta] — 2026-06-07

First public beta release.

### Android
- Auto-detection of new screenshots via `ContentObserver` on MediaStore
- Persistent `ForegroundService` (primary engine) + WorkManager URI trigger (self-heal backup)
- Boot receiver — re-arms background engine after reboot or app update
- TOFU pairing: QR code scanner + manual IP entry
- mDNS discovery — finds the Windows PC automatically on the LAN
- Auto-send toggle and manual "Send latest screenshot" button
- History screen — full log of sent/failed/pending screenshots with thumbnails
- Settings: image quality (Low / Medium / High), language (System / EN / ES), background mode, boot toggle
- English + Spanish UI — auto-detected from device locale, manually overridable
- Localized native notifications (Kotlin `Strings.kt` reads same preference as Flutter)
- Portrait orientation locked
- Glassmorphism design system
- Signed release APK (RSA 2048, valid 10 000 days)

### Windows
- TCP server on port 49152 — receives images, places them in clipboard via `win32clipboard`
- Glassmorphism popup (pywebview / EdgeChromium) with Status / History / Settings tabs
- 3-state tray icon: green = connected, amber = paired/idle, red = unpaired
- Toast notification on screenshot received (bottom-right, auto-dismiss)
- mDNS advertisement via `zeroconf`
- QR code display for easy phone pairing
- Single-instance: second launch raises existing window instead of duplicating
- `--background` flag for tray-only autostart (no window on boot)
- Autostart registry management ("Start with Windows" toggle)
- No console window — launched via `pythonw.exe`
- English + Spanish UI — auto-detected from Windows locale, manually overridable
- Inno Setup installer (`MagicPaste-Setup-v0.1.0-beta.exe`)
- Standalone EXE via PyInstaller (no Python install required)

### Protocol
- 32-byte binary header: magic `SNAP` (0x534E4150), message type, payload length, 16-byte auth token
- Message types: `IMAGE`, `PING`, `PONG`, `PAIR_REQUEST`, `PAIR_ACCEPT`, `IMAGE_ACK`, `PAIR_REJECT`
- IMAGE payload: format (PNG/JPEG) + width + height + raw bytes
- IMAGE_ACK: 1-byte reply confirming clipboard write or reporting drop (paused/error)

---

*Made by [Red Orion Studio](https://www.redorionstudio.com)*
