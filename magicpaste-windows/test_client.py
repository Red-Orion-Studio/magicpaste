"""
Test client for MagicPaste — simulates the Android phone from your PC.

Use this to verify the whole Windows side WITHOUT a phone:
1. In one terminal:   python magicpaste.py
2. In another:        python test_client.py
Then press Ctrl+V somewhere (e.g. Paint, Word, a chat) to confirm the image
arrived on the clipboard.

You can pass your own image:
    python test_client.py --image path\to\screenshot.png --host 127.0.0.1
If no image is given, a colorful test image is generated automatically.
"""

import argparse
import socket
from io import BytesIO

from PIL import Image, ImageDraw

import protocol


def make_test_image(width: int = 600, height: int = 400) -> bytes:
    """Generate a recognizable PNG so you can confirm paste worked."""
    img = Image.new("RGB", (width, height), (15, 23, 42))
    d = ImageDraw.Draw(img)
    for i in range(0, width, 20):
        d.line([(i, 0), (i, height)], fill=(30, 41, 59), width=1)
    d.rectangle([40, 40, width - 40, height - 40], outline=(59, 130, 246), width=4)
    d.text((80, height // 2 - 10), "MagicPaste test image — paste worked!", fill=(226, 232, 240))
    out = BytesIO()
    img.save(out, "PNG")
    return out.getvalue()


def load_image(path: str):
    img = Image.open(path)
    width, height = img.size
    fmt = protocol.IMG_JPEG if img.format == "JPEG" else protocol.IMG_PNG
    with open(path, "rb") as f:
        raw = f.read()
    return raw, width, height, fmt


def main():
    parser = argparse.ArgumentParser(description="MagicPaste test client")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=protocol.DEFAULT_PORT)
    parser.add_argument("--image", help="path to an image to send (PNG/JPEG)")
    parser.add_argument("--device-name", default="Test Phone")
    parser.add_argument("--pair", action="store_true", help="send a PAIR_REQUEST first")
    parser.add_argument("--token", default=None, help="hex auth token (from the PC's QR)")
    args = parser.parse_args()

    if args.image:
        raw, width, height, fmt = load_image(args.image)
    else:
        raw = make_test_image()
        width, height, fmt = 600, 400, protocol.IMG_PNG

    token = bytes.fromhex(args.token) if args.token else None

    print(f"Connecting to {args.host}:{args.port} ...")
    with socket.create_connection((args.host, args.port), timeout=5) as s:
        if args.pair:
            s.sendall(
                protocol.build_simple_message(
                    protocol.MSG_PAIR_REQUEST, args.device_name.encode("utf-8"), token
                )
            )
            resp = s.recv(protocol.HEADER_SIZE)
            msg_type, plen, _ = protocol.parse_header(resp)
            payload = s.recv(plen) if plen else b""
            if msg_type == protocol.MSG_PAIR_ACCEPT:
                if payload:
                    import json
                    info = json.loads(payload.decode("utf-8"))
                    if info.get("token"):
                        token = bytes.fromhex(info["token"])
                    print(f"Pairing accepted! pc={info.get('name')} token={token.hex() if token else None}")
                else:
                    print("Pairing accepted!")
            else:
                print("Pairing failed")

        print(f"Sending image {width}x{height} ({len(raw)} bytes) ...")
        s.sendall(protocol.build_image_message(fmt, width, height, raw, token))
        print("Sent. Now press Ctrl+V somewhere on Windows to verify.")


if __name__ == "__main__":
    main()
