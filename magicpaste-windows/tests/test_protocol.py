"""Unit tests for the MagicPaste wire protocol (protocol.py)."""
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import protocol as P


# ── Header round-trip ─────────────────────────────────────────────────────────

def test_header_magic():
    hdr = P.build_header(P.MSG_PING, 0)
    magic, *_ = struct.unpack(">IIII16s", hdr)
    assert magic == P.MAGIC


def test_header_size():
    hdr = P.build_header(P.MSG_PING, 0)
    assert len(hdr) == P.HEADER_SIZE


def test_header_roundtrip():
    token = b"\x01\x02\x03\x04" * 4
    hdr = P.build_header(P.MSG_IMAGE, 1024, token)
    msg_type, payload_len, tok = P.parse_header(hdr)
    assert msg_type == P.MSG_IMAGE
    assert payload_len == 1024
    assert tok == token


def test_header_zero_token_default():
    hdr = P.build_header(P.MSG_PING, 0)
    _, _, tok = P.parse_header(hdr)
    assert tok == b"\x00" * P.TOKEN_SIZE


def test_parse_header_bad_magic():
    bad = b"\x00" * P.HEADER_SIZE
    try:
        P.parse_header(bad)
        assert False, "should raise"
    except ValueError as e:
        assert "magic" in str(e).lower()


def test_parse_header_wrong_length():
    try:
        P.parse_header(b"\x00" * 10)
        assert False, "should raise"
    except ValueError:
        pass


# ── Image payload round-trip ──────────────────────────────────────────────────

def test_image_payload_roundtrip():
    raw = b"\xff\xd8\xff" + b"\x00" * 100  # fake JPEG bytes
    payload = P.build_image_payload(P.IMG_JPEG, 1920, 1080, raw)
    fmt, w, h, data = P.parse_image_payload(payload)
    assert fmt == P.IMG_JPEG
    assert w == 1920
    assert h == 1080
    assert data == raw


def test_image_payload_too_short():
    try:
        P.parse_image_payload(b"\x00" * 5)
        assert False, "should raise"
    except ValueError:
        pass


# ── Full message ──────────────────────────────────────────────────────────────

def test_full_image_message():
    token = b"A" * P.TOKEN_SIZE
    raw = b"\x89PNG" + b"\x00" * 50
    msg = P.build_image_message(P.IMG_PNG, 800, 600, raw, token)

    assert len(msg) > P.HEADER_SIZE
    msg_type, payload_len, tok = P.parse_header(msg[:P.HEADER_SIZE])
    assert msg_type == P.MSG_IMAGE
    assert payload_len == len(msg) - P.HEADER_SIZE
    assert tok == token

    fmt, w, h, data = P.parse_image_payload(msg[P.HEADER_SIZE:])
    assert fmt == P.IMG_PNG
    assert w == 800
    assert h == 600
    assert data == raw


def test_simple_message_ping():
    msg = P.build_simple_message(P.MSG_PING)
    assert len(msg) == P.HEADER_SIZE
    msg_type, payload_len, _ = P.parse_header(msg)
    assert msg_type == P.MSG_PING
    assert payload_len == 0


def test_simple_message_with_payload():
    payload = b"HelloWorld"
    msg = P.build_simple_message(P.MSG_PAIR_REQUEST, payload)
    msg_type, payload_len, _ = P.parse_header(msg[:P.HEADER_SIZE])
    assert msg_type == P.MSG_PAIR_REQUEST
    assert payload_len == len(payload)
    assert msg[P.HEADER_SIZE:] == payload


# ── Token normalisation ───────────────────────────────────────────────────────

def test_token_too_long_is_truncated():
    long_token = b"X" * 32
    hdr = P.build_header(P.MSG_PING, 0, long_token)
    _, _, tok = P.parse_header(hdr)
    assert len(tok) == P.TOKEN_SIZE
    assert tok == b"X" * P.TOKEN_SIZE


def test_token_too_short_is_padded():
    short_token = b"AB"
    hdr = P.build_header(P.MSG_PING, 0, short_token)
    _, _, tok = P.parse_header(hdr)
    assert tok == b"AB" + b"\x00" * (P.TOKEN_SIZE - 2)
