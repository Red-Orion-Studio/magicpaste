"""Small PNG thumbnail generation for UI previews."""

from io import BytesIO

from PIL import Image


def make_thumb_png(image_bytes: bytes, max_w: int = 400, max_h: int = 540) -> bytes | None:
    """Return a PNG thumbnail of the given image, or None on failure.

    Sized large enough (~400x540) that the History grid cells (~170x227 on a
    HiDPI display) render crisp rather than upscaled/blurry. LANCZOS keeps the
    downscale sharp; JPEG-quality isn't a concern since we keep PNG for the
    striped/UI look but the source is already compressed.
    """
    try:
        img = Image.open(BytesIO(image_bytes))
        img = img.convert("RGB")
        img.thumbnail((max_w, max_h), Image.LANCZOS)
        out = BytesIO()
        img.save(out, "PNG")
        return out.getvalue()
    except Exception:  # noqa: BLE001
        return None
