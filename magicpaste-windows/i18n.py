"""
Lightweight en/es localization for the Windows app.

Default follows the Windows UI language (Spanish -> Spanish, else English),
overridable by the user (System/EN/ES). The HTML is filled via data-i18n keys
(see assets/main.html); Python-built strings (toasts) use t().
"""


def _system_lang() -> str:
    try:
        import ctypes
        buf = ctypes.create_unicode_buffer(85)
        ctypes.windll.kernel32.GetUserDefaultLocaleName(buf, 85)
        return 'es' if buf.value.lower().startswith('es') else 'en'
    except Exception:  # noqa: BLE001
        return 'en'


def resolve(mode: str) -> str:
    """mode: 'system' | 'en' | 'es' -> actual language code."""
    return mode if mode in ('en', 'es') else _system_lang()


def strings(lang: str) -> dict:
    """Flat {key: text} for the given language, for the HTML layer."""
    return {k: v.get(lang, v['en']) for k, v in _S.items()}


def t(key: str, lang: str, **args) -> str:
    e = _S.get(key, {})
    s = e.get(lang) or e.get('en') or key
    for k, val in args.items():
        s = s.replace('{' + k + '}', str(val))
    return s


_S = {
    # sidebar / pages
    'status': {'en': 'Status', 'es': 'Estado'},
    'history': {'en': 'History', 'es': 'Historial'},
    'settings': {'en': 'Settings', 'es': 'Ajustes'},
    'status_sub': {
        'en': "Your phone sends screenshots straight to this PC's clipboard.",
        'es': 'Tu teléfono envía capturas directo al portapapeles de este PC.'
    },
    'connected': {'en': 'Connected', 'es': 'Conectado'},
    'ready': {'en': 'Ready', 'es': 'Listo'},
    'not_paired': {'en': 'Not paired', 'es': 'Sin emparejar'},
    'no_device': {'en': 'No device', 'es': 'Sin dispositivo'},
    'not_paired_hint': {
        'en': 'Not paired — open Settings to pair',
        'es': 'Sin emparejar — abre Ajustes para emparejar'
    },
    'last_received': {'en': 'Last received', 'es': 'Última recibida'},
    'nothing_yet': {'en': 'Nothing yet', 'es': 'Nada aún'},
    'take_ss_phone': {'en': 'Take a screenshot on your phone', 'es': 'Toma una captura en tu teléfono'},
    'copied_clipboard': {'en': 'Copied to clipboard', 'es': 'Copiado al portapapeles'},
    'automatic_receiving': {'en': 'Automatic receiving', 'es': 'Recepción automática'},
    'autosend_on_sub': {
        'en': 'On — screenshots land on your clipboard',
        'es': 'Activado — las capturas llegan a tu portapapeles'
    },
    'autosend_paused_sub': {'en': 'Paused — not receiving', 'es': 'En pausa — no se reciben'},

    'waiting_ss': {'en': ' · waiting for screenshots', 'es': ' · esperando capturas'},
    'screenshot': {'en': 'Screenshot', 'es': 'Captura'},

    # history
    'history_sub': {'en': '{n} items', 'es': '{n} elementos'},
    'clear': {'en': 'Clear', 'es': 'Borrar'},
    'badge_copied': {'en': 'COPIED', 'es': 'COPIADA'},
    'badge_failed': {'en': 'FAILED', 'es': 'FALLÓ'},
    'no_history': {'en': 'No screenshots received yet', 'es': 'Aún no has recibido capturas'},
    'history_hint': {
        'en': 'Hover a screenshot and tap Copy to re-copy it.',
        'es': 'Pasa el cursor sobre una captura y toca Copiar para re-copiarla.'
    },
    'copy': {'en': 'Copy', 'es': 'Copiar'},

    # settings
    'settings_sub': {
        'en': 'Connection, preferences and pairing.',
        'es': 'Conexión, preferencias y emparejamiento.'
    },
    'connection': {'en': 'Connection', 'es': 'Conexión'},
    'paired_phone': {'en': 'Paired phone', 'es': 'Teléfono emparejado'},
    'no_device_paired': {'en': 'No device paired', 'es': 'Ningún dispositivo emparejado'},
    'forget_device': {'en': 'Forget device', 'es': 'Olvidar dispositivo'},
    'pair_new_phone': {'en': 'Pair a new phone', 'es': 'Emparejar un teléfono'},
    'pair_new_sub': {'en': 'Show the QR & address to scan', 'es': 'Mostrar el QR y la dirección'},
    'pair_device': {'en': 'Pair device', 'es': 'Emparejar'},
    'allow_manual': {'en': 'Allow a manual connection', 'es': 'Permitir conexión manual'},
    'allow_manual_sub': {
        'en': 'Only if the phone pairs by typing the IP (no QR). Opens a 2-min window.',
        'es': 'Solo si el teléfono empareja escribiendo la IP (sin QR). Abre una ventana de 2 min.'
    },
    'allow_btn': {'en': 'Allow (2 min)', 'es': 'Permitir (2 min)'},
    'allow_open': {
        'en': 'Open — connect from your phone now · ',
        'es': 'Abierto — conecta desde tu teléfono ahora · '
    },
    'allow_connected': {'en': '✓ Device connected', 'es': '✓ Dispositivo conectado'},
    'this_pc_addr': {'en': "This PC's address", 'es': 'Dirección de este PC'},
    'this_pc_addr_sub': {
        'en': 'Type this on the phone for a manual connection',
        'es': 'Escribe esto en el teléfono para una conexión manual'
    },
    'pair_step1': {'en': '1 · Open MagicPaste on your phone', 'es': '1 · Abre MagicPaste en tu teléfono'},
    'pair_step2': {'en': '2 · Tap "Scan QR" and point it here', 'es': '2 · Toca "Escanear QR" y apúntalo aquí'},
    'pair_step3': {'en': 'or type this address manually:', 'es': 'o escribe esta dirección a mano:'},
    'preferences': {'en': 'Preferences', 'es': 'Preferencias'},
    'start_with_windows': {'en': 'Start with Windows', 'es': 'Iniciar con Windows'},
    'show_notifications': {'en': 'Show notifications', 'es': 'Mostrar notificaciones'},
    'listen_port': {'en': 'Listen port', 'es': 'Puerto de escucha'},
    'restart_apply': {'en': 'Restart to apply', 'es': 'Reinicia para aplicar'},
    'about': {'en': 'About', 'es': 'Acerca de'},
    'open_source_free': {'en': 'Open source & free forever', 'es': 'Código abierto y gratis para siempre'},
    'made_with': {'en': 'Made with ', 'es': 'Hecho con '},
    'by': {'en': ' by ', 'es': ' por '},
    'support_kofi': {'en': 'Support on Ko-fi', 'es': 'Apoyar en Ko-fi'},
    'language': {'en': 'Language', 'es': 'Idioma'},
    'lang_system': {'en': 'System', 'es': 'Sistema'},

    # time labels
    'just_now': {'en': 'just now', 'es': 'ahora'},
    'ago': {'en': '{t} ago', 'es': 'hace {t}'},

    # toasts (built in Python)
    'toast_ss_copied': {'en': 'Screenshot copied to clipboard', 'es': 'Captura copiada al portapapeles'},
    'toast_from': {'en': 'from {d} · now', 'es': 'de {d} · ahora'},
    'toast_device_connected': {'en': '✓ Device connected', 'es': '✓ Dispositivo conectado'},
    'toast_paired': {'en': '{d} · paired', 'es': '{d} · emparejado'},
    'toast_copied': {'en': 'Copied to clipboard', 'es': 'Copiado al portapapeles'},
    'toast_press_ctrlv': {'en': 'press Ctrl+V to paste', 'es': 'presiona Ctrl+V para pegar'},
    'toast_img_unavailable': {'en': 'Image no longer available', 'es': 'La imagen ya no está disponible'},
    'toast_paused_ignored': {'en': 'Paused — screenshot ignored', 'es': 'En pausa — captura ignorada'},
}
