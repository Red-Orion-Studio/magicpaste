# Contributing to MagicPaste

[![Español](https://img.shields.io/badge/README-Español-7C3AED.svg)](CONTRIBUTING.es.md)

Thanks for your interest in contributing! MagicPaste is a small open-source project by [Red Orion Studio](https://www.redorionstudio.com). Any help is welcome.

---

## Ways to contribute

- **Report bugs** — open an [issue](https://github.com/RedOrionStudio/magicpaste/issues) with steps to reproduce, your Android version/OEM, and Windows version
- **Test on other devices** — especially non-Xiaomi OEMs (Samsung, Pixel, OnePlus, Motorola)
- **Fix bugs** — pick an open issue and submit a PR
- **Improve translations** — EN and ES are included; adding more languages is welcome
- **Add features from the roadmap** — see `SPEC.md` section 10 for the v2 list

---

## Project structure

| Folder | Stack |
|--------|-------|
| `magicpaste-android/` | Flutter (Dart) + Kotlin native background engine |
| `magicpaste-windows/` | Python 3.10+ + pywebview + pystray |
| `branding/` | SVG source files for logos and icons |
| `.github/workflows/` | CI/CD — builds APK and EXE on every push |

See [`SPEC.md`](SPEC.md) for the full architecture, protocol description, and future roadmap.

---

## Development setup

### Windows client

```powershell
cd magicpaste-windows
pip install -r requirements.txt
python magicpaste.py
```

To simulate the phone sending a screenshot:
```powershell
python test_client.py
```

To run the protocol unit tests:
```powershell
pip install pytest
pytest tests/
```

### Android app

```powershell
cd magicpaste-android
flutter pub get
flutter run
```

To run Flutter tests:
```powershell
flutter test
```

---

## Pull request guidelines

1. **One PR per concern** — don't mix bug fixes with new features
2. **Keep it simple** — no new dependencies without discussion
3. **Test your change** — run `pytest tests/` (Python) and `flutter test` (Android) before submitting
4. **Follow the existing style** — no formatter wars; match the surrounding code
5. **Update the SPEC** if you add or change a feature

---

## Signing / release

The release keystore (`magicpaste-release.jks`) and `key.properties` are **not in the repository** and are kept by Red Orion Studio. Release APKs are built and signed by the maintainers only.

---

## Code of conduct

Be kind. This is a hobby project — maintainer response time may vary.

---

*Made by [Red Orion Studio](https://www.redorionstudio.com) — GPLv3*
