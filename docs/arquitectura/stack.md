# Stack Técnico

Ver también: [datos](datos.md) · [sincronización](sincronizacion.md) · [seguridad](seguridad.md) · [../decisiones/index](../decisiones/index.md)

## Resumen

| Capa | Tecnología |
|------|-----------|
| Framework | Flutter (Dart) |
| Base de datos | SQLite |
| Primary keys | UUID v4 en todas las tablas |
| Auditoría de fila | columna `updated_at` en ISO-8601 en todas las tablas |
| Gestión de estado | Riverpod, desacoplada de la UI — ver [gestión de estado](gestion-estado.md) y [decisión 0014](../decisiones/0014-riverpod-como-gestion-de-estado.md) |
| Resolución de conflictos | Last Write Wins (LWW), basada en `updated_at` |
| Targets de compilación | Android (APK/AAB) + Windows/Linux (ejecutable nativo desktop) |

Offline-first: la app nunca depende de un backend en la nube. Todo el estado vive en SQLite local; la sincronización es punto a punto por red local (ver [sincronización](sincronizacion.md)).

## Por qué UUID v4 + `updated_at` en vez de autoincrement

Con sync entre múltiples dispositivos sin servidor central, un `id` autoincremental generaría colisiones (dos dispositivos offline creando el registro "3" cada uno). UUID v4 garantiza unicidad sin coordinación. `updated_at` es la base de la resolución de conflictos LWW.

## Versión y toolchain (scaffold, 2026-07-28)

- Flutter 3.44.8 (stable) / Dart 3.12.2, gestionado con `fvm` (no Flutter global del sistema — correr `fvm use stable` o anteponer `~/fvm/default/bin` al PATH).
- Toolchain Linux desktop verificado end-to-end: `flutter build linux --debug` compila y linkea.
- Android: SDK incompleto en este entorno (falta `cmdline-tools`, `platforms`, `build-tools`) — no bloquea el desarrollo desktop, pendiente completar antes de compilar un APK.
- Windows: no se puede cross-compilar desde Linux — se usa una VM Windows disponible cuando llegue el momento de ese target.

### Gotcha encontrado: `flutter_secure_storage` y clang reciente

La versión `^9.x` de `flutter_secure_storage` trae una copia vieja de `json.hpp` (nlohmann-json) que no compila con clang ≥ 22 en Linux desktop (`-Wdeprecated-literal-operator` como error). Se resolvió subiendo a `^10.3.1` — si en el futuro este error reaparece con otra dependencia nativa C++, el mismo patrón de diagnóstico aplica: revisar si hay una versión más nueva del paquete antes de tocar flags de compilador.

## Dependencias del scaffold (`pubspec.yaml`)

| Paquete | Para qué |
|---------|----------|
| `flutter_riverpod` | Gestión de estado (0014) |
| `sqflite` + `sqflite_common_ffi` | SQLite — Android y Linux/Windows desktop respectivamente |
| `flutter_secure_storage` | Rol, contraseña, `device_id` (0011) |
| `shared_preferences` | Preferencias de UI no sensibles (0018 — `PreferenciasNotifier`) |
| `cryptography` | Argon2id implementado en `CredencialesService` (0011); AES-256-GCM para `.tiketback` aún sin implementar (0006) |
| `uuid` | UUID v4 en todas las PK |
| `path_provider` / `path` | Ubicación del archivo SQLite en cada plataforma |
| `intl` | Formato de fechas/moneda |
| `flutter_svg` | Íconos vectoriales propios (0020) |
| `bonsoir` | mDNS para sync — anunciar + descubrir (0021). En Linux depende de `avahi-daemon` del sistema. |
| `file_picker` | Selector nativo de archivos para exportar/restaurar `.tiketback`/`.tiketdata` (0006/0017). Verificado que compila en Linux (implementación nativa en Dart desde v4, no depende de zenity/kdialog). |

**Pendiente de decidir, no de paquete:** el protocolo de transporte para intercambiar filas entre dispositivos una vez descubiertos (servidor embebido, socket TCP, WebSocket...) — ver `docs/arquitectura/sincronizacion.md#estado-de-implementación-2026-07-28`.
