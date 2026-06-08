import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight 2-language (en/es) localization.
///
/// Default follows the device language (Spanish device -> Spanish, anything
/// else -> English). The user can override it in Settings to System/EN/ES.
/// Call [init] before runApp; rebuild the app on [mode] changes.
class L10n {
  static const _kLangMode = 'mp_lang'; // 'system' | 'en' | 'es'

  /// Notifies listeners when the language changes (wrap the app to rebuild).
  static final ValueNotifier<String> mode = ValueNotifier<String>('system');
  static String _lang = 'en';

  static String get lang => _lang;

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _apply(p.getString(_kLangMode) ?? 'system');
  }

  static Future<void> setMode(String m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLangMode, m);
    _apply(m);
  }

  static void _apply(String m) {
    if (m == 'en' || m == 'es') {
      _lang = m;
    } else {
      m = 'system';
      final sys = ui.PlatformDispatcher.instance.locale.languageCode;
      _lang = sys == 'es' ? 'es' : 'en';
    }
    // Assigning a new value notifies listeners (the app rebuilds). The Settings
    // screen also calls setState after setMode, so picking the same option
    // still refreshes the selected chip.
    mode.value = m;
  }

  /// Force a specific language code directly — for use in tests only.
  // ignore: invalid_use_of_visible_for_testing_member
  static void forcelang(String lang) {
    _lang = lang;
    mode.value = lang;
  }

  /// Translate [key]; replaces {placeholders} from [args].
  static String t(String key, [Map<String, String>? args]) {
    final e = _s[key];
    var v = (e == null) ? key : (e[_lang] ?? e['en'] ?? key);
    if (args != null) args.forEach((k, val) => v = v.replaceAll('{$k}', val));
    return v;
  }

  static const Map<String, Map<String, String>> _s = {
    // -- bottom nav --
    'nav_home': {'en': 'Home', 'es': 'Inicio'},
    'nav_history': {'en': 'History', 'es': 'Historial'},
    'nav_settings': {'en': 'Settings', 'es': 'Ajustes'},

    // -- home --
    'tagline': {'en': 'Local clipboard sync', 'es': 'Portapapeles local'},
    'connected': {'en': 'Connected', 'es': 'Conectado'},
    'searching_pc': {'en': 'Searching for PC…', 'es': 'Buscando PC…'},
    'ready_take_ss': {'en': 'Ready — take a screenshot', 'es': 'Listo — toma una captura'},
    'make_sure_pc': {
      'en': 'Make sure the PC app is running on the same WiFi',
      'es': 'Asegúrate de que la app del PC esté abierta en la misma WiFi'
    },
    'port_host': {'en': 'Port {p} · {h}', 'es': 'Puerto {p} · {h}'},
    'retry_connection': {'en': 'Retry connection →', 'es': 'Reintentar conexión →'},
    'recently_sent': {'en': 'RECENTLY SENT', 'es': 'ENVIADAS RECIENTES'},
    'items': {'en': '{n} items', 'es': '{n} elementos'},
    'no_ss_yet': {'en': 'No screenshots sent yet', 'es': 'Aún no has enviado capturas'},
    'automatic_sending': {'en': 'Automatic sending', 'es': 'Envío automático'},
    'autosend_on': {
      'en': 'On — screenshots are sent automatically',
      'es': 'Activado — las capturas se envían solas'
    },
    'autosend_off': {
      'en': 'Off — screenshots are not being sent',
      'es': 'Desactivado — no se están enviando capturas'
    },
    'send_latest': {'en': 'Send latest screenshot now', 'es': 'Enviar última captura ahora'},
    'snack_photo_perm': {'en': 'Photo permission required', 'es': 'Se requiere permiso de fotos'},
    'snack_autosend_on': {
      'en': 'Auto-send on. On Xiaomi, also enable "Autostart" for MagicPaste.',
      'es': 'Envío automático activado. En Xiaomi, activa también "Inicio automático" para MagicPaste.'
    },
    'snack_sent_ok': {
      'en': 'Sent — press Ctrl+V on your PC',
      'es': 'Enviado — presiona Ctrl+V en tu PC'
    },
    'snack_sent_fail': {'en': 'Failed to send', 'es': 'No se pudo enviar'},
    'snack_no_ss': {'en': 'No screenshots found', 'es': 'No se encontraron capturas'},

    // -- pairing --
    'step_of': {'en': 'Step {n} of 2', 'es': 'Paso {n} de 2'},
    'back': {'en': 'Back', 'es': 'Atrás'},
    'keep_current_pc': {'en': 'Keep current PC', 'es': 'Mantener PC actual'},
    'pc_found': {'en': 'PC found on network', 'es': 'PC encontrado en la red'},
    'connect_arrow': {'en': 'Connect →', 'es': 'Conectar →'},
    'scan_to_connect': {'en': 'Scan to Connect', 'es': 'Escanea para conectar'},
    'scan_from_pc': {
      'en': 'Scan from MagicPaste on your Windows PC',
      'es': 'Escanea desde MagicPaste en tu PC'
    },
    'tap_code_open': {
      'en': 'Tap the code to open the scanner, then point it\nat the QR on your PC',
      'es': 'Toca el código para abrir el escáner y apúntalo\nal QR de tu PC'
    },
    'enter_ip_manually': {'en': 'Enter IP address manually →', 'es': 'Ingresar IP manualmente →'},
    'scan_qr_instead': {'en': '← Scan QR code instead', 'es': '← Escanear QR en su lugar'},
    'or': {'en': 'or', 'es': 'o'},
    'enter_pc_address': {'en': 'Enter PC Address', 'es': 'Dirección del PC'},
    'type_local_ip': {'en': "Type your PC's local IP address", 'es': 'Escribe la IP local de tu PC'},
    'ip_address_label': {'en': 'IP ADDRESS', 'es': 'DIRECCIÓN IP'},
    'connect': {'en': 'Connect', 'es': 'Conectar'},
    'where_find_ip': {
      'en': 'Where do I find it? On your PC open MagicPaste → Settings → "Pair device". It shows an address like 192.168.1.8 — type that here. (Tip: scanning the QR there is easier — no typing.)',
      'es': '¿Dónde la encuentro? En tu PC abre MagicPaste → Ajustes → "Pair device". Muestra una dirección como 192.168.1.8 — escríbela aquí. (Tip: escanear el QR es más fácil, sin teclear.)'
    },
    'err_refused': {
      'en': 'This PC already has a phone paired. On the PC, open MagicPaste → tap "Allow (2 min)", then try again.',
      'es': 'Este PC ya tiene un teléfono emparejado. En el PC, abre MagicPaste → toca "Allow (2 min)" y reintenta.'
    },
    'err_unreachable': {
      'en': "Couldn't reach the PC. Make sure MagicPaste is open on the same WiFi.",
      'es': 'No se pudo contactar al PC. Asegúrate de que MagicPaste esté abierto en la misma WiFi.'
    },
    'err_enter_ip': {'en': 'Please enter the PC IP address.', 'es': 'Ingresa la IP del PC.'},
    'scan_pc_qr_title': {'en': 'Scan PC QR code', 'es': 'Escanear QR del PC'},
    'camera_failed': {
      'en': "Camera couldn't start ({code}).",
      'es': 'No se pudo iniciar la cámara ({code}).'
    },
    'camera_failed_hint': {
      'en': 'Go back and pair with the green "PC found on network" banner or by typing the PC IP — no camera needed.',
      'es': 'Vuelve y empareja con el banner verde "PC encontrado" o escribiendo la IP — sin cámara.'
    },
    'torch': {'en': 'Torch', 'es': 'Linterna'},

    // -- history --
    'history_title': {'en': 'History', 'es': 'Historial'},
    'screenshots_sent': {'en': '{n} screenshots sent', 'es': '{n} capturas enviadas'},
    'clear': {'en': 'Clear', 'es': 'Borrar'},
    'take_ss_to_send': {
      'en': 'Take a screenshot to send it to your PC',
      'es': 'Toma una captura para enviarla a tu PC'
    },
    'today': {'en': 'Today', 'es': 'Hoy'},
    'yesterday': {'en': 'Yesterday', 'es': 'Ayer'},
    'sent_badge': {'en': 'SENT', 'es': 'ENVIADA'},
    'failed_badge': {'en': 'FAILED', 'es': 'FALLÓ'},
    'months_abbr': {
      'en': 'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec',
      'es': 'Ene,Feb,Mar,Abr,May,Jun,Jul,Ago,Sep,Oct,Nov,Dic'
    },

    // -- settings --
    'connection': {'en': 'Connection', 'es': 'Conexión'},
    'paired_phone': {'en': 'Paired phone', 'es': 'Teléfono emparejado'},
    'pc_address': {'en': 'PC Address', 'es': 'Dirección del PC'},
    'port_label': {'en': 'Port', 'es': 'Puerto'},
    'change_connection': {'en': 'Change Connection', 'es': 'Cambiar conexión'},
    'behavior': {'en': 'Behavior', 'es': 'Comportamiento'},
    'image_quality': {'en': 'Image Quality', 'es': 'Calidad de imagen'},
    'q_low': {'en': 'Low', 'es': 'Baja'},
    'q_med': {'en': 'Med', 'es': 'Media'},
    'q_high': {'en': 'High', 'es': 'Alta'},
    'confirmation_sound': {'en': 'Confirmation Sound', 'es': 'Sonido de confirmación'},
    'autostart_on_boot': {'en': 'Auto-start on boot', 'es': 'Iniciar al encender'},
    'always_on': {'en': 'Always-on detection', 'es': 'Detección permanente'},
    'always_on_hint': {
      'en': 'Keeps a small notification so screenshots are sent even when the app is fully closed. Recommended on Xiaomi / Huawei. Uses a little more battery.',
      'es': 'Mantiene una notificación para enviar capturas aunque la app esté cerrada. Recomendado en Xiaomi / Huawei. Usa un poco más de batería.'
    },
    'bg_setup_help': {'en': 'Background setup help', 'es': 'Ayuda de segundo plano'},
    'language': {'en': 'Language', 'es': 'Idioma'},
    'lang_system': {'en': 'System', 'es': 'Sistema'},
    'about': {'en': 'About', 'es': 'Acerca de'},
    'version': {'en': 'Version', 'es': 'Versión'},
    'open_source_free': {'en': 'Open source & free forever', 'es': 'Código abierto y gratis para siempre'},
    'support_kofi': {'en': 'Support on Ko-fi', 'es': 'Apoyar en Ko-fi'},
    'made_with': {'en': 'Made with ', 'es': 'Hecho con '},
    'by': {'en': ' by ', 'es': ' por '},

    // -- background help sheet --
    'bg_title': {'en': 'Keep running in the background', 'es': 'Mantener activo en segundo plano'},
    'bg_intro': {
      'en': 'Xiaomi/MIUI aggressively closes apps. Grant these so MagicPaste keeps sending screenshots when it is closed:',
      'es': 'Xiaomi/MIUI cierra las apps de forma agresiva. Activa esto para que MagicPaste siga enviando capturas aunque esté cerrada:'
    },
    'bg_s1_title': {'en': 'Autostart', 'es': 'Inicio automático'},
    'bg_s1_desc': {'en': 'Lets MagicPaste restart itself.', 'es': 'Permite que MagicPaste se reinicie solo.'},
    'bg_s1_action': {'en': 'Open Autostart', 'es': 'Abrir Inicio automático'},
    'bg_s2_title': {'en': 'No battery restrictions', 'es': 'Sin restricciones de batería'},
    'bg_s2_desc': {
      'en': 'Set battery to "No restrictions" so the service is not killed.',
      'es': 'Pon la batería en "Sin restricciones" para que no cierren el servicio.'
    },
    'bg_s2_action': {'en': 'Open battery settings', 'es': 'Abrir ajustes de batería'},
    'bg_s3_title': {'en': 'Lock in recents', 'es': 'Fijar en recientes'},
    'bg_s3_desc': {
      'en': 'Open Recents, hold MagicPaste and tap the padlock 🔒 to pin it.',
      'es': 'Abre Recientes, mantén pulsada MagicPaste y toca el candado 🔒 para fijarla.'
    },
    'done': {'en': 'Done', 'es': 'Listo'},
  };
}
