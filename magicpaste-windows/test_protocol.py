"""Round-trip tests for the MagicPaste protocol (no Windows deps needed).

Run with:  python -m pytest test_protocol.py   (or)   python test_protocol.py
"""

import protocol


def test_header_roundtrip():
    raw = protocol.build_header(protocol.MSG_IMAGE, 1234)
    msg_type, payload_len, token = protocol.parse_header(raw)
    assert msg_type == protocol.MSG_IMAGE
    assert payload_len == 1234
    assert token == b"\x00" * protocol.TOKEN_SIZE
    assert len(raw) == protocol.HEADER_SIZE


def test_token_roundtrip():
    tok = bytes(range(protocol.TOKEN_SIZE))
    raw = protocol.build_header(protocol.MSG_PING, 0, tok)
    _, _, parsed = protocol.parse_header(raw)
    assert parsed == tok


def test_bad_magic_rejected():
    bad = b"\x00" * protocol.HEADER_SIZE
    try:
        protocol.parse_header(bad)
    except ValueError:
        return
    raise AssertionError("expected ValueError for bad magic")


def test_image_message_roundtrip():
    body = b"\x89PNG fake image bytes"
    tok = b"\xab" * protocol.TOKEN_SIZE
    msg = protocol.build_image_message(protocol.IMG_PNG, 800, 600, body, tok)
    msg_type, payload_len, token = protocol.parse_header(msg[: protocol.HEADER_SIZE])
    assert msg_type == protocol.MSG_IMAGE
    assert token == tok
    payload = msg[protocol.HEADER_SIZE :]
    assert len(payload) == payload_len
    fmt, w, h, raw = protocol.parse_image_payload(payload)
    assert (fmt, w, h, raw) == (protocol.IMG_PNG, 800, 600, body)


if __name__ == "__main__":
    test_header_roundtrip()
    test_token_roundtrip()
    test_bad_magic_rejected()
    test_image_message_roundtrip()
    print("All protocol tests passed.")
