# MagicPaste — Project Specification

> Version: 0.1.0 Beta
> Status: Implemented — in beta
> Last updated: 2026-06-07
> [Versión en español](SPEC.es.md)

---

## 1. What is MagicPaste?

MagicPaste is an open-source tool that automatically detects when the user takes a screenshot on Android and sends it to a Windows PC clipboard — so the user can immediately press Ctrl+V to paste it, without any extra steps.

**Core user flow:**
1. User takes a screenshot on Android
2. MagicPaste detects the new screenshot automatically (no user action required)
3. MagicPaste sends the image to the Windows PC over local WiFi
4. The image is placed in the Windows clipboard
5. User presses Ctrl+V anywhere on Windows — done

**No accounts. No internet. No cloud. No registration. Completely local.**

---

## 2. Goals

- Zero configuration after first-time pairing
- Works entirely on local network (WiFi) — no internet required
- Open source (GPLv3 License)
- Easy for non-technical users to install and use
- English + Spanish UI on both platforms

---

## 3. Non-Goals

- No support for iOS
- No cloud sync or remote access
- No text clipboard sync (images/screenshots only, for now)
- No Android-to-Mac support (future feature)

---

## 4. Components

### 4.1 Android App (`magicpaste-android/`)

**Language:** Flutter (Dart) + Kotlin (native background engine)
**Min SDK:** Android 8.0 (API 26)
**Distribution:** GitHub Releases as `.apk`
**Orientation:** Portrait locked

**Screens (bottom nav):**
- **Home** — connection status card, paired device info, auto-send toggle, manual send button, recent history preview
- **History** — full sent/failed/pending log with timestamps and thumbnails
- **Pairing** — QR scanner + manual IP entry, connection status banner
- **Settings** — image quality (Low/Med/High), language selector (System/EN/ES), background mode toggle, boot toggle, about/version

**Background engine (dual-layer):**
- `ScreenshotService.kt` — persistent `ForegroundService` with a `ContentObserver` on `MediaStore.Images.Media.EXTERNAL_CONTENT_URI`. Primary engine. Stays alive in the foreground with an ongoing notification.
- `SyncWorker.kt` — WorkManager `CoroutineWorker` with a URI trigger on the MediaStore. Fires within seconds of a new screenshot. Acts as a self-heal backup: if the OEM killed the service, the worker restarts it. Also runs as a 6h periodic safety net.
- `SyncScheduler.kt` — arms/re-arms WorkManager triggers
- `BootCompletedReceiver.kt` — re-arms on boot and app update
- `ScreenshotScanner.kt` — shared logic for querying MediaStore and sending via the protocol
- `MagicPasteProtocol.kt` — Kotlin implementation of the wire protocol
- `Strings.kt` — Kotlin-side i18n (reads same `mp_lang` pref as Flutter)
- `NotificationActionReceiver.kt` — handles the "Disable" action on the persistent notification

**Flutter services:**
- `screenshot_monitor.dart` — coordinates with native layer
- `network_service.dart` — TCP send logic
- `pairing_service.dart` — pairing state management
- `settings_service.dart` — SharedPreferences wrapper
- `sent_history.dart` — local history of sent screenshots
- `native_sync.dart` — method channel to native
- `protocol.dart` — Dart implementation of the wire protocol
- `l10n.dart` — i18n service (English + Spanish, system-detect or manual override)

**Key packages:** `photo_manager`, `network_info_plus`, `nsd`, `flutter_foreground_task`, `qr_flutter`, `mobile_scanner`, `shared_preferences`, `permission_handler`, `url_launcher`

---

### 4.2 Windows Client (`magicpaste-windows/`)

**Language:** Python 3.10+
**Distribution:** Standalone `.exe` (PyInstaller, onefile) + Inno Setup installer

**UI:** Glassmorphism window via `pywebview` (EdgeChromium/WebView2) — single app window with sidebar tabs: Status / History / Settings. Launched hidden with `--background` for autostart.

