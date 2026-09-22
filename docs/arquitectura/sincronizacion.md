# Sincronización

Ver también: [datos](datos.md) · [seguridad](seguridad.md) · [../funciones/roles-y-auth](../funciones/roles-y-auth.md) · [../../features/Data.feature](../../features/Data.feature)

## Base (ya definida en Architecture.feature)

- Descubrimiento de dispositivos en la misma red local vía ZeroConf/mDNS
- Intercambio de registros SQLite
- Resolución de conflictos: Last Write Wins según `updated_at`

## Topología multi-dispositivo

El esquema soporta más de dos dispositivos: una Gerente principal y posiblemente varias Registradoras (los roles son de interfaz, no de privilegio estricto — ver [roles-y-auth](../funciones/roles-y-auth.md)).

**Diseño vigente:** cada dispositivo sincroniza con **todos** los pares que ve, sin mirar el rol, y repasa los ya conocidos en una ronda cada 15 segundos — ver [decisión 0036](../decisiones/0036-sync-par-a-par-con-ronda-periodica.md).

Sustituye al diseño de dos redes lógicas por rol de la [decisión 0007](../decisiones/0007-topologia-sync.md), que quedó a medias: el paso que unía los dos grupos (el handshake entre orquestadores) nunca se implementó, así que una Registradora veía al Gerente por mDNS y no sincronizaba nunca con él. La separación por rol **no era de seguridad** — los roles son de interfaz, no de privilegio — sino un ahorro de tráfico que a esta escala no compra nada.

El coordinador de orquestador sigue existiendo por si ese ahorro hiciera falta algún día. Un aparato que no ve a nadie **no** es orquestador: orquestar es coordinar con alguien.

## El interruptor de sincronización

Está en Configuración → Sincronizar. Recién instalada la app arranca **apagada**; encenderla se recuerda para el siguiente arranque y no se auto-apaga al cerrar la app.

Al apagarlo el aparato **deja de anunciarse** por mDNS y deja de descubrir. Importa más de lo que parece: un teléfono que sigue anunciando con el interruptor apagado entra en las rondas de todos los demás, y sus datos aparecen donde nadie los puso.

## Borrados

Los borrados se propagan como cualquier otro cambio de fila: son soft-delete (`deleted_at`) resuelto por la misma lógica LWW basada en `updated_at` — no requieren un mecanismo de sync aparte. Ver [decisión 0005](../decisiones/0005-borrados-en-sync.md).

## Protocolo de transporte

Una vez que dos dispositivos del mismo rol se descubren, intercambian filas vía un servidor HTTP embebido (`shelf`) con puerto asignado dinámicamente por el sistema operativo y anunciado por mDNS — ver [decisión 0022](../decisiones/0022-protocolo-transporte-sync-shelf-puerto-dinamico.md). Cada dispositivo expone `GET /sync/exportar` (todas las filas de las 5 tablas sincronizables —`categoria`, `producto`, `venta`, `linea_venta` y `corte_caja`—, incluyendo tombstones) y hace *pull* del mismo endpoint en cada peer descubierto, aplicando el resultado con `RowUpserter` (LWW vía `RowSyncEngine`).

El payload va envuelto en `{version, esquema, moneda, tablas}`. La `moneda` (símbolo y decimales, 0043) se rechaza si difiere, como el esquema. `esquema` va por **5**
desde las variantes (0039): 1.0.0 usaba 4. `version` es la forma del mensaje y `esquema` la versión del modelo de datos: un peer con otro `esquema` se **rechaza sin aplicar una sola fila**, porque mezclar filas de dos modelos no produce un error visible sino una contabilidad que no es la de ninguno de los dos aparatos.

### Qué viaja y qué no

| | Viaja | Por qué |
|---|---|---|
| `categoria`, `producto` | sí | catálogo compartido |
| `venta`, `linea_venta` | sí, **solo las del libro abierto** | son las tablas del libro adjunto ([decisión 0025](../decisiones/0025-archivado-anual-rodante.md)); eso acota el volcado a un año en vez de a la vida del negocio |
| `libro_ventas` | **no** | describe los ARCHIVOS de este dispositivo — sus nombres y fechas de corte son suyos y de nadie más. Propagarlo dejaría al otro con filas apuntando a archivos que no existen. Además no tiene `updated_at`, que `RowSyncEngine` exige |
| libros cerrados | **no** | pendiente de un ADR propio: los libros son por dispositivo y una venta podría acabar en dos libros del mismo aparato, contándose doble en los reportes |

Dos detalles del lado del cliente que hacen falta con este modelo: se llama a `prepararPara` **antes** de aplicar (sin libro abierto no hay tabla `venta` donde escribir), y a `recontarDias` **después** — porque las ventas que entran por sync no pasan por la caja y el libro no contaría sus días, así que no rotaría nunca. Se recuenta desde el contenido en vez de incrementar: el sync reenvía las mismas filas y un contador incremental acumularía error.

Un aparato **sin ninguna venta** exporta `venta` y `linea_venta` como listas vacías. Antes lanzaba `no such table`, el servidor devolvía 500 y el cliente se comía la excepción en silencio — con lo cual una instalación nueva tampoco recibía el **catálogo**.

## Estado de implementación (2026-07-28)

- **Descubrimiento** (anunciar rol + descubrir pares): implementado con `bonsoir` — ver [decisión 0021](../decisiones/0021-paquete-mdns-bonsoir.md). En Linux depende de `avahi-daemon` activo en el sistema.
- **Transporte** (`SyncServer` + `SyncClient`): implementado — ver [decisión 0022](../decisiones/0022-protocolo-transporte-sync-shelf-puerto-dinamico.md). Cubre sync **intra-grupo** (pares del mismo rol, pairwise); probado con un test de integración real sobre HTTP (`test/sync_transport_test.dart`).
- **Elección de orquestador** (`SyncGroupCoordinator`): implementado, lógica pura (regla determinista sobre `device_id`s visibles).
- **Resolución de conflictos fila por fila** (`RowSyncEngine`): implementado, lógica pura de LWW — reutilizable tal cual por `TiketdataNotifier` (0017) y por `SyncClient` (0022) vía `RowUpserter`.
- **⚠ Falta — coordinación entre grupos**: el paso 3/4 del diseño de topología (orquestadores de cada rol sincronizando entre sí) todavía no tiene protocolo definido. Mientras no exista, `SyncNotifier.todosLosDispositivosSincronizados` sigue devolviendo `false` siempre (correcto: un Gerente y una Registradora nunca terminan de verse sincronizados entre sí sin ese handshake, que es el caso que le importa a la purga de Producto, 0015).
