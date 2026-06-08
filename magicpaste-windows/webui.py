"""
pywebview UI for MagicPaste.

Two windows only:
  - the MAIN window (assets/main.html): a single app window with a sidebar —
    Status / History / Settings. This is the app's "face".
  - the TOAST (assets/toast.html): a Win11-style notification shown bottom-right
    when a screenshot arrives.

pywebview owns the main thread on Windows (webview.start() blocks the WebView2
loop), so this is started LAST from magicpaste.py; the TCP server + tray icon
run on background threads. Windows are created hidden up front, then shown/
hidden on demand. Closing the main window only HIDES it (the background service
keeps running); real shutdown happens via tray → Quit.

HTML calls into Python via `window.pywebview.api.<method>()`; Python pushes
state into pages by evaluating `window.mpRender(<json>)`.
"""

import base64
import json
import os
import sys
import threading
import webbrowser

import i18n

try:
    import webview  # pywebview
    _HAS_WEBVIEW = True
except ImportError:
    webview = None
    _HAS_WEBVIEW = False


def _asset(name: str) -> str:
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, "assets", name)


def _asset_icon(name: str) -> str:
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, "assets", "icons", name)


MAIN_W, MAIN_H = 720, 560
TOAST_W, TOAST_H = 360, 96
_MARGIN = 16
_TASKBAR = 56


class Api:
    """Exposed to JS as window.pywebview.api."""

    def __init__(self, ui: "WebUI"):
        self._ui = ui

    def request_state(self):
        self._ui.push_state()

    def hide_main(self):
        self._ui.hide_main()

    def minimize_main(self):
        self._ui.minimize_main()

    def hide_toast(self):
        self._ui._hide_toast()

    def toggle_pause(self):
        self._ui.on_toggle_pause()
        self._ui.push_state()

    def forget_device(self):
        self._ui.on_forget_device()
        self._ui.push_state()

    def allow_new_device(self):
        # Open a 2-minute window during which an untokened phone may (re)pair.
        self._ui.state.open_pairing_window(120)
        self._ui.push_state()

    def clear_history(self):
        self._ui.state.clear_history()
        self._ui.push_state()

    def copy_history(self, item_id):
        self._ui.copy_history(item_id)

    def set_bool(self, key, value):
        self._ui.on_set_bool(key, bool(value))

    def set_port(self, value):
        try:
            self._ui.on_set_port(int(str(value).strip()))
        except (ValueError, TypeError):
            pass

    def set_quality(self, value):
        self._ui.state.update_settings(image_quality=str(value))

    def open_github(self):
        webbrowser.open("https://github.com/RedOrionStudio/magicpaste")

    def open_studio(self):
        webbrowser.open("https://www.redorionstudio.com")

    def open_kofi(self):
        webbrowser.open("https://ko-fi.com/redorionstudio")

    def set_lang(self, mode):
        self._ui.state.update_settings(lang=str(mode))
        self._ui.push_i18n()
        self._ui.push_state()