**Modules:**
- `magicpaste.py` — entry point; wires all components together; `--background` flag for tray-only mode; single-instance via control port 49199
- `server.py` — TCP listener on port 49152; dispatches IMAGE / PING / PAIR messages
- `clipboard.py` — sets Windows clipboard via `win32clipboard`
- `tray.py` — 3-state pystray icon (green=connected, amber=ready/paired, red=unpaired); autostart registry management; uses `pythonw.exe` for no-console launch
- `webui.py` — pywebview wrapper; exposes Python API to JS; sends state snapshots and i18n strings to the UI; toast notifications
- `state.py` — shared `AppState`; persisted to `state.json`
- `discovery.py` — mDNS advertisement via `zeroconf` (`_magicpaste._tcp.local.`)
- `thumbs.py` — generates thumbnail PNGs for the history view
- `pairing_info.py` — generates QR code for pairing
- `protocol.py` — wire protocol implementation
- `i18n.py` — i18n module (English + Spanish, auto-detects Windows locale)

**Assets:** `assets/main.html`, `assets/toast.html`, `assets/logo.png`, `assets/icons/`

**Python dependencies:** `pywin32`, `Pillow`, `pystray`, `zeroconf`, `qrcode`, `pywebview`

---

## 5. Communication Protocol

### 5.1 Transport
- **Primary:** TCP over local WiFi
- **Port:** `49152` (configurable)
- **Future:** Bluetooth RFCOMM (not implemented)

### 5.2 Message Format

All messages are binary. Every message starts with a fixed **32-byte header**:

```
Bytes  0-3  : Magic number 0x534E4150 ("SNAP")
Bytes  4-7  : Message type (uint32, big-endian)
                0x01 = IMAGE
                0x02 = PING
                0x03 = PONG
                0x04 = PAIR_REQUEST
                0x05 = PAIR_ACCEPT
                0x06 = IMAGE_ACK
                0x07 = PAIR_REJECT
Bytes  8-11 : Payload length in bytes (uint32, big-endian)
Bytes 12-15 : Reserved (0x00000000)
Bytes 16-31 : Auth token (16 bytes). The phone learns this on pairing.
              The PC rejects non-pairing messages with wrong tokens.
              Unauthenticated requests send 16 zero bytes.
```

**IMAGE payload (12-byte prefix + raw image bytes):**
```
Bytes 0-3  : Image format (uint32): 0x01 = PNG, 0x02 = JPEG
Bytes 4-7  : Image width in pixels (uint32)
Bytes 8-11 : Image height in pixels (uint32)
Bytes 12+  : Raw image file bytes
```

**IMAGE_ACK payload (1 byte):** `0x01` = copied to clipboard, `0x00` = dropped (paused or error).

### 5.3 Pairing Flow (TOFU)

1. Android sends `PAIR_REQUEST` with device name as UTF-8 payload
2. PC accepts if: phone already has a valid token, no device is paired yet (first-time), or "Allow new device" window is open
3. PC sends `PAIR_ACCEPT` with a freshly generated 16-byte random token as payload
4. Android stores the token; all subsequent messages include it in the header
5. PC sends `PAIR_REJECT` if already paired and not in pairing mode

mDNS discovery (`_magicpaste._tcp.local.`) lets Android find the PC automatically — no IP typing needed.

---

## 6. First-Time Setup (User Experience)

### Windows side:
1. Run `MagicPaste-Setup-v0.1.0-beta.exe` — installs to Program Files, creates desktop shortcut
2. MagicPaste launches automatically — tray icon appears
3. Right-click tray → "Show pairing info" → QR code + IP displayed in the app window

### Android side:
1. Install `MagicPaste-v0.1.0-beta.apk` from GitHub Releases
2. Open the app → tap **Connect to PC** → scan QR code or type IP manually
3. Pairing completes automatically (TOFU — no manual accept needed on PC)
4. Enable **Auto-send** toggle → done

### After setup:
- Take any screenshot → it appears in PC clipboard in under 2 seconds
- No further interaction needed

---

## 7. Repository Structure

