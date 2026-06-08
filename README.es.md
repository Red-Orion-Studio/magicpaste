# MagicPaste

[![Licencia: GPL v3](https://img.shields.io/badge/Licencia-GPLv3-7C3AED.svg)](LICENSE)
[![Beta](https://img.shields.io/badge/estado-beta-orange.svg)]()
[![English](https://img.shields.io/badge/README-English-7C3AED.svg)](README.md)
[![Ko-fi](https://img.shields.io/badge/Apoyar-Ko--fi-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/redorionstudio)

**Toma una captura de pantalla en Android → presiona Ctrl+V en tu PC con Windows. Así de simple.**

MagicPaste detecta automáticamente las capturas de pantalla nuevas en tu teléfono Android y las
envía directo al portapapeles de tu PC a través de tu WiFi local. Sin cuentas, sin
internet, sin nube — completamente local y de código abierto.

> **Aviso beta:** MagicPaste está en beta temprana (v0.1.0). Ha sido probado en
> Xiaomi (MIUI) — uno de los fabricantes Android más restrictivos con procesos en segundo plano
> — por lo que debería funcionar bien en la mayoría de dispositivos. Si encuentras algún error,
> por favor [abre un issue](https://github.com/RedOrionStudio/magicpaste/issues). 🙏

---

## Cómo funciona

1. Tomas una captura de pantalla en Android.
2. MagicPaste la detecta automáticamente (sin tocar nada más).
3. La envía a tu PC a través del WiFi local.
4. La imagen llega al portapapeles de Windows.
5. Presiona **Ctrl+V** donde quieras. Listo.

## Estructura del proyecto

| Carpeta | Qué es |
|---------|--------|
| [`magicpaste-windows/`](magicpaste-windows/) | Cliente Windows (Python) — recibe imágenes y las pone en el portapapeles |
| [`magicpaste-android/`](magicpaste-android/) | App Android (Flutter) — detecta y envía capturas de pantalla |
| [`.github/workflows/`](.github/workflows/) | CI para compilar el `.exe` y el `.apk` automáticamente |

---

## 🧪 Pruébalo antes de lanzar (orden recomendado)

### Paso 1 — Prueba el lado Windows en tu PC (sin teléfono)

```powershell
cd magicpaste-windows
pip install -r requirements.txt
python magicpaste.py            # aparece el ícono en la bandeja del sistema
# en una segunda terminal:
python test_client.py           # simula el teléfono
```

Presiona **Ctrl+V** en Paint / Word / un chat → deberías ver la imagen de prueba.
Esto confirma que toda la cadena recepción→portapapeles funciona. ✅

### Paso 2 — Prueba en tu teléfono

No necesitas Flutter en tu PC — la forma más fácil de obtener un APK de prueba es
compilarlo en la nube con el GitHub Action incluido:

1. Sube este repositorio a GitHub.
2. El workflow **Build Android APK** se ejecuta automáticamente (o inícialo manualmente
   desde la pestaña Actions → "Run workflow").
3. Descarga el artefacto `magicpaste-android` → instala el `.apk` en tu teléfono
   (activa "Instalar desde fuentes desconocidas").
4. Abre la app, vincula con tu PC (escanea el QR desde el tray de "Mostrar info de vinculación",
   o escribe la IP manualmente), luego toca **"Enviar última captura ahora"** para probar
   manualmente primero, y activa **Auto-envío**.

> ¿Prefieres compilar localmente? Instala [Flutter](https://docs.flutter.dev/get-started/install/windows),
> luego `cd magicpaste-android && flutter build apk`.

### Paso 3 — Publicar

Crea un GitHub Release con la etiqueta `v0.1.0`. Ambos workflows compilan y adjuntan el
`.exe` y el `.apk` al release automáticamente.

---

## Preguntas frecuentes

**¿Necesita internet?** No. Todo ocurre en tu WiFi local.

**¿Funciona fuera de mi WiFi de casa?** No — ambos dispositivos deben estar en la misma red.

**¿Es seguro?** Sí. Es solo local y completamente de código abierto — nada sale de tu red.
(El cifrado del enlace TCP está en el roadmap de v2.)

**¿iPhone?** No compatible (solo Android por ahora).

---

## Contribuir

Issues y PRs son bienvenidos. Consulta [`SPEC.md`](SPEC.md) para el diseño completo. Buenas
áreas de inicio: el roadmap de v2 (fallback Bluetooth, sincronización de portapapeles de texto, cifrado).

## Licencia

[GPLv3](LICENSE) — libre y de código abierto. Los forks y redistribuciones deben mantenerse
de código abierto bajo la misma licencia.

Hecho por [Red Orion Studio](https://www.redorionstudio.com) — *construimos software que se lanza.*
