"""
MagicPaste — Windows client entry point.

Wires together:
  - AppState        : shared status / device / history / settings
  - MagicPasteServer: TCP listener (background thread)
  - DiscoveryAdvertiser : mDNS so the phone can find this PC
  - Tray            : status tray icon (background thread, run_detached)
  - WebUI           : glassmorphism popup / settings / toast (OWNS main thread)

pywebview must run on the main thread, so it is started LAST and blocks until
the user quits. Everything else runs on background threads.

Usage:
    python magicpaste.py [--port PORT] [--no-ui] [--verbose]
"""

import argparse
import logging
import sys
import threading

import protocol
from server import MagicPasteServer
from discovery import DiscoveryAdvertiser, get_local_ip
from state import AppState
from thumbs import make_thumb_png

log = logging.getLogger("magicpaste")


# A fixed localhost port used only for the single-instance "show the window"
# control channel (separate from the screenshot data port).
_CONTROL_PORT = 49199


def _signal_existing_instance(cmd: bytes) -> bool:
    """Send a one-word command to a running instance's control port.
    Returns True if an instance was reached."""
    import socket
    try:
        with socket.create_connection(("127.0.0.1", _CONTROL_PORT), timeout=0.6) as s:
            s.sendall(cmd)
        return True
    except OSError:
        return False


def _ping_existing_instance() -> bool:
    """If MagicPaste is already running, tell it to show its window."""
    return _signal_existing_instance(b"SHOW")


def _start_show_listener(on_show, on_quit):
    """Listen on the control port: 'SHOW' raises the window, 'QUIT' exits
    cleanly (so the tray icon is removed instead of left as a ghost)."""
    import socket

    def loop():
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            srv.bind(("127.0.0.1", _CONTROL_PORT))
            srv.listen(5)
        except OSError:
            return  # someone else owns it; ignore
        while True:
            try:
                conn, _ = srv.accept()
                with conn:
                    cmd = conn.recv(16)
                if cmd.strip().upper().startswith(b"QUIT"):
                    on_quit()
                    break
                on_show()
            except OSError:
                break

    threading.Thread(target=loop, daemon=True).start()


def main():
    parser = argparse.ArgumentParser(description="MagicPaste Windows client")
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument("--no-ui", action="store_true", help="run headless (no tray/windows)")
    parser.add_argument("--background", action="store_true",
                        help="start hidden (tray + service only); used for autostart")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--quit", action="store_true",
                        help="tell a running instance to exit cleanly, then exit")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    # `--quit`: ask a running instance to shut down cleanly, then exit.
    if args.quit:
        ok = _signal_existing_instance(b"QUIT")
        print("Quit signal sent." if ok else "No running instance found.")
        return

    # Single instance: if one is already running, just raise its window & exit.
    if not args.no_ui and _ping_existing_instance():
        log.info("MagicPaste already running — asked it to show its window.")
        return

    state = AppState()
    if args.port:
        state.update_settings(port=args.port)
    port = state.port

    # Reflect the real registry autostart state in the UI toggle.
    if not args.no_ui:
        try:
            from tray import is_autostart_enabled
            state.start_with_windows = is_autostart_enabled()
        except Exception:  # noqa: BLE001
            pass

    # --- server callbacks -------------------------------------------------
    ui_holder = {"ui": None}

    def on_pair_request(device_name: str, authed: bool) -> bool:
        # Accept when: the phone already holds a valid token (authed), no device
        # is paired yet (first-time setup), or the user opened the "Allow new
        # device" window. Otherwise an unknown device is refused so it can't grab
        # the token off the LAN while one is already paired.
        if authed or not state.paired or state.pairing_open():
            state.pair(device=device_name)
            ui = ui_holder["ui"]
            if ui:
                ui.show_pair_toast(device_name)
            return True
        log.warning("Refused pairing from unknown device %r "
                    "(locked — use 'Allow new device' on the PC)", device_name)
        return False

    def on_activity(ip: str):
        # Ping or any message -> phone is connected right now.
        state.mark_activity(ip=ip)

    def on_image(width: int, height: int, raw: bytes):
        thumb = make_thumb_png(raw)
        state.mark_activity()
        state.add_received(_default_name(), width, height, thumb, image_bytes=raw)
        ui = ui_holder["ui"]
        if ui:
            ui.show_toast(thumb)

    def on_status(message: str):
        log.info(message)

    server = MagicPasteServer(
        port=port,
        on_image=on_image,
        on_pair_request=on_pair_request,
        on_status=on_status,
        on_activity=on_activity,
        get_token=state.token_bytes,
        get_paused=lambda: state.paused,
    )
    advertiser = DiscoveryAdvertiser(port=port)

    try:
        server.start()
    except OSError as e:
        log.error("Could not start server on port %d: %s", port, e)
        sys.exit(1)
    advertiser.start()

    ip = get_local_ip()
    # On startup we don't yet know if the phone is reachable; keep the device
    # IP but mark not-connected until its first ping arrives. `paired` is loaded
    # from disk, so if a device was paired before we show the device view (not QR).
    state.set_connected(False, ip=state.device_ip or ip)
    log.info("MagicPaste ready. Pair your phone with %s:%d", ip, port)

    # Watchdog: if the phone stops pinging, drop to "disconnected" after 20s.
    def _watchdog():
        while True:
            import time
            time.sleep(5)
            state.check_timeout(20)

    threading.Thread(target=_watchdog, daemon=True).start()

    def shutdown():
        log.info("Shutting down…")
        advertiser.stop()
        server.stop()

    if args.no_ui:
        try:
            import time
            print(f"\nMagicPaste running (headless). Pair with: {ip}:{port}")
            print("Press Ctrl+C to quit.\n")
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            shutdown()
        return

    # --- UI (tray + webview) ---------------------------------------------
    from tray import Tray
    from webui import WebUI

    def toggle_pause():
        state.set_paused(not state.paused)

    def forget_device():
        state.unpair()

    def setting_changed(key, value):
        # The "Start with Windows" toggle must write the registry Run key.
        if key == "startWithWindows":
            try:
                from tray import set_autostart
                set_autostart(bool(value))
            except Exception:  # noqa: BLE001
                log.exception("set_autostart failed")

    ui = WebUI(
        state,
        callbacks={
            "toggle_pause": toggle_pause,
            "forget_device": forget_device,
            "setting_changed": setting_changed,
        },
    )
    ui_holder["ui"] = ui

    def _on_quit():
        # Stop the tray first so its icon is removed cleanly (no ghost), then
        # shut down the server and close the windows.
        try:
            tray.stop()
        except Exception:  # noqa: BLE001
            pass
        shutdown()
        ui.quit()

    tray = Tray(
        state,
        on_left_click=lambda: ui.show_main(),
        on_settings=lambda: ui.show_main(),
        on_quit=_on_quit,
    )

    # A tiny localhost control socket lets a second launch ("open the app"
    # while the background instance is already running) raise the existing
    # window instead of starting a duplicate process that would clash on the
    # TCP port.
    _start_show_listener(lambda: ui.show_main(), _on_quit)

    # Start tray on a background thread (run_detached), then block on webview.
    threading.Thread(target=tray.start, daemon=True).start()
    try:
        # --background launches hidden (autostart); a normal launch shows the window.
        ui.start(show_main=not args.background)
    finally:
        shutdown()


def _default_name() -> str:
    from datetime import datetime
    return "Screenshot_" + datetime.now().strftime("%Y%m%d_%H%M%S") + ".png"


if __name__ == "__main__":
    main()
