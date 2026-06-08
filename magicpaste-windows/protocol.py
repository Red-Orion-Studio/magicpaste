"""
MagicPaste wire protocol.

Shared definitions for the binary TCP protocol used between the Android app
and the Windows client. See SPEC.md section 5 for the authoritative description.

Header (32 bytes, big-endian):
    Bytes 0-3   : Magic number 0x534E4150 ("SNAP")
    Bytes 4-7   : Message type (uint32)
    Bytes 8-11  : Payload length in bytes (uint32)
    Bytes 12-15 : Reserved (0x00000000)
    Bytes 16-31 : Auth token (16 bytes). The phone learns this secret when it
                  pairs (from the QR, or returned in PAIR_ACCEPT). The PC
                  rejects any non-pairing message whose token doesn't match.
                  Replies and unauthenticated requests send 16 zero bytes.

IMAGE payload prefix (12 bytes, big-endian) followed by raw image bytes:
    Bytes 0-3   : Image format (uint32) -> 0x01 PNG, 0x02 JPEG
    Bytes 4-7   : Image width  (uint32)
    Bytes 8-11  : Image height (uint32)
    Bytes 12+   : Raw image file bytes
"""

import struct

# 0x534E4150 == b"SNAP".
MAGIC = 0x534E4150

HEADER_SIZE = 32
HEADER_FORMAT = ">IIII16s"  # magic, type, payload_len, reserved, token(16)
TOKEN_SIZE = 16
_ZERO_TOKEN = b"\x00" * TOKEN_SIZE

# Message types
MSG_IMAGE = 0x01
MSG_PING = 0x02
MSG_PONG = 0x03
MSG_PAIR_REQUEST = 0x04
MSG_PAIR_ACCEPT = 0x05
# Reply to an IMAGE: 1-byte payload, 1 = copied to clipboard, 0 = dropped
# (paused or clipboard error). Lets the phone beep/log only on real delivery.
MSG_IMAGE_ACK = 0x06
# Explicit pairing refusal (PC already paired and not in "allow new device"
# mode). Lets the phone tell the user immediately instead of timing out.
MSG_PAIR_REJECT = 0x07

MSG_NAMES = {
    MSG_IMAGE: "IMAGE",
    MSG_PING: "PING",
    MSG_PONG: "PONG",
    MSG_PAIR_REQUEST: "PAIR_REQUEST",
    MSG_PAIR_ACCEPT: "PAIR_ACCEPT",
    MSG_IMAGE_ACK: "IMAGE_ACK",
    MSG_PAIR_REJECT: "PAIR_REJECT",
}

# Image formats
IMG_PNG = 0x01
IMG_JPEG = 0x02

# Default TCP port (configurable)
DEFAULT_PORT = 49152

# mDNS service type
SERVICE_TYPE = "_magicpaste._tcp.local."


def _norm_token(token: bytes | None) -> bytes:
    """Coerce a token to exactly TOKEN_SIZE bytes (zero-padded / truncated)."""
    if not token:
        return _ZERO_TOKEN
    return token[:TOKEN_SIZE].ljust(TOKEN_SIZE, b"\x00")


def build_header(msg_type: int, payload_len: int, token: bytes | None = None) -> bytes:
    """Build a 32-byte message header carrying an optional 16-byte auth token."""
    return struct.pack(HEADER_FORMAT, MAGIC, msg_type, payload_len, 0, _norm_token(token))


def parse_header(data: bytes):
    """Parse a 32-byte header. Returns (msg_type, payload_len, token).

    Raises ValueError if the magic number does not match.
    """
    if len(data) != HEADER_SIZE:
        raise ValueError(f"header must be {HEADER_SIZE} bytes, got {len(data)}")
    magic, msg_type, payload_len, _reserved, token = struct.unpack(HEADER_FORMAT, data)
    if magic != MAGIC:
        raise ValueError(f"bad magic number: 0x{magic:08X}")
    return msg_type, payload_len, token


def build_image_payload(image_format: int, width: int, height: int, raw: bytes) -> bytes:
    """Build an IMAGE message payload (12-byte prefix + raw bytes)."""
    return struct.pack(">III", image_format, width, height) + raw


def parse_image_payload(payload: bytes):
    """Parse an IMAGE payload. Returns (image_format, width, height, raw_bytes)."""
    if len(payload) < 12:
        raise ValueError("image payload too short")
    image_format, width, height = struct.unpack(">III", payload[:12])
    return image_format, width, height, payload[12:]


def build_image_message(
    image_format: int, width: int, height: int, raw: bytes, token: bytes | None = None
) -> bytes:
    """Build a full IMAGE message (header + payload) ready to send."""
    payload = build_image_payload(image_format, width, height, raw)
    return build_header(MSG_IMAGE, len(payload), token) + payload


def build_simple_message(msg_type: int, payload: bytes = b"", token: bytes | None = None) -> bytes:
    """Build any header-only / small-payload message (PING, PAIR_*, etc.)."""
    return build_header(msg_type, len(payload), token) + payload
