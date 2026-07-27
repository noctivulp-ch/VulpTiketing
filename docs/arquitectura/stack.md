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

## Pendiente

- [ ] Versión mínima de Flutter/Dart
