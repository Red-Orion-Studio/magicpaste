# MagicPaste — Especificación del Proyecto

> Versión: 0.1.0 Beta
> Estado: Implementado — en beta
> Última actualización: 2026-06-07
> [English version](SPEC.md)

---

## 1. ¿Qué es MagicPaste?

MagicPaste es una herramienta de código abierto que detecta automáticamente cuando el usuario toma una captura de pantalla en Android y la envía al portapapeles de una PC con Windows — para que el usuario pueda presionar Ctrl+V de inmediato, sin pasos adicionales.

**Flujo principal:**
1. El usuario toma una captura de pantalla en Android
2. MagicPaste la detecta automáticamente (sin acción del usuario)
3. MagicPaste envía la imagen a la PC con Windows a través del WiFi local
4. La imagen se coloca en el portapapeles de Windows
5. El usuario presiona Ctrl+V en cualquier lugar — listo

**Sin cuentas. Sin internet. Sin nube. Sin registro. Completamente local.**

---

## 2. Objetivos

- Cero configuración tras el emparejamiento inicial
- Funciona completamente en red local (WiFi) — sin internet
- Código abierto (Licencia GPLv3)
- Fácil de instalar y usar para usuarios no técnicos
- Interfaz en inglés y español en ambas plataformas

---

## 3. No incluido

- Sin soporte para iOS
- Sin sincronización en la nube ni acceso remoto
- Sin sincronización de portapapeles de texto (solo imágenes/capturas, por ahora)
- Sin soporte Android→Mac (funcionalidad futura)

---

## 4. Componentes

### 4.1 App Android (`magicpaste-android/`)

**Lenguaje:** Flutter (Dart) + Kotlin (motor de segundo plano nativo)
**SDK mínimo:** Android 8.0 (API 26)
**Distribución:** GitHub Releases como `.apk`
**Orientación:** Portrait bloqueado

**Pantallas (navegación inferior):**
- **Inicio** — tarjeta de estado de conexión, info del dispositivo vinculado, toggle de auto-envío, botón de envío manual, historial reciente
- **Historial** — registro completo de envíos (enviado/fallido/pendiente) con marcas de tiempo y miniaturas
- **Vinculación** — escáner QR + entrada manual de IP, banner de estado de conexión
- **Configuración** — calidad de imagen (Baja/Media/Alta), selector de idioma (Sistema/EN/ES), toggle de modo en segundo plano, toggle de inicio en arranque, acerca de/versión

**Motor en segundo plano (doble capa):**
- `ScreenshotService.kt` — `ForegroundService` persistente con un `ContentObserver` sobre `MediaStore.Images.Media.EXTERNAL_CONTENT_URI`. Motor principal. Se mantiene activo en primer plano con una notificación permanente.
- `SyncWorker.kt` — `CoroutineWorker` de WorkManager con un trigger URI sobre MediaStore. Se activa en segundos ante una nueva captura. Funciona como autocorrección: si el fabricante mató el servicio, el worker lo reinicia. También corre como red de seguridad periódica cada 6h.
- `SyncScheduler.kt` — arma y rearma los triggers de WorkManager
- `BootCompletedReceiver.kt` — rearma en arranque y actualización de la app
- `ScreenshotScanner.kt` — lógica compartida para consultar MediaStore y enviar vía el protocolo
- `MagicPasteProtocol.kt` — implementación Kotlin del protocolo de comunicación
- `Strings.kt` — i18n en el lado Kotlin (lee la misma preferencia `mp_lang` que Flutter)
- `NotificationActionReceiver.kt` — maneja la acción "Desactivar" en la notificación persistente

**Servicios Flutter:**
- `screenshot_monitor.dart` — coordina con la capa nativa
- `network_service.dart` — lógica de envío TCP
- `pairing_service.dart` — gestión del estado de emparejamiento
- `settings_service.dart` — wrapper de SharedPreferences
- `sent_history.dart` — historial local de capturas enviadas
- `native_sync.dart` — method channel hacia el lado nativo
- `protocol.dart` — implementación Dart del protocolo
- `l10n.dart` — servicio de i18n (inglés + español, detección automática o manual)

**Paquetes principales:** `photo_manager`, `network_info_plus`, `nsd`, `flutter_foreground_task`, `qr_flutter`, `mobile_scanner`, `shared_preferences`, `permission_handler`, `url_launcher`

---

### 4.2 Cliente Windows (`magicpaste-windows/`)

**Lenguaje:** Python 3.10+
**Distribución:** `.exe` standalone (PyInstaller, onefile) + instalador Inno Setup

**Interfaz:** Ventana glassmorphism con `pywebview` (EdgeChromium/WebView2) — ventana única con pestañas en la barra lateral: Estado / Historial / Configuración. Se lanza oculta con `--background` para el inicio automático.

