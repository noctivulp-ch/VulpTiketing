# 0017 — Importar datos: `.tiketdata` (catálogo) vs `.tiketback` (backup completo), reemplazar vs fusionar

**Fecha:** 2026-07-27
**Estado:** Aceptada

## Contexto

El usuario propuso poder **importar** datos desde un archivo, con la opción de **reemplazar** o **fusionar** con lo que ya existe localmente — pensando en casos como cargar un menú/catálogo pre-armado (ej. un paquete de productos listo para usar, compartido entre negocios). Propuso además usar **dos extensiones de archivo distintas** para dos propósitos distintos, en vez de forzar todo a través del backup ya definido en [0006](0006-encriptacion-backup.md).

## Decisión

Dos tipos de archivo, con propósitos y formatos deliberadamente distintos:

### `.tiketback` — backup completo (renombra `.sodabak` de 0006)

- Contenido: **todo** el estado del dispositivo — SQLite completo (Producto, Categoria, Venta, LineaVenta históricas) + configuración.
- Formato: bundle cifrado, exactamente como ya definido en 0006 (contraseña de exportación → Argon2id → AES-256-GCM).
- Uso: recuperación de desastre, migrar de dispositivo.
- **Restaurar un `.tiketback` es siempre un reemplazo completo** — no ofrece modo "fusionar". Fusionar dos historiales de ventas de dispositivos distintos no tiene un significado contable sensato y arriesga corromper la contabilidad (que es la función central de la app).
- Se renombra `.sodabak` → `.tiketback` por consistencia de nombre con `.tiketdata` (ambos comparten el prefijo de la app).

### `.tiketdata` — paquete de catálogo (nuevo)

- Contenido: **solo** Producto y Categoria — nunca Ventas. Un catálogo no tiene datos sensibles ni historial de negocio, por eso se puede compartir libremente entre instalaciones distintas.
- Formato: **JSON, sin cifrar** — a propósito, porque este archivo está pensado para compartirse (entre negocios, como plantilla, etc.); cifrarlo sería fricción contraproducente para algo diseñado para circular. JSON también es más fácil de generar por herramientas de terceros que un bundle SQLite.
- Preserva los UUID originales de sus filas — esto hace que reimportar el mismo paquete dos veces sea naturalmente idempotente (no crea duplicados), por el mismo mecanismo de upsert por `id` que ya usa la sync.
- Al importar, el usuario elige:
  - **Reemplazar**: descontinúa (soft-delete vía `deleted_at`, nunca borrado físico — consistente con [0005](0005-borrados-en-sync.md)/[0009](0009-cruds-independientes-por-entidad.md)) todo Producto/Categoria local que **no** esté en el archivo, y aplica upsert de todo lo que sí viene en el archivo.
  - **Fusionar**: aplica upsert únicamente de lo que viene en el archivo — no toca nada más del catálogo local.
  - **Ambos modos reutilizan el mismo mecanismo de resolución de conflictos LWW** ya construido para sync entre dispositivos (0005) — un `.tiketdata` se trata como "un peer más" que aporta cambios por `updated_at`, no se inventa un algoritmo de merge nuevo.

## Alternativas descartadas

- **Un solo tipo de archivo para todo** — mezclaría datos sensibles/históricos (Ventas) con algo pensado para compartirse abiertamente (catálogo), y complicaría la semántica de "reemplazar" (¿reemplazar también el historial de ventas al cargar un menú? no tiene sentido).
- **Cifrar también `.tiketdata`** — fricción innecesaria para un archivo cuyo propósito es compartirse.
- **Permitir "fusionar" en la restauración de `.tiketback`** — sin sentido contable, dos historiales de ventas independientes no se combinan de forma segura.

## Consecuencias

- `Data.feature` gana escenarios de exportar/importar `.tiketdata` con ambos modos, y de restaurar `.tiketback` (siempre reemplazo).
- `docs/funciones/backup.md` se reescribe para cubrir ambos tipos de archivo.
- Dos servicios separados en la gestión de estado — `TiketbackNotifier` y `TiketdataNotifier` ([decisión 0019](0019-descomponer-servicios-responsabilidad-unica.md)) — en vez de uno solo, porque tienen mecanismos internos distintos (bundle cifrado vs. JSON + merge LWW). `TiketdataNotifier` **reutiliza** `RowSyncEngine` (el mismo motor de LWW que usa la sync entre dispositivos) en vez de duplicar esa lógica — consistente con [0009](0009-cruds-independientes-por-entidad.md).
- Todas las referencias previas a `.sodabak` (features, docs, 0006) se actualizan a `.tiketback`.
