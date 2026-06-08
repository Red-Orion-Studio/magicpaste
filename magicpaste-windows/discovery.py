"""
mDNS / zeroconf service advertisement.

Advertises the MagicPaste server on the local network as
`_magicpaste._tcp.local.` so the Android app can discover the PC's IP
automatically (no manual IP typing required).
"""

import socket
import logging

import protocol

try:
    from zeroconf import ServiceInfo, Zeroconf
    _HAS_ZEROCONF = True
except ImportError:
    ServiceInfo = Zeroconf = None
    _HAS_ZEROCONF = False

log = logging.getLogger("magicpaste.discovery")


def get_local_ip() -> str:
    """Best-effort local LAN IP address."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Doesn't actually send packets; just picks the right interface.
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


class DiscoveryAdvertiser:
    def __init__(self, port: int = protocol.DEFAULT_PORT, instance_name: str = "MagicPaste"):
        self.port = port
        self.instance_name = instance_name
        self._zc = None
        self._info = None

    def start(self):
        if not _HAS_ZEROCONF:
            log.warning("zeroconf not installed; mDNS discovery disabled")
            return
        ip = get_local_ip()
        hostname = socket.gethostname()
        self._info = ServiceInfo(
            protocol.SERVICE_TYPE,
            f"{self.instance_name}._magicpaste._tcp.local.",
            addresses=[socket.inet_aton(ip)],
            port=self.port,
            properties={"version": "1.0", "host": hostname},
            server=f"{hostname}.local.",
        )
        self._zc = Zeroconf()
        self._zc.register_service(self._info)
        log.info("Advertised %s at %s:%d via mDNS", self.instance_name, ip, self.port)

    def stop(self):
        if self._zc and self._info:
            try:
                self._zc.unregister_service(self._info)
            finally:
                self._zc.close()
        self._zc = None
        self._info = None