```
magicpaste/
├── README.md
├── README.es.md
├── LICENSE                          (GPLv3)
├── SPEC.md                          (this file)
├── branding/
│   ├── logo-magicpaste.svg          (full violet-bg logo)
│   └── glifo-magicpaste.svg         (glyph only, transparent bg)
├── magicpaste-android/
│   ├── pubspec.yaml
│   ├── key.properties               (not committed — signing config)
│   ├── magicpaste-release.jks       (not committed — release keystore)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/
│   │   │   ├── l10n.dart
│   │   │   ├── screenshot_monitor.dart
│   │   │   ├── network_service.dart
│   │   │   ├── pairing_service.dart
│   │   │   ├── settings_service.dart
│   │   │   ├── sent_history.dart
│   │   │   ├── native_sync.dart
│   │   │   └── protocol.dart
│   │   └── ui/
│   │       ├── theme.dart
│   │       ├── main_shell.dart
│   │       ├── bottom_nav.dart
│   │       ├── home_screen.dart
│   │       ├── history_screen.dart
│   │       ├── pairing_screen.dart
│   │       ├── settings_screen.dart
│   │       └── background_help.dart
│   ├── assets/branding/             (launcher icons, splash)
│   └── android/app/src/main/kotlin/com/magicpaste/magicpaste/
│       ├── MainActivity.kt
│       ├── ScreenshotService.kt
│       ├── SyncWorker.kt
│       ├── SyncScheduler.kt
│       ├── ScreenshotScanner.kt
│       ├── MagicPasteProtocol.kt
│       ├── Strings.kt
│       ├── BootCompletedReceiver.kt
│       └── NotificationActionReceiver.kt
├── magicpaste-windows/
│   ├── requirements.txt
│   ├── magicpaste.py
│   ├── server.py
│   ├── clipboard.py
│   ├── tray.py
│   ├── webui.py
│   ├── state.py
│   ├── discovery.py
│   ├── thumbs.py
│   ├── pairing_info.py
│   ├── protocol.py
│   ├── i18n.py
│   ├── test_client.py
│   ├── test_protocol.py
│   ├── magicpaste.spec              (PyInstaller spec)
│   ├── installer.iss                (Inno Setup script)
│   └── assets/
│       ├── main.html
│       ├── toast.html
│       ├── logo.png
│       └── icons/
│           ├── logo.png
│           ├── magicpaste.ico
│           ├── tray_green.png
│           └── tray_red.png
└── .github/workflows/
    ├── build-android.yml
    └── build-windows.yml
```

---

## 8. GitHub Actions (CI/CD)

Both workflows trigger on pushes to `main` and on new release tags (`v*`). Release tags additionally attach the built artifacts to the GitHub Release.

### Android APK (`build-android.yml`):
- Sets up Java 17 + Flutter
- Runs `flutter build apk --release`
- Uploads `app-release.apk` as artifact and to the release

### Windows EXE (`build-windows.yml`):
- Sets up Python 3.11
- Runs `pip install -r requirements.txt pyinstaller`
- Runs `pyinstaller magicpaste.spec --clean`
- Uploads `MagicPaste.exe` as artifact and to the release

---

## 9. i18n

Both platforms support **English** and **Spanish**. Language is auto-detected from the OS locale (Spanish if `es-*`, English otherwise) and can be overridden manually via a Language selector (System / EN / ES) in Settings.

- **Android (Flutter):** `l10n.dart` — `L10n.t(key)` throughout all screens and the bottom nav
- **Android (Kotlin native):** `Strings.kt` — reads the same `flutter.mp_lang` SharedPreferences key; used in `ScreenshotService` and `SyncWorker` notifications
- **Windows (Python):** `i18n.py` — `i18n.t(key, lang)` for toasts; locale detected via `kernel32.GetUserDefaultLocaleName`
- **Windows (HTML/JS):** `data-i18n` attributes on all static text; `window.applyI18n(dict)` applies translations pushed from Python via `MP_I18N` event

---

## 10. Future Features (v2.0+)

- Bluetooth support (RFCOMM) as fallback when WiFi unavailable
- Text clipboard sync (not just images)
- macOS client
- Linux client
- Multiple paired devices
- Encryption (TLS) for the TCP connection
- Google Play Store release
- Windows app: Microsoft Store release

---

*GPLv3 License — free and open source; forks must stay open. Made by Red Orion Studio.*
