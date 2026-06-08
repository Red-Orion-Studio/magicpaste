# Contribuir a MagicPaste

[![English](https://img.shields.io/badge/README-English-7C3AED.svg)](CONTRIBUTING.md)

¡Gracias por tu interés en contribuir! MagicPaste es un proyecto de código abierto de [Red Orion Studio](https://www.redorionstudio.com). Cualquier ayuda es bienvenida.

---

## Cómo contribuir

- **Reportar bugs** — abre un [issue](https://github.com/RedOrionStudio/magicpaste/issues) con los pasos para reproducirlo, tu versión de Android/fabricante y versión de Windows
- **Probar en otros dispositivos** — especialmente OEMs distintos a Xiaomi (Samsung, Pixel, OnePlus, Motorola)
- **Corregir bugs** — toma un issue abierto y envía un PR
- **Mejorar traducciones** — EN y ES están incluidos; agregar más idiomas es bienvenido
- **Añadir funcionalidades del roadmap** — ver `SPEC.es.md` sección 10 para la lista de v2

---

## Estructura del proyecto

| Carpeta | Stack |
|---------|-------|
| `magicpaste-android/` | Flutter (Dart) + motor de segundo plano nativo en Kotlin |
| `magicpaste-windows/` | Python 3.10+ + pywebview + pystray |
| `branding/` | Archivos SVG fuente para logos e íconos |
| `.github/workflows/` | CI/CD — compila APK y EXE en cada push |

Ver [`SPEC.es.md`](SPEC.es.md) para la arquitectura completa, descripción del protocolo y roadmap futuro.

---

## Configuración de desarrollo

### Cliente Windows

```powershell
cd magicpaste-windows
pip install -r requirements.txt
python magicpaste.py
```

Para simular el teléfono enviando una captura:
```powershell
python test_client.py
```

Para correr los tests unitarios del protocolo:
```powershell
pip install pytest
pytest tests/
```

### App Android

```powershell
cd magicpaste-android
flutter pub get
flutter run
```

Para correr los tests de Flutter:
```powershell
flutter test
```

---

## Guía para Pull Requests

1. **Un PR por tema** — no mezcles correcciones de bugs con nuevas funcionalidades
2. **Mantenlo simple** — no agregues dependencias nuevas sin discutirlo antes
3. **Prueba tu cambio** — ejecuta `pytest tests/` (Python) y `flutter test` (Android) antes de enviar
4. **Sigue el estilo existente** — sin guerras de formateadores; adapta el código al entorno
5. **Actualiza el SPEC** si añades o cambias una funcionalidad

---

## Firma / release

El keystore de release (`magicpaste-release.jks`) y `key.properties` **no están en el repositorio** y son mantenidos por Red Orion Studio. Los APKs de release son compilados y firmados únicamente por los mantenedores.

---

## Código de conducta

Sé amable. Este es un proyecto personal — el tiempo de respuesta del mantenedor puede variar.

---

*Hecho por [Red Orion Studio](https://www.redorionstudio.com) — GPLv3*
