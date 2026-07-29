# Backup e Importación de Datos

Ver también: [../arquitectura/seguridad](../arquitectura/seguridad.md) · [../../features/Data.feature](../../features/Data.feature) · [decisión 0017](../decisiones/0017-importar-datos-tiketdata-vs-tiketback.md)

Dos tipos de archivo con propósitos distintos — ver [decisión 0017](../decisiones/0017-importar-datos-tiketdata-vs-tiketback.md) para el razonamiento completo.

## `.tiketback` — backup completo (cifrado)

**Implementado** (`TiketbackService`/`TiketbackNotifier`, con prueba de round-trip en `test/tiketback_service_test.dart`).

- Contenido: la base de datos SQLite completa (Producto, Categoria, Venta, LineaVenta históricas) + preferencias de UI no sensibles (orden de productos, acento). **No incluye** rol, contraseña ni `device_id` — esos son de almacenamiento seguro nativo, específicos de cada dispositivo, y se quedan ahí a propósito aunque el archivo ya vaya cifrado (defensa en profundidad). Restaurar un backup en un dispositivo nuevo deja su rol/contraseña como estaban en ese dispositivo (de fábrica, o lo que se haya configurado ahí).
- Exportar: disponible para cualquier rol. Restaurar: **solo Gerente** (aplicado en `ConfiguracionScreen`).
- Esquema de encriptación: contraseña de exportación propia (distinta del login) → clave derivada con Argon2id → AES-256-GCM (`package:cryptography`). Ver [seguridad](../arquitectura/seguridad.md) y [decisión 0006](../decisiones/0006-encriptacion-backup.md).
- Restaurar es **siempre un reemplazo completo** del estado local — no existe modo "fusionar" para este archivo (fusionar dos historiales de ventas no tiene sentido contable). La UI pide confirmación explícita antes de pedir la contraseña, por ser irreversible.
- Selector de archivo: `file_picker` (nativo, verificado que compila en los tres targets).

## `.tiketdata` — paquete de catálogo (sin cifrar)

**Implementado** (`TiketdataService`/`TiketdataNotifier`, con pruebas en `test/tiketdata_service_test.dart` cubriendo fusionar, reemplazar, y que LWW respeta un cambio local más reciente).

- Contenido: **solo** Producto y Categoria **activos** (no se exportan descontinuados) — nunca Ventas. Pensado para compartirse (ej. un menú prearmado entre negocios), por eso no está cifrado.
- Formato: JSON, preservando los UUID originales de cada fila (reimportar el mismo paquete dos veces no crea duplicados).
- Exportar e importar: solo Gerente (aplicado en `ConfiguracionScreen`).
- Al importar, el usuario elige:
  - **Reemplazar** — descontinúa (soft-delete, nunca borrado físico) todo lo local activo que no esté en el archivo, y aplica upsert de lo que sí viene.
  - **Fusionar** — aplica upsert solo de lo que viene en el archivo, sin tocar el resto del catálogo. La UI pide confirmación explícita solo para "Reemplazar" (afecta datos existentes).
  - Ambos modos reutilizan `RowSyncEngine.resolver()` fila por fila — el mismo mecanismo LWW de la sync entre dispositivos (0005), no es un algoritmo de merge nuevo.
- Selector de archivo: `file_picker`, igual que `.tiketback`.
