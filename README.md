# MagicPaste

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-7C3AED.svg)](LICENSE)
[![Beta](https://img.shields.io/badge/status-beta-orange.svg)]()
[![Español](https://img.shields.io/badge/README-Español-7C3AED.svg)](README.es.md)
[![Ko-fi](https://img.shields.io/badge/Support-Ko--fi-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/redorionstudio)

**Take a screenshot on Android → press Ctrl+V on your Windows PC. That's it.**

[![Download Windows](https://img.shields.io/badge/Windows-Download%20Installer-7C3AED?logo=windows&logoColor=white)](https://github.com/Red-Orion-Studio/magicpaste/releases/download/v0.1.0/MagicPaste-Setup-v0.1.0-beta.exe)
[![Download Android](https://img.shields.io/badge/Android-Download%20APK-7C3AED?logo=android&logoColor=white)](https://github.com/Red-Orion-Studio/magicpaste/releases/download/v0.1.0/app-release.apk)

MagicPaste automatically detects new screenshots on your Android phone and sends
them straight to your Windows clipboard over your local WiFi. No accounts, no
internet, no cloud — completely local and open source.

> **Beta notice:** MagicPaste is in early beta (v0.1.0). It has been tested on
> Xiaomi (MIUI) — one of the most restrictive Android OEMs for background processes
> — so it should work well on most devices. If you hit a bug, please
> [open an issue](https://github.com/Red-Orion-Studio/magicpaste/issues). 🙏

---

## How it works

1. You take a screenshot on Android.
2. MagicPaste detects it automatically (no tapping anything).
3. It sends the image to your PC over local WiFi.
4. The image lands in your Windows clipboard.
5. Press **Ctrl+V** anywhere. Done.

## Project layout

| Folder | What it is |
|--------|------------|
| [`magicpaste-windows/`](magicpaste-windows/) | Windows client (Python) — receives images, sets clipboard |
| [`magicpaste-android/`](magicpaste-android/) | Android app (Flutter) — detects & sends screenshots |
| [`.github/workflows/`](.github/workflows/) | CI to build the `.exe` and `.apk` automatically |

---

## 🧪 Try it before launching (recommended order)

### Step 1 — Test the Windows side on your PC (no phone needed)

```powershell
cd magicpaste-windows
pip install -r requirements.txt
python magicpaste.py            # tray icon appears
# in a second terminal:
python test_client.py           # simulates the phone
```

Press **Ctrl+V** in Paint / Word / a chat box → you should see the test image.
This proves the whole receive→clipboard pipeline works. ✅

### Step 2 — Test on your phone

Flutter isn't required on your PC — the easiest way to get a testable APK is to
build it in the cloud with the included GitHub Action:

1. Push this repo to GitHub.
2. The **Build Android APK** workflow runs automatically (or trigger it manually
   from the Actions tab → "Run workflow").
3. Download the `magicpaste-android` artifact → install the `.apk` on your phone
   (enable "Install from unknown sources").
4. Open the app, pair with your PC (scan the QR from the tray's "Show pairing
   info", or type the IP), then tap **"Send latest screenshot now"** to test
   manually first, then flip on **Auto-send**.

> Prefer to build locally? Install [Flutter](https://docs.flutter.dev/get-started/install/windows),
> then `cd magicpaste-android && flutter build apk`.

### Step 3 — Ship it

Create a GitHub Release tagged `v0.1.0`. Both workflows build and attach the
`.exe` and `.apk` to the release automatically.

---

## FAQ

**Does this need internet?** No. Everything happens on your local WiFi.

**Does it work outside my home WiFi?** No — both devices must be on the same
network.

**Is it safe?** Yes. It's local-only and fully open source — nothing leaves your
network. (Encryption over the TCP link is on the v2 roadmap.)

**iPhone?** Not supported (Android only for now).

---

## Contributing

Issues and PRs welcome. See [`SPEC.md`](SPEC.md) for the full design. Good first
areas: the v2 roadmap (Bluetooth fallback, text clipboard sync, encryption).

## License

[GPLv3](LICENSE) — free and open source. Forks and redistributions must stay
open source under the same license.

Made by [Red Orion Studio](https://www.redorionstudio.com) — *we build software that ships.*
