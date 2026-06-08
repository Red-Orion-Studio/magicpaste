"""
Shared application state for the MagicPaste Windows client.

Holds connection status, the paired device, received-screenshot history, and
user settings. Persists settings + history to a JSON file next to the exe so
they survive restarts. UI layers (tray icon, popup, settings window, toasts)
subscribe via add_listener() and re-render when something changes.
"""

import base64
import json
import os
import secrets
import threading
import time

import protocol

APP_DIR = os.path.join(os.path.expanduser("~"), ".magicpaste")
STATE_FILE = os.path.join(APP_DIR, "state.json")
# Full-resolution copies of received screenshots, so the user can re-copy an
# older one to the clipboard from History. Capped to the same _MAX_HISTORY.
HISTORY_DIR = os.path.join(APP_DIR, "history")

_MAX_HISTORY = 50


def _now_ms() -> int:
    return int(time.time() * 1000)


def relative_time(ms: int) -> str:
    """Human '2 min ago' style label."""
    if not ms:
        return ""
    secs = max(0, (_now_ms() - ms) // 1000)
    if secs < 60:
        return "now"
    mins = secs // 60
    if mins < 60:
        return f"{mins} min" + ("" if mins == 1 else "")
    hrs = mins // 60
    if hrs < 24:
        return f"{hrs} hr"
    days = hrs // 24
    return f"{days} d"


class AppState:
    def __init__(self):
        self._lock = threading.RLock()
        self._listeners = []

        # runtime
        self.connected = False  # recent activity (ping/image) seen
        self.paired = False     # we know a device (persisted)
        self.paired_device = None  # str device name
        self.device_ip = None
        self.last_seen_ms = 0
        self.paused = False
        # Transient "accept a new pairing" window (monotonic deadline). While
        # open, an unknown (no-token) device may pair even though one is already
        # paired — the user opens it explicitly from the UI/tray. Not persisted.
        self._pairing_until = 0.0

        # persisted
        self.port = protocol.DEFAULT_PORT
        # Shared secret the phone must present on every message. Generated once,
        # rotated on unpair (so a forgotten phone immediately loses access).
        self.token = None  # 32-char hex str
        self.start_with_windows = False
        self.show_notifications = True
        self.image_quality = "High"  # Low | Medium | High
        self.lang = "system"  # 'system' | 'en' | 'es'
        self.history = []  # list of dicts: {name,w,h,ts,thumb_b64}

        # cached pairing QR (regenerated only when address changes)
        self._qr_cache_key = None
        self._qr_cache_b64 = None

        self._load()

    # -- listeners ---------------------------------------------------------

    def add_listener(self, fn):
        with self._lock:
            self._listeners.append(fn)

    def _notify(self):
        for fn in list(self._listeners):
            try:
                fn(self)
            except Exception:  # noqa: BLE001 — never let UI errors kill core
                pass

    # -- persistence -------------------------------------------------------

    def _load(self):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.port = int(data.get("port", self.port))
            self.start_with_windows = bool(data.get("start_with_windows", False))
            self.show_notifications = bool(data.get("show_notifications", True))
            self.image_quality = data.get("image_quality", "High")
            self.lang = data.get("lang", "system")
            self.paused = bool(data.get("paused", False))
            self.history = data.get("history", [])
            # Remember the paired device across restarts so we don't fall back
            # to the QR pairing screen every launch.
            self.paired = bool(data.get("paired", False))
            self.paired_device = data.get("paired_device")
            self.device_ip = data.get("device_ip")
            self.token = data.get("token") or None
        except (FileNotFoundError, ValueError, OSError):
            pass
        # Always have a token ready (first run, or upgrading an old state file).
        if not self.token:
            self.token = secrets.token_hex(protocol.TOKEN_SIZE)
            self._save()

    def _save(self):
        try:
            os.makedirs(APP_DIR, exist_ok=True)
            data = {
                "port": self.port,
                "start_with_windows": self.start_with_windows,
                "show_notifications": self.show_notifications,
                "image_quality": self.image_quality,
                "lang": self.lang,
                "paused": self.paused,
                "history": self.history[:_MAX_HISTORY],
                "paired": self.paired,
                "paired_device": self.paired_device,
                "device_ip": self.device_ip,
                "token": self.token,
            }
            # Write atomically: a crash / force-kill mid-write would otherwise
            # truncate state.json, losing the token and forcing a re-pair.
            tmp = STATE_FILE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, STATE_FILE)
        except OSError:
            pass

    # -- mutations ---------------------------------------------------------

    def pair(self, device=None, ip=None):
        """A phone paired with us — remember it across restarts."""
        with self._lock:
            self.paired = True
            self.connected = True
            self.last_seen_ms = _now_ms()
            if device is not None:
                self.paired_device = device
            if ip is not None:
                self.device_ip = ip
            # A successful pairing closes the "allow new device" window.
            self._pairing_until = 0.0
            self._save()
        self._notify()

    def open_pairing_window(self, seconds: int = 120):
        """Allow a new (untokened) device to pair for the next `seconds`."""
        with self._lock:
            self._pairing_until = time.monotonic() + seconds
        self._notify()

    def pairing_open(self) -> bool:
        return time.monotonic() < self._pairing_until

    def pairing_seconds_left(self) -> int:
        return max(0, int(self._pairing_until - time.monotonic()))

    def unpair(self):
        with self._lock:
            self.paired = False
            self.connected = False
            self.paired_device = None
            self.device_ip = None
            # Rotate the secret so the forgotten phone can no longer send.
            self.token = secrets.token_hex(protocol.TOKEN_SIZE)
            self._qr_cache_key = None  # force QR regen with the new token
            self._save()
        self._notify()

    def token_bytes(self) -> bytes | None:
        """The expected auth token as raw bytes, or None if unset."""
        with self._lock:
            if not self.token:
                return None
            try:
                return bytes.fromhex(self.token)
            except ValueError:
                return None

    def mark_activity(self, ip=None):
        """Any message (ping/image) from the phone -> it's alive & connected."""
        changed = not self.connected
        with self._lock:
            self.last_seen_ms = _now_ms()
            if ip is not None:
                self.device_ip = ip
            if not self.connected:
                self.connected = True
            # First contact also implies a pairing if we somehow lost it.
            if not self.paired:
                self.paired = True
                self._save()
        if changed:
            self._notify()

    def check_timeout(self, timeout_s: int = 20):
        """Drop to 'disconnected' if no activity for a while (called by a timer)."""
        if not self.connected:
            return
        if _now_ms() - self.last_seen_ms > timeout_s * 1000:
            with self._lock:
                self.connected = False
            self._notify()

    def set_connected(self, connected: bool, device=None, ip=None):
        with self._lock:
            self.connected = connected
            if device is not None:
                self.paired_device = device
            if ip is not None:
                self.device_ip = ip
        self._notify()

    def set_paused(self, paused: bool):
        with self._lock:
            self.paused = paused
            self._save()
        self._notify()

    def add_received(self, name, width, height, thumb_png: bytes | None,
                     image_bytes: bytes | None = None):
        with self._lock:
            ts = _now_ms()
            item_id = str(ts)
            # Save the full image to disk so it can be re-copied later.
            if image_bytes:
                try:
                    os.makedirs(HISTORY_DIR, exist_ok=True)
                    with open(os.path.join(HISTORY_DIR, item_id + ".img"), "wb") as f:
                        f.write(image_bytes)
                except OSError:
                    item_id = None  # couldn't persist the full image
            item = {
                "id": item_id,
                "name": name,
                "w": width,
                "h": height,
                "ts": ts,
                "thumb": base64.b64encode(thumb_png).decode("ascii") if thumb_png else None,
            }
            self.history.insert(0, item)
            # Drop overflow and delete their on-disk images.
            for old in self.history[_MAX_HISTORY:]:
                self._delete_history_file(old.get("id"))
            self.history = self.history[:_MAX_HISTORY]
            self._save()
        self._notify()

    def _delete_history_file(self, item_id):
        if not item_id:
            return
        try:
            os.remove(os.path.join(HISTORY_DIR, str(item_id) + ".img"))
        except OSError:
            pass

    def history_image_bytes(self, item_id) -> bytes | None:
        """Full image bytes for a history entry, for re-copying to clipboard."""
        if not item_id:
            return None
        try:
            with open(os.path.join(HISTORY_DIR, str(item_id) + ".img"), "rb") as f:
                return f.read()
        except OSError:
            return None

    def clear_history(self):
        with self._lock:
            for it in self.history:
                self._delete_history_file(it.get("id"))
            self.history = []
            self._save()
        self._notify()

    def update_settings(self, **kw):
        with self._lock:
            for k, v in kw.items():
                if hasattr(self, k):
                    setattr(self, k, v)
            self._save()
        self._notify()

    # -- snapshot for UI ---------------------------------------------------

    def _pairing(self) -> dict:
        """LAN address + cached QR PNG for the pairing UI."""
        try:
            from pairing_info import pairing_address, pairing_qr_data, qr_png_b64
            addr = pairing_address(self.port)
            qr_data = pairing_qr_data(self.port, self.token)
            if qr_data != self._qr_cache_key:
                self._qr_cache_key = qr_data
                self._qr_cache_b64 = qr_png_b64(qr_data)
            return {"address": addr, "qr": self._qr_cache_b64}
        except Exception:  # noqa: BLE001
            return {"address": "", "qr": None}

    def snapshot(self) -> dict:
        with self._lock:
            pairing = self._pairing()
            return {
                "connected": self.connected,
                "paired": self.paired,
                "paused": self.paused,
                "pairingOpen": self.pairing_open(),
                "pairingSecondsLeft": self.pairing_seconds_left(),
                "device": self.paired_device or "No device",
                "deviceIp": self.device_ip or "",
                "pairAddress": pairing["address"],
                "pairQr": pairing["qr"],
                "port": self.port,
                "startWithWindows": self.start_with_windows,
                "showNotifications": self.show_notifications,
                "imageQuality": self.image_quality,
                "lang": self.lang,
                "history": [
                    {
                        "id": h.get("id"),
                        "name": h["name"],
                        "w": h["w"],
                        "h": h["h"],
                        "ts": h["ts"],
                        "rel": relative_time(h["ts"]),
                        "thumb": h.get("thumb"),
                    }
                    for h in self.history
                ],
            }