class WebUI:
    def __init__(self, state, callbacks=None):
        self.state = state
        self.cb = callbacks or {}
        self._api = Api(self)
        self._main = None
        self._toast = None
        self._toast_hide_timer = None
        self._main_visible = False
        self._quitting = False

    # -- callbacks into app logic -----------------------------------------

    def on_toggle_pause(self):
        fn = self.cb.get("toggle_pause")
        if fn:
            fn()

    def on_forget_device(self):
        fn = self.cb.get("forget_device")
        if fn:
            fn()

    def on_set_bool(self, key, value):
        mapped = {
            "startWithWindows": "start_with_windows",
            "showNotifications": "show_notifications",
        }.get(key, key)
        self.state.update_settings(**{mapped: value})
        fn = self.cb.get("setting_changed")
        if fn:
            fn(key, value)

    def on_set_port(self, port):
        self.state.update_settings(port=port)

    # -- geometry ----------------------------------------------------------

    def _screen(self):
        try:
            s = webview.screens[0]
            return s.width, s.height
        except Exception:  # noqa: BLE001
            return 1920, 1080

    # -- lifecycle ---------------------------------------------------------

    def start(self, show_main: bool = True):
        if not _HAS_WEBVIEW:
            raise RuntimeError("pywebview not installed")

        # Set the AppUserModelID before any window exists so Windows groups the
        # taskbar entry under our app (and uses our icon), not python.exe.
        try:
            import ctypes
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
                "RedOrionStudio.MagicPaste"
            )
        except Exception:  # noqa: BLE001
            pass

        # frameless + easy_drag=False so ONLY the .pywebview-drag-region
        # titlebar drags the window (not buttons or content).
        self._main = webview.create_window(
            "MagicPaste", _asset("main.html"),
            js_api=self._api,
            width=MAIN_W, height=MAIN_H, min_size=(620, 480),
            frameless=True, easy_drag=False,
            hidden=not show_main, background_color="#101014", resizable=True,
        )
        self._main_visible = show_main

        # Distinct title so we can find the toast's HWND (the main window is
        # also "MagicPaste") and strip it from the taskbar / Alt-Tab.
        self._toast = webview.create_window(
            "MagicPaste Toast", _asset("toast.html"),
            js_api=self._api,
            width=TOAST_W, height=TOAST_H,
            frameless=True, easy_drag=False, on_top=True,
            hidden=True, background_color="#101014", resizable=False,
        )

        self._main.events.closing += self._on_main_closing
        self._toast.events.closing += self._on_toast_closing

        self.state.add_listener(lambda _s: self.push_state())
        webview.start(self._on_loaded, gui="edgechromium", private_mode=False)

    def _on_loaded(self):
        self.push_i18n()
        self.push_state()
        # Replace the default python.exe taskbar/window icon with the brand .ico.
        threading.Timer(0.6, self._apply_window_icon).start()
        # Make the toast a tool window so it never gets a taskbar button.
        threading.Timer(0.8, self._hide_toast_from_taskbar).start()

    def _hide_toast_from_taskbar(self):
        """Strip the toast window's taskbar button + Alt-Tab entry (WS_EX_TOOLWINDOW)."""
        try:
            import ctypes
            from ctypes import wintypes
            user32 = ctypes.windll.user32
            user32.FindWindowW.restype = wintypes.HWND
            hwnd = user32.FindWindowW(None, "MagicPaste Toast")
            if not hwnd:
                return
            GWL_EXSTYLE = -20
            WS_EX_TOOLWINDOW = 0x00000080
            WS_EX_APPWINDOW = 0x00040000
            get_ = user32.GetWindowLongPtrW
            set_ = user32.SetWindowLongPtrW
            get_.restype = ctypes.c_ssize_t
            get_.argtypes = [wintypes.HWND, ctypes.c_int]
            set_.restype = ctypes.c_ssize_t
            set_.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_ssize_t]
            ex = get_(hwnd, GWL_EXSTYLE)
            ex = (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW
            set_(hwnd, GWL_EXSTYLE, ex)
        except Exception:  # noqa: BLE001
            pass

    def _apply_window_icon(self):
        """Set the MagicPaste .ico on the native window (taskbar + titlebar).

        While running under python.exe the OS shows the Python icon; this
        overrides it. The packaged .exe will also embed the icon at build time.
        """
        try:
            import ctypes
            from ctypes import wintypes

            ico = _asset_icon("magicpaste.ico")
            if not os.path.exists(ico):
                return
            user32 = ctypes.windll.user32
            # Find our top-level window by title.
            hwnd = user32.FindWindowW(None, "MagicPaste")
            if not hwnd:
                return
            IMAGE_ICON = 1
            LR_LOADFROMFILE = 0x00000010
            LR_DEFAULTSIZE = 0x00000040
            big = user32.LoadImageW(None, ico, IMAGE_ICON, 0, 0,
                                    LR_LOADFROMFILE | LR_DEFAULTSIZE)
            small = user32.LoadImageW(None, ico, IMAGE_ICON, 16, 16,
                                      LR_LOADFROMFILE)
            WM_SETICON = 0x0080
            if big:
                user32.SendMessageW(hwnd, WM_SETICON, 1, big)   # ICON_BIG
            if small:
                user32.SendMessageW(hwnd, WM_SETICON, 0, small)  # ICON_SMALL
            # Also set the AppUserModelID so the taskbar groups under our app.
            try:
                ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
                    "RedOrionStudio.MagicPaste"
                )
            except Exception:  # noqa: BLE001
                pass
        except Exception:  # noqa: BLE001
            pass

    def _on_main_closing(self):
        if self._quitting:
            return True
        self._main.hide()
        self._main_visible = False
        return False  # cancel the close — only hide

    def _on_toast_closing(self):
        if self._quitting:
            return True
        self._toast.hide()
        return False

    def quit(self):
        self._quitting = True
        for w in (self._main, self._toast):
            if w is not None:
                try:
                    w.destroy()
                except Exception:  # noqa: BLE001
                    pass

    # -- show / hide -------------------------------------------------------

    def show_main(self):
        if not self._main:
            return
        self.push_state()
        try:
            self._main.show()
            self._main.restore()
            self._main.on_top = True
            self._main.on_top = False
        except Exception:  # noqa: BLE001
            pass
        self._main_visible = True

    def hide_main(self):
        if self._main and self._main_visible:
            self._main.hide()
            self._main_visible = False

    def minimize_main(self):
        # Stay in the taskbar — just minimize, don't hide to tray.
        if self._main:
            try:
                self._main.minimize()
            except Exception:  # noqa: BLE001
                pass

    def toggle_main(self):
        if self._main_visible:
            self.hide_main()
        else:
            self.show_main()

    def show_toast(self, thumb_png: bytes | None):
        if not self.state.show_notifications:
            return
        lang = self._lang()
        snap = self.state.snapshot()
        self._show_toast({
            "msg": i18n.t("toast_ss_copied", lang),
            "sub": i18n.t("toast_from", lang, d=snap["device"]),
            "thumb": base64.b64encode(thumb_png).decode("ascii") if thumb_png else None,
        })

    def copy_history(self, item_id):
        """Re-copy an older received image (from History) to the clipboard."""
        lang = self._lang()
        data = self.state.history_image_bytes(item_id)
        if not data:
            self._show_toast({"msg": i18n.t("toast_img_unavailable", lang), "sub": "", "thumb": None})
            return
        try:
            from clipboard import set_clipboard_image
            set_clipboard_image(data)
            self._show_toast({
                "msg": i18n.t("toast_copied", lang),
                "sub": i18n.t("toast_press_ctrlv", lang),
                "thumb": None,
            })
        except Exception:  # noqa: BLE001
            self._show_toast({"msg": i18n.t("toast_img_unavailable", lang), "sub": "", "thumb": None})

    def show_pair_toast(self, device: str):
        # Feedback when a phone (re)pairs — shown regardless of the
        # notifications setting since it confirms a deliberate user action.
        lang = self._lang()
        self._show_toast({
            "msg": i18n.t("toast_device_connected", lang),
            "sub": i18n.t("toast_paired", lang, d=device),
            "thumb": None,
        })

    def _show_toast(self, payload: dict):
        if not self._toast:
            return
        sw, sh = self._screen()
        self._toast.move(sw - TOAST_W - _MARGIN, sh - TOAST_H - _TASKBAR - _MARGIN)
        try:
            self._toast.evaluate_js(
                f"window.mpRender && window.mpRender({json.dumps(payload)})"
            )
        except Exception:  # noqa: BLE001
            pass
        self._toast.show()
        if self._toast_hide_timer:
            self._toast_hide_timer.cancel()
        self._toast_hide_timer = threading.Timer(4.0, self._hide_toast)
        self._toast_hide_timer.daemon = True
        self._toast_hide_timer.start()

    def _hide_toast(self):
        if self._toast_hide_timer:
            self._toast_hide_timer.cancel()
            self._toast_hide_timer = None
        if self._toast:
            try:
                self._toast.hide()
            except Exception:  # noqa: BLE001
                pass

    # -- state push --------------------------------------------------------

    def _lang(self) -> str:
        return i18n.resolve(self.state.lang)

    def push_i18n(self):
        """Send the current language's strings to the page and apply them."""
        if self._main is None:
            return
        data = i18n.strings(self._lang())
        js = ("window.MP_I18N = " + json.dumps(data) + ";"
              " window.applyI18n && window.applyI18n();")
        try:
            self._main.evaluate_js(js)
        except Exception:  # noqa: BLE001
            pass

    def push_state(self):
        if self._main is None:
            return
        snap = self.state.snapshot()
        js = f"window.mpRender && window.mpRender({json.dumps(snap)})"
        try:
            self._main.evaluate_js(js)
        except Exception:  # noqa: BLE001
            pass
