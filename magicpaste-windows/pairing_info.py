"""
Pairing info for the Windows UI: the PC's LAN address + a scannable QR code.

The Android app's pairing screen scans this QR (or the user types the IP) to
learn where to send screenshots. The QR encodes "<ip>:<port>?tk=<token>",
matching the format PairingService.parseAddress() expects on the phone. The
token lets the phone authenticate every message; the displayed text address
omits it so a shared screenshot of the window doesn't leak the secret.
"""

import base64
from io import BytesIO

from discovery import get_local_ip

try:
    import qrcode
    _HAS_QR = True
except ImportError:
    qrcode = None
    _HAS_QR = False


def pairing_address(port: int) -> str:
    """Human-readable address shown in the UI (no secret)."""
    return f"{get_local_ip()}:{port}"


def pairing_qr_data(port: int, token: str | None) -> str:
    """Data encoded in the QR: address plus the auth token the phone needs."""
    addr = pairing_address(port)
    return f"{addr}?tk={token}" if token else addr


def qr_png_b64(data: str) -> str | None:
    """Return a base64-encoded PNG QR code for `data`, or None if unavailable."""
    if not _HAS_QR:
        return None
    try:
        qr = qrcode.QRCode(border=2, box_size=8)
        qr.add_data(data)
        qr.make(fit=True)
        img = qr.make_image(fill_color="#101014", back_color="white")
        buf = BytesIO()
        img.save(buf, "PNG")
        return base64.b64encode(buf.getvalue()).decode("ascii")
    except Exception:  # noqa: BLE001
        return None
