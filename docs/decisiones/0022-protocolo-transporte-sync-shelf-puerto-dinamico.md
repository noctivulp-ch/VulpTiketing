# 0022 — Protocolo de transporte de sync: HTTP embebido (`shelf`) + puerto dinámico

**Fecha:** 2026-07-28
**Estado:** Aceptada

## Contexto

0021 resolvió el **descubrimiento** (mDNS vía `bonsoir`): cada dispositivo ya puede anunciar su rol y ver qué pares del mismo rol están visibles en la red local. Pero descubrir un peer no es lo mismo que intercambiar datos con él — faltaba decidir **cómo** dos dispositivos que ya se descubrieron mueven filas entre sí. Sin esto, `SyncNotifier.todosLosDispositivosSincronizados` no podía ser otra cosa que `false`: no había ningún mecanismo real de intercambio.

## Opciones consideradas

| Opción | Evaluación |
|---|---|
| HTTP embebido (`shelf`) | Puro Dart, sin código nativo por plataforma. El formato de filas ya es JSON-serializable (reutilizado de `.tiketdata`, 0017). Semántica pull simple (`GET /sync/exportar`) alcanza para el volumen de una soda pequeña. |
| TCP crudo con protocolo propio | Evita la dependencia, pero obliga a diseñar framing de mensajes a mano (dónde empieza/termina cada payload) — trabajo y superficie de bugs sin beneficio real frente a HTTP. |
| WebSocket | Pensado para streaming bidireccional en tiempo real; la sync aquí es periódica/best-effort (0007), no hay necesidad de mantener una conexión persistente. |
| gRPC | Requiere codegen y un runtime más pesado; sobredimensionado para un endpoint de "dame tus filas". |

## Decisión

Servidor HTTP embebido con el paquete `shelf` (puro Dart, verificado que compila limpio en Linux antes de comprometerse — mismo criterio de debida diligencia que con `bonsoir` y `file_picker`). Cada dispositivo:

- Levanta un `SyncServer` (`lib/features/sync/sync_server.dart`) que expone `GET /sync/exportar`, devolviendo el contenido completo (JSON) de las 4 tablas sincronizables: `categoria`, `producto`, `venta`, `linea_venta`.
- Usa un `SyncClient` (`lib/features/sync/sync_client.dart`, sobre `dart:io HttpClient`, sin dependencia nueva) para hacer *pull* de cada peer descubierto del mismo rol y aplicar sus filas.

### Puerto: asignado por el SO, nunca fijo

La primera versión de `DeviceDiscoveryService` traía un puerto hardcodeado (`4321`) marcado como "provisional" — nunca se justificó, era un placeholder sin investigación. Al revisarlo, la corrección no es "elegir mejor número" sino **eliminar la necesidad de cualquier número fijo**:

- `SyncServer.iniciar()` hace `bind` a `InternetAddress.anyIPv4, 0` — el `0` le pide al sistema operativo que asigne cualquier puerto libre.
- Ese puerto real (`HttpServer.port`) se pasa a `DeviceDiscoveryService.anunciar(..., puerto: puerto)`, que lo publica como parte del registro mDNS (`BonsoirService(port: puerto, ...)`).
- Como el descubrimiento siempre precede a la conexión (no se puede sincronizar con un peer que no se descubrió primero), cada dispositivo aprende el puerto real de cada peer vía `PeerVisible.puerto` — nunca necesita adivinarlo ni coordinarlo con nadie.

Esto es el patrón estándar de Zeroconf/Bonjour (mismo principio detrás de por qué servicios como AirPrint o Chromecast no usan puertos fijos) y elimina por completo el riesgo de colisión de puertos entre instancias de la app corriendo en la misma red, o con cualquier otro proceso del sistema.

### Exportación completa, sin filtro incremental

`GET /sync/exportar` devuelve **todas** las filas de las 4 tablas en cada llamada, sin filtrar por `updated_at` desde la última sync. Para el volumen esperado de una soda pequeña esto es simple y suficientemente rápido en LAN; no hay necesidad real de una consulta incremental todavía. Se puede agregar después (ej. `GET /sync/exportar?desde=<timestamp>`) sin romper el contrato del endpoint actual.

A diferencia de `.tiketdata` (que solo exporta catálogo activo, sin `deleted_at`, pensado para compartir un catálogo plantilla), `/sync/exportar` incluye filas con `deleted_at` — la sync real entre dispositivos del mismo negocio debe propagar tombstones (0005), de lo contrario un producto descontinuado en un dispositivo "resucitaría" al sincronizar con otro que todavía no se enteró.

### Sin autenticación

El endpoint no exige credenciales. Esto es coherente con el modelo de amenaza ya establecido en 0002: la red local se asume compuesta por dispositivos de confianza del mismo negocio; el objetivo de la app es defender contra terceros externos, no contra un adversario dentro de la misma LAN. Añadir autenticación aquí sería una capa de seguridad para un actor que este diseño nunca se propuso frenar.

### Reutilización de `RowUpserter`

La lógica de "aplicar filas remotas con resolución LWW" ya existía duplicada en `TiketdataService._upsertConLww`. Se extrajo a `RowUpserter` (`lib/features/sync/row_upserter.dart`) y ahora la usan tanto `TiketdataService` (merge desde archivo `.tiketdata`) como `SyncClient` (merge desde un peer de red). Esto **no** contradice 0009 (que prohíbe reciclar CRUDs entre entidades de negocio distintas): `RowUpserter` no es un CRUD de entidad, es una utilidad de infraestructura ("aplicar un lote de filas remotas contra una tabla, fila por fila, con LWW") que no sabe nada de qué tabla es ni de las reglas de negocio de esa entidad.

## Alcance NO resuelto por esta decisión

Esta decisión resuelve la sync **intra-grupo** (pares del mismo rol se sincronizan entre sí, pairwise). El paso 3/4 del diseño de topología (0007) — coordinación *entre* grupos vía los orquestadores electos de cada rol (Gerente ↔ Registradora) — sigue sin protocolo definido. Por eso `SyncNotifier.todosLosDispositivosSincronizados` sigue devolviendo `false`: sin ese handshake entre orquestadores, un Gerente y una Registradora nunca terminan de verse sincronizados entre sí, que es justo el caso que le importa a la purga de Producto (0015).

## Consecuencias

- `pubspec.yaml` agrega `shelf: ^1.4.2`.
- `DeviceDiscoveryService.anunciar()` gana un parámetro `puerto` requerido; `PeerVisible` gana un campo `puerto`.
- Nuevos archivos: `lib/features/sync/sync_server.dart`, `lib/features/sync/sync_client.dart`, `lib/features/sync/row_upserter.dart`.
- `TiketdataService` se refactoriza para usar `RowUpserter` en vez de su lógica privada duplicada.
- `SyncNotifier.iniciarSync()` ahora arranca un `SyncServer`, obtiene su puerto real, lo anuncia, y sincroniza (best-effort, un peer inalcanzable no detiene el ciclo) con cada par descubierto del mismo rol usando `SyncClient`.
- Test de integración real (`test/sync_transport_test.dart`) cubre el round-trip HTTP completo entre dos bases SQLite in-memory independientes: filas nuevas, propagación de tombstones, y resolución LWW.
