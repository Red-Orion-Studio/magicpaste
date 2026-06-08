"""
TCP server for MagicPaste.

Listens for incoming connections from the Android app, parses MagicPaste
protocol messages, and dispatches them (images -> clipboard, pairing, ping).
"""

import hmac
import json
import socket
import threading
import logging

import protocol
from clipboard import set_clipboard_image

log = logging.getLogger("magicpaste.server")


def _recv_exactly(conn: socket.socket, n: int) -> bytes:
    """Read exactly n bytes from conn, or raise ConnectionError on EOF."""
    chunks = []
    remaining = n
    while remaining > 0:
        chunk = conn.recv(min(remaining, 65536))
        if not chunk:
            raise ConnectionError("connection closed while reading")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


class MagicPasteServer:
    """Threaded TCP server.

    Callbacks (all optional):
        on_image(width, height)             -> called after an image hits clipboard
        on_pair_request(device_name, authed)-> return True to accept pairing
        on_status(message)                  -> human-readable status updates
        get_token()                         -> expected 16-byte token (or None)
    """

    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = protocol.DEFAULT_PORT,
        on_image=None,
        on_pair_request=None,
        on_status=None,
        on_activity=None,
        get_token=None,
        get_paused=None,
    ):
        self.host = host
        self.port = port
        self.on_image = on_image
        self.on_pair_request = on_pair_request
        self.on_status = on_status
        # Called with the peer ip on ANY inbound message (ping/image/pair) so
        # the UI can keep a live "connected" indicator from the phone's pings.
        self.on_activity = on_activity
        # Returns the secret the phone must present; None until first run.
        self.get_token = get_token
        # Returns True while receiving is paused (images are dropped).
        self.get_paused = get_paused

        self._sock: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._running = threading.Event()

    # -- lifecycle ---------------------------------------------------------

    def start(self):
        """Start listening in a background thread."""
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind((self.host, self.port))
        self._sock.listen(5)
        self._running.set()
        self._thread = threading.Thread(target=self._accept_loop, daemon=True)
        self._thread.start()
        self._status(f"Listening on {self.host}:{self.port}")

    def stop(self):
        self._running.clear()
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
        self._status("Server stopped")

    # -- internals ---------------------------------------------------------

    def _status(self, message: str):
        log.info(message)
        if self.on_status:
            try:
                self.on_status(message)
            except Exception:  # noqa: BLE001 - never let a callback kill the loop
                log.exception("on_status callback failed")

    def _accept_loop(self):
        while self._running.is_set():
            try:
                conn, addr = self._sock.accept()
            except OSError:
                break  # socket closed during stop()
            threading.Thread(
                target=self._handle_client, args=(conn, addr), daemon=True
            ).start()

    def _handle_client(self, conn: socket.socket, addr):
        peer = f"{addr[0]}:{addr[1]}"
        log.info("Connection from %s", peer)
        try:
            with conn:
                while self._running.is_set():
                    header = _recv_exactly(conn, protocol.HEADER_SIZE)
                    try:
                        msg_type, payload_len, token = protocol.parse_header(header)
                    except ValueError as e:
                        log.warning("Rejecting %s: %s", peer, e)
                        return
                    payload = (
                        _recv_exactly(conn, payload_len) if payload_len else b""
                    )
                    if not self._dispatch(conn, peer, msg_type, payload, token):
                        return  # auth failure -> drop the connection
        except ConnectionError:
            log.info("Connection from %s closed", peer)
        except Exception:  # noqa: BLE001
            log.exception("Error handling client %s", peer)

    def _send_ack(self, conn, status: int):
        """Tell the phone whether the image was copied (1) or dropped (0)."""
        try:
            conn.sendall(
                protocol.build_simple_message(protocol.MSG_IMAGE_ACK, bytes([status]))
            )
        except OSError:
            pass

    def _authed(self, token: bytes) -> bool:
        """Constant-time check of a message token against the expected secret."""
        expected = self.get_token() if self.get_token else None
        if not expected:
            # No secret configured yet (very first run before any pairing):
            # accept so the user can complete setup. Once paired, a token
            # always exists and this branch never runs again.
            return True
        return hmac.compare_digest(token, protocol._norm_token(expected))

    def _dispatch(self, conn, peer, msg_type, payload, token) -> bool:
        """Handle one message. Returns False if the connection should be dropped."""
        name = protocol.MSG_NAMES.get(msg_type, f"0x{msg_type:02X}")
        log.debug("Message %s from %s (%d bytes)", name, peer, len(payload))

        authed = self._authed(token)

        # PAIR_REQUEST is the one message allowed without a valid token: it's how
        # a brand-new phone bootstraps. Everything else is rejected outright so a
        # random device on the LAN can't push to the clipboard.
        if msg_type != protocol.MSG_PAIR_REQUEST and not authed:
            log.warning("Rejecting unauthenticated %s from %s", name, peer)
            return False

        # Mark the phone alive on real traffic — but NOT on a PAIR_REQUEST.
        # mark_activity() flips paired=True, which would otherwise trip the
        # trust-on-first-use gate below and make us refuse the very pairing
        # that's in progress. A successful pair sets connected on its own.
        if self.on_activity and msg_type != protocol.MSG_PAIR_REQUEST:
            try:
                self.on_activity(peer.rsplit(":", 1)[0])
            except Exception:  # noqa: BLE001
                log.exception("on_activity callback failed")

        if msg_type == protocol.MSG_IMAGE:
            # Honour the "pause" toggle — drop the image (clipboard/history
            # untouched) and tell the phone so it doesn't beep/log it.
            if self.get_paused and self.get_paused():
                self._status("Paused — screenshot ignored")
                self._send_ack(conn, 0)
                return True
            fmt, width, height, raw = protocol.parse_image_payload(payload)
            # Wrap the clipboard write so a transient Windows error
            # (busy clipboard, decode failure on a half-received image)
            # doesn't kill the entire client connection — the Android
            # side would otherwise have to reconnect for every retry.
            try:
                set_clipboard_image(raw)
                self._status(f"Screenshot copied to clipboard ({width}x{height})")
                if self.on_image:
                    try:
                        self.on_image(width, height, raw)
                    except Exception:  # noqa: BLE001
                        log.exception("on_image callback failed")
                self._send_ack(conn, 1)
            except Exception as e:  # noqa: BLE001
                log.exception("set_clipboard_image failed for %dx%d", width, height)
                self._status(f"Clipboard write failed: {e}")
                self._send_ack(conn, 0)

        elif msg_type == protocol.MSG_PING:
            conn.sendall(protocol.build_simple_message(protocol.MSG_PONG))

        elif msg_type == protocol.MSG_PAIR_REQUEST:
            device_name = payload.decode("utf-8", errors="replace")
            # Already-known phones (valid token, e.g. paired via QR) are always
            # welcome. An unknown device is only accepted under the TOFU rule the
            # callback enforces (first-time setup) so it can't hijack an existing
            # pairing or silently grab the token.
            accepted = True
            if not authed and self.on_pair_request:
                try:
                    accepted = bool(self.on_pair_request(device_name, authed))
                except Exception:  # noqa: BLE001
                    log.exception("on_pair_request callback failed")
                    accepted = False
            elif authed and self.on_pair_request:
                # Refresh device name / connected state for the known phone.
                try:
                    self.on_pair_request(device_name, authed)
                except Exception:  # noqa: BLE001
                    log.exception("on_pair_request callback failed")
            if accepted:
                # Hand the phone the secret (so it can authenticate from now on)
                # plus this PC's name so the phone can show "Connected to <PC>".
                tok = self.get_token() if self.get_token else None
                info = {
                    "token": tok.hex() if tok else "",
                    "name": socket.gethostname(),
                }
                conn.sendall(
                    protocol.build_simple_message(
                        protocol.MSG_PAIR_ACCEPT,
                        json.dumps(info).encode("utf-8"),
                    )
                )
                self._status(f"Paired with {device_name}")
            else:
                # Tell the phone right away so it can prompt the user to open
                # "Allow new device" on the PC (instead of timing out silently).
                try:
                    conn.sendall(protocol.build_simple_message(protocol.MSG_PAIR_REJECT))
                except OSError:
                    pass
                self._status(f"Rejected pairing from {device_name}")

        else:
            log.warning("Unknown message type from %s: %s", peer, name)

        return True
