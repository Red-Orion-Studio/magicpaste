"""
System tray icon for MagicPaste (Windows).

- Violet clipboard glyph with a status dot: green when a phone is connected,
  red when disconnected.
- Left-click  -> toggle the glassmorphism tray popup (handled by WebUI).
- Right-click -> menu: Open popup, Settings, Start with Windows, Quit.

Runs on a background thread; pystray's run_detached() keeps it off the
pywebview main loop.
"""

import logging
import os
import sys

from PIL import Image, ImageDraw

log = logging.getLogger("magicpaste.tray")


def _asset(name: str) -> str:
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, "assets", "icons", name)

try:
    import pystray
    _HAS_PYSTRAY = True
except ImportError:
    pystray = None
    _HAS_PYSTRAY = False

APP_NAME = "MagicPaste"
_RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"

_VIOLET = (124, 58, 237, 255)
_VIOLET_LT = (155, 107, 245, 255)
_GREEN = (52, 211, 153, 255)
_AMBER = (245, 158, 11, 255)
_RED = (248, 113, 113, 255)

# Three states mirror the app UI: connected (green), ready/paired-idle (amber),
# not paired (red).
_STATUS_COLOR = {"connected": _GREEN, "ready": _AMBER, "disconnected": _RED}


def status_of(state) -> str:
    """connected > ready (paired, idle) > disconnected (not paired)."""
    if getattr(state, "connected", False):
        return "connected"
    if getattr(state, "paired", False):
        return "ready"
    return "disconnected"


# -- icon ------------------------------------------------------------------

def make_icon_image(status: str, size: int = 64) -> Image.Image:
    """Tray icon: brand logo with a status dot drawn on top, so all three
    states (green / amber / red) come from one base image."""
    color = _STATUS_COLOR.get(status, _RED)
    try:
        base = Image.open(_asset("logo.png")).convert("RGBA").resize(
            (size, size), Image.LANCZOS)
    except Exception:  # noqa: BLE001 — fall back to a drawn glyph
        base = _drawn_base(size)
    d = ImageDraw.Draw(base)
    r = size * 0.20
    cx, cy = size - r - size * 0.05, size - r - size * 0.05
    # dark ring for contrast against any wallpaper, then the colored dot
    d.ellipse([cx - r - size * 0.04, cy - r - size * 0.04,
               cx + r + size * 0.04, cy + r + size * 0.04], fill=(16, 16, 20, 255))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    return base


def _drawn_base(size: int) -> Image.Image:
    """Fallback brand-ish base (violet rounded square + clipboard) if logo.png
    is missing."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = size // 10
    d.rounded_rectangle([pad, pad, size - pad, size - pad], radius=size // 6, fill=_VIOLET)
    w = size
    lw = max(2, size // 22)
    d.rounded_rectangle(
        [w * 0.30, w * 0.28, w * 0.62, w * 0.66],
        radius=size // 12, outline=(255, 255, 255, 235), width=lw,
    )
    d.line([(w * 0.46, w * 0.30), (w * 0.70, w * 0.30)], fill=(255, 255, 255, 235), width=lw)
    d.line([(w * 0.70, w * 0.30), (w * 0.70, w * 0.56)], fill=(255, 255, 255, 235), width=lw)
    return img


# -- auto-start ------------------------------------------------------------

def _pythonw() -> str:
    # Prefer pythonw.exe (no console window). Check next to python.exe first,
    # then fall back to PATH (Windows Store Python puts it in WindowsApps/).
    import pathlib, shutil
    pw = pathlib.Path(sys.executable).with_name("pythonw.exe")
    if pw.exists():
        return str(pw)
    found = shutil.which("pythonw")
    return found if found else sys.executable

def _exe_path() -> str:
    # Autostart launches in --background mode: tray + service, no window.
    if getattr(sys, "frozen", False):
        return f'"{sys.executable}" --background'
    return f'"{_pythonw()}" "{os.path.abspath(sys.argv[0])}" --background'


def is_autostart_enabled() -> bool:
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, _RUN_KEY) as key:
            winreg.QueryValueEx(key, APP_NAME)
            return True
    except (ImportError, FileNotFoundError, OSError):
        return False


def set_autostart(enabled: bool):
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, _RUN_KEY, 0, winreg.KEY_SET_VALUE) as key:
        if enabled:
            winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, _exe_path())
        else:
            try:
                winreg.DeleteValue(key, APP_NAME)
            except FileNotFoundError:
                pass


# -- tray runner -----------------------------------------------------------

class Tray:
    """Background tray icon. Callbacks: on_left_click, on_settings, on_quit."""

    def __init__(self, state, on_left_click=None, on_settings=None, on_quit=None):
        self.state = state
        self.on_left_click = on_left_click
        self.on_settings = on_settings
        self.on_quit = on_quit
        self._icon = None
        # repaint the icon when the status (connected/ready/disconnected) changes
        state.add_listener(self._on_state)
        self._last_status = None

    _TITLE = {
        "connected": "MagicPaste — Connected",
        "ready": "MagicPaste — Ready (phone idle)",
        "disconnected": "MagicPaste — Not paired",
    }

    def _on_state(self, state):
        status = status_of(state)
        if status != self._last_status and self._icon is not None:
            self._last_status = status
            try:
                self._icon.icon = make_icon_image(status)
                self._icon.title = self._TITLE.get(status, "MagicPaste")
            except Exception:  # noqa: BLE001
                pass

    def start(self):
        if not _HAS_PYSTRAY:
            log.warning("pystray not installed; tray disabled")
            return

        def _left(icon, item):
            if self.on_left_click:
                self.on_left_click()

        def _settings(icon, item):
            if self.on_settings:
                self.on_settings()

        def _toggle_autostart(icon, item):
            set_autostart(not is_autostart_enabled())

        def _allow_new_device(icon, item):
            self.state.open_pairing_window(120)

        def _quit(icon, item):
            if self.on_quit:
                self.on_quit()
            icon.stop()

        menu = pystray.Menu(
            # default=True makes this the left-click action
            pystray.MenuItem("Open MagicPaste", _left, default=True),
            pystray.MenuItem("Settings", _settings),
            pystray.MenuItem("Allow new device (2 min)", _allow_new_device),
            pystray.MenuItem(
                "Start with Windows", _toggle_autostart,
                checked=lambda item: is_autostart_enabled(),
            ),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Quit", _quit),
        )
        self._last_status = status_of(self.state)
        self._icon = pystray.Icon(
            APP_NAME, make_icon_image(self._last_status),
            self._TITLE.get(self._last_status, "MagicPaste"), menu,
        )
        # run_detached -> doesn't block; pywebview owns the main thread.
        self._icon.run_detached()

    def stop(self):
        if self._icon:
            try:
                self._icon.stop()
            except Exception:  # noqa: BLE001
                pass