**Módulos:**
- `magicpaste.py` — punto de entrada; conecta todos los componentes; flag `--background` para modo solo-bandeja; instancia única vía puerto de control 49199
- `server.py` — listener TCP en puerto 49152; despacha mensajes IMAGE / PING / PAIR
- `clipboard.py` — establece el portapapeles de Windows vía `win32clipboard`
- `tray.py` — ícono pystray de 3 estados (verde=conectado, ámbar=listo/vinculado, rojo=sin vincular); gestión del registro de inicio automático; usa `pythonw.exe` para lanzamiento sin consola
- `webui.py` — wrapper de pywebview; expone la API Python a JS; envía snapshots de estado y strings de i18n a la UI; notificaciones toast
- `state.py` — `AppState` compartido; persistido en `state.json`
- `discovery.py` — anuncio mDNS vía `zeroconf` (`_magicpaste._tcp.local.`)
- `thumbs.py` — genera miniaturas PNG para la vista de historial
- `pairing_info.py` — genera el código QR para vinculación
- `protocol.py` — implementación del protocolo de comunicación
- `i18n.py` — módulo de i18n (inglés + español, detección automática del locale de Windows)

**Assets:** `assets/main.html`, `assets/toast.html`, `assets/logo.png`, `assets/icons/`

**Dependencias Python:** `pywin32`, `Pillow`, `pystray`, `zeroconf`, `qrcode`, `pywebview`

---

## 5. Protocolo de Comunicación

### 5.1 Transporte
- **Primario:** TCP sobre WiFi local
- **Puerto:** `49152` (configurable)
- **Futuro:** Bluetooth RFCOMM (no implementado)

### 5.2 Formato de Mensajes

Todos los mensajes son binarios. Cada mensaje comienza con una **cabecera fija de 32 bytes**:

```
Bytes  0-3  : Número mágico 0x534E4150 ("SNAP")
Bytes  4-7  : Tipo de mensaje (uint32, big-endian)
                0x01 = IMAGE
                0x02 = PING
                0x03 = PONG
                0x04 = PAIR_REQUEST
                0x05 = PAIR_ACCEPT
                0x06 = IMAGE_ACK
                0x07 = PAIR_REJECT
Bytes  8-11 : Longitud del payload en bytes (uint32, big-endian)
Bytes 12-15 : Reservado (0x00000000)
Bytes 16-31 : Token de autenticación (16 bytes). El teléfono lo aprende al vincularse.
              La PC rechaza mensajes no-pairing con token incorrecto.
              Las solicitudes no autenticadas envían 16 bytes en cero.
```

**Payload IMAGE (prefijo de 12 bytes + bytes crudos de imagen):**
```
Bytes 0-3  : Formato de imagen (uint32): 0x01 = PNG, 0x02 = JPEG
Bytes 4-7  : Ancho en píxeles (uint32)
Bytes 8-11 : Alto en píxeles (uint32)
Bytes 12+  : Bytes crudos del archivo de imagen
```

**Payload IMAGE_ACK (1 byte):** `0x01` = copiado al portapapeles, `0x00` = descartado (pausado o error).

### 5.3 Flujo de Vinculación (TOFU)

1. Android envía `PAIR_REQUEST` con el nombre del dispositivo como payload UTF-8
2. La PC acepta si: el teléfono ya tiene un token válido, no hay dispositivo vinculado aún (primera vez), o la ventana "Permitir nuevo dispositivo" está abierta
3. La PC envía `PAIR_ACCEPT` con un token aleatorio de 16 bytes recién generado como payload
4. Android almacena el token; todos los mensajes siguientes lo incluyen en la cabecera
5. La PC envía `PAIR_REJECT` si ya está vinculada y no está en modo de vinculación

El descubrimiento mDNS (`_magicpaste._tcp.local.`) permite que Android encuentre la PC automáticamente — sin necesidad de escribir la IP.

---

## 6. Configuración Inicial (Experiencia de Usuario)

### Lado Windows:
1. Ejecutar `MagicPaste-Setup-v0.1.0-beta.exe` — instala en Archivos de programa, crea acceso directo en el escritorio
2. MagicPaste se lanza automáticamente — aparece el ícono en la bandeja del sistema
3. Clic derecho en la bandeja → "Mostrar info de vinculación" → QR + IP mostrados en la ventana

### Lado Android:
1. Instalar `MagicPaste-v0.1.0-beta.apk` desde GitHub Releases
2. Abrir la app → tocar **Conectar a PC** → escanear QR o escribir IP manualmente
3. La vinculación se completa automáticamente (TOFU — sin aceptación manual en la PC)
4. Activar el toggle **Auto-envío** → listo

### Después de la configuración:
- Toma cualquier captura → aparece en el portapapeles de la PC en menos de 2 segundos
- No se requiere ninguna acción adicional

---

