"""
Windows clipboard handler.

Places a received image into the Windows clipboard so the user can paste it
with Ctrl+V anywhere.

The Windows clipboard is a single-writer system-wide resource — at any
given moment another process (Discord, browser, screenshot tool, even
Explorer's "copy file") may be holding it open. Calling OpenClipboard
when it's busy raises `pywintypes.error: (5, 'OpenClipboard', 'Access
denied.')`. That's why this module retries with a short backoff
instead of giving up on the first try: a single failed SetClipboard
call would otherwise leave the user pasting the *previous* image
forever, since the new bytes never made it into the system buffer.
"""

import time
from io import BytesIO

from PIL import Image

try:
    import win32clipboard
    import pywintypes
    _HAS_WIN32 = True
except ImportError:  # allows importing on non-Windows for tests/linting
    win32clipboard = None
    pywintypes = None
    _HAS_WIN32 = False


# Tuneables for the retry loop. 10 attempts × 50 ms ≈ half a second
# of worst-case latency before we give up — well within "user pressed
# Ctrl+V a second later" UX.
_MAX_OPEN_ATTEMPTS = 10
_OPEN_BACKOFF_S = 0.05


def _open_clipboard_with_retry() -> None:
    """OpenClipboard, retrying briefly while another process holds it.

    Raises RuntimeError after [_MAX_OPEN_ATTEMPTS] failed attempts so
    the caller can log + skip without leaving the clipboard in an
    inconsistent state.
    """
    last_err: Exception | None = None
    for attempt in range(_MAX_OPEN_ATTEMPTS):
        try:
            win32clipboard.OpenClipboard()
            return
        except pywintypes.error as e:  # type: ignore[union-attr]
            last_err = e
            time.sleep(_OPEN_BACKOFF_S)
    raise RuntimeError(
        f"OpenClipboard busy after {_MAX_OPEN_ATTEMPTS} attempts: {last_err}"
    )


def set_clipboard_image(image_bytes: bytes) -> tuple[int, int]:
    """Decode image_bytes and place it on the Windows clipboard as CF_DIB.

    Returns (width, height) of the image placed on the clipboard.
    Raises RuntimeError if win32clipboard is unavailable or the
    clipboard stayed busy past the retry budget.
    """
    if not _HAS_WIN32:
        raise RuntimeError(
            "win32clipboard not available. Install pywin32 and run on Windows."
        )

    image = Image.open(BytesIO(image_bytes))
    width, height = image.size

    output = BytesIO()
    # CF_DIB expects a BMP without the 14-byte BMP file header.
    image.convert("RGB").save(output, "BMP")
    bmp_data = output.getvalue()[14:]

    _open_clipboard_with_retry()
    try:
        # EmptyClipboard MUST be called before SetClipboardData,
        # otherwise the new entry coexists with the previous owner's
        # data and some apps prefer the older format on paste.
        win32clipboard.EmptyClipboard()
        win32clipboard.SetClipboardData(win32clipboard.CF_DIB, bmp_data)
    finally:
        # CloseClipboard releases the system lock regardless of
        # whether SetClipboardData raised, so a downstream OpenClipboard
        # by another process isn't blocked indefinitely.
        win32clipboard.CloseClipboard()

    return width, height
