# Sincronización

Ver también: [datos](datos.md) · [seguridad](seguridad.md) · [../funciones/roles-y-auth](../funciones/roles-y-auth.md) · [../../features/Data.feature](../../features/Data.feature)

## Base (ya definida en Architecture.feature)

- Descubrimiento de dispositivos en la misma red local vía ZeroConf/mDNS
- Intercambio de registros SQLite
- Resolución de conflictos: Last Write Wins según `updated_at`

## Topología multi-dispositivo

El esquema soporta más de dos dispositivos: una Gerente principal y posiblemente varias Registradoras (los roles son de interfaz, no de privilegio estricto — ver [roles-y-auth](../funciones/roles-y-auth.md)).

**Diseño aceptado** (dos redes lógicas por rol, con orquestador electo por red) — ver el diseño completo en [decisión 0007](../decisiones/0007-topologia-sync.md):

1. Dispositivos del mismo rol sincronizan directo entre sí (pairwise) al descubrirse por mDNS.
2. Cada grupo de rol elige un orquestador de forma agnóstica (regla determinista, ej. UUID más bajo visible entre el `device_id` de cada dispositivo — ver [esquema-db, sección de configuración local](esquema-db.md#configuración-local-del-dispositivo-fuera-de-sqlite), aún pendiente de diseñar a detalle) para coordinar la sync *entre* grupos.
3. Cuando ambos grupos están sin tareas de sync pendientes internamente, sus orquestadores sincronizan entre sí y propagan el resultado a su propio grupo.

## Borrados

Los borrados se propagan como cualquier otro cambio de fila: son soft-delete (`deleted_at`) resuelto por la misma lógica LWW basada en `updated_at` — no requieren un mecanismo de sync aparte. Ver [decisión 0005](../decisiones/0005-borrados-en-sync.md).

## Estado de implementación (2026-07-28)

- **Descubrimiento** (anunciar rol + descubrir pares): implementado con `bonsoir` — ver [decisión 0021](../decisiones/0021-paquete-mdns-bonsoir.md). En Linux depende de `avahi-daemon` activo en el sistema.
- **Elección de orquestador** (`SyncGroupCoordinator`): implementado, lógica pura (regla determinista sobre `device_id`s visibles).
- **Resolución de conflictos fila por fila** (`RowSyncEngine`): implementado, lógica pura de LWW — reutilizable tal cual por `TiketdataNotifier` (0017).
- **⚠ Falta — protocolo de transporte**: una vez que dos dispositivos se descubren, todavía no existe una decisión de **cómo intercambian las filas reales** por la red (¿servidor HTTP embebido? ¿socket TCP con un formato propio? ¿WebSocket?). `DeviceDiscoveryService`, `SyncGroupCoordinator` y `RowSyncEngine` están listos para que ese protocolo los use, pero ninguno de los tres resuelve el transporte en sí — es una decisión de arquitectura aparte, todavía no tomada. Mientras no exista, `SyncNotifier.todosLosDispositivosSincronizados` sigue devolviendo `false` siempre (correcto: sin transporte, ninguna sync se completa de verdad).