## 7. Estructura del Repositorio

```
magicpaste/
├── README.md
├── README.es.md
├── LICENSE                          (GPLv3)
├── SPEC.md                          (spec en inglés)
├── SPEC.es.md                       (este archivo)
├── branding/
│   ├── logo-magicpaste.svg          (logo completo fondo violeta)
│   └── glifo-magicpaste.svg         (solo el glifo, fondo transparente)
├── magicpaste-android/
│   ├── pubspec.yaml
│   ├── key.properties               (no se sube — config de firma)
│   ├── magicpaste-release.jks       (no se sube — keystore de release)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/
│   │   │   ├── l10n.dart
│   │   │   ├── screenshot_monitor.dart
│   │   │   ├── network_service.dart
│   │   │   ├── pairing_service.dart
│   │   │   ├── settings_service.dart
│   │   │   ├── sent_history.dart
│   │   │   ├── native_sync.dart
│   │   │   └── protocol.dart
│   │   └── ui/
│   │       ├── theme.dart
│   │       ├── main_shell.dart
│   │       ├── bottom_nav.dart
│   │       ├── home_screen.dart
│   │       ├── history_screen.dart
│   │       ├── pairing_screen.dart
│   │       ├── settings_screen.dart
│   │       └── background_help.dart
│   ├── assets/branding/             (íconos de launcher, splash)
│   └── android/app/src/main/kotlin/com/magicpaste/magicpaste/
│       ├── MainActivity.kt
│       ├── ScreenshotService.kt
│       ├── SyncWorker.kt
│       ├── SyncScheduler.kt
│       ├── ScreenshotScanner.kt
│       ├── MagicPasteProtocol.kt
│       ├── Strings.kt
│       ├── BootCompletedReceiver.kt
│       └── NotificationActionReceiver.kt
├── magicpaste-windows/
│   ├── requirements.txt
│   ├── magicpaste.py
│   ├── server.py
│   ├── clipboard.py
│   ├── tray.py
│   ├── webui.py
│   ├── state.py
│   ├── discovery.py
│   ├── thumbs.py
│   ├── pairing_info.py
│   ├── protocol.py
│   ├── i18n.py
│   ├── test_client.py
│   ├── test_protocol.py
│   ├── magicpaste.spec              (spec de PyInstaller)
│   ├── installer.iss                (script de Inno Setup)
│   └── assets/
│       ├── main.html
│       ├── toast.html
│       ├── logo.png
│       └── icons/
│           ├── logo.png
│           ├── magicpaste.ico
│           ├── tray_green.png
│           └── tray_red.png
└── .github/workflows/
    ├── build-android.yml
    └── build-windows.yml
```

---

## 8. GitHub Actions (CI/CD)

Ambos workflows se activan en pushes a `main` y en nuevos tags de release (`v*`). Los tags de release además adjuntan los artefactos compilados al GitHub Release.

### APK Android (`build-android.yml`):
- Configura Java 17 + Flutter
- Ejecuta `flutter build apk --release`
- Sube `app-release.apk` como artefacto y al release

### EXE Windows (`build-windows.yml`):
- Configura Python 3.11
- Ejecuta `pip install -r requirements.txt pyinstaller`
- Ejecuta `pyinstaller magicpaste.spec --clean`
- Sube `MagicPaste.exe` como artefacto y al release

---

## 9. i18n

Ambas plataformas soportan **inglés** y **español**. El idioma se detecta automáticamente desde el locale del SO (español si `es-*`, inglés en cualquier otro caso) y se puede cambiar manualmente desde el selector de idioma en Configuración (Sistema / EN / ES).

- **Android (Flutter):** `l10n.dart` — `L10n.t(clave)` en todas las pantallas y la navegación inferior
- **Android (Kotlin nativo):** `Strings.kt` — lee la misma clave `flutter.mp_lang` de SharedPreferences; usada en las notificaciones de `ScreenshotService` y `SyncWorker`
- **Windows (Python):** `i18n.py` — `i18n.t(clave, lang)` para toasts; locale detectado vía `kernel32.GetUserDefaultLocaleName`
- **Windows (HTML/JS):** atributos `data-i18n` en todo el texto estático; `window.applyI18n(dict)` aplica las traducciones enviadas desde Python vía el evento `MP_I18N`

---

## 10. Funcionalidades Futuras (v2.0+)

- Soporte Bluetooth (RFCOMM) como respaldo cuando no hay WiFi disponible
- Sincronización de portapapeles de texto (no solo imágenes)
- Cliente macOS
- Cliente Linux
- Múltiples dispositivos vinculados
- Cifrado (TLS) para la conexión TCP
- Publicación en Google Play Store
- Publicación en Microsoft Store

---

*Licencia GPLv3 — libre y de código abierto; los forks deben mantenerse abiertos. Hecho por Red Orion Studio.*
