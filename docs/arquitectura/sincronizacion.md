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

## Protocolo de transporte

Una vez que dos dispositivos del mismo rol se descubren, intercambian filas vía un servidor HTTP embebido (`shelf`) con puerto asignado dinámicamente por el sistema operativo y anunciado por mDNS — ver [decisión 0022](../decisiones/0022-protocolo-transporte-sync-shelf-puerto-dinamico.md). Cada dispositivo expone `GET /sync/exportar` (todas las filas de las 4 tablas sincronizables, incluyendo tombstones) y hace *pull* del mismo endpoint en cada peer descubierto, aplicando el resultado con `RowUpserter` (LWW vía `RowSyncEngine`).

## Estado de implementación (2026-07-28)

- **Descubrimiento** (anunciar rol + descubrir pares): implementado con `bonsoir` — ver [decisión 0021](../decisiones/0021-paquete-mdns-bonsoir.md). En Linux depende de `avahi-daemon` activo en el sistema.
- **Transporte** (`SyncServer` + `SyncClient`): implementado — ver [decisión 0022](../decisiones/0022-protocolo-transporte-sync-shelf-puerto-dinamico.md). Cubre sync **intra-grupo** (pares del mismo rol, pairwise); probado con un test de integración real sobre HTTP (`test/sync_transport_test.dart`).
- **Elección de orquestador** (`SyncGroupCoordinator`): implementado, lógica pura (regla determinista sobre `device_id`s visibles).
- **Resolución de conflictos fila por fila** (`RowSyncEngine`): implementado, lógica pura de LWW — reutilizable tal cual por `TiketdataNotifier` (0017) y por `SyncClient` (0022) vía `RowUpserter`.
- **⚠ Falta — coordinación entre grupos**: el paso 3/4 del diseño de topología (orquestadores de cada rol sincronizando entre sí) todavía no tiene protocolo definido. Mientras no exista, `SyncNotifier.todosLosDispositivosSincronizados` sigue devolviendo `false` siempre (correcto: un Gerente y una Registradora nunca terminan de verse sincronizados entre sí sin ese handshake, que es el caso que le importa a la purga de Producto, 0015).
