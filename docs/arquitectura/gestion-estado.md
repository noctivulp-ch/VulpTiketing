# Gestión de Estado

Ver también: [stack](stack.md) · [datos](datos.md) · [../decisiones/0009](../decisiones/0009-cruds-independientes-por-entidad.md) · [../decisiones/0014](../decisiones/0014-riverpod-como-gestion-de-estado.md)

**Antes de crear o modificar cualquier Notifier: leer este archivo completo y el ciclo de vida real de la entidad en [datos.md](datos.md). No copiar la forma de otro Notifier "por consistencia" si esa entidad no tiene las mismas operaciones.**

## Elegido: Riverpod

Ver [decisión 0014](../decisiones/0014-riverpod-como-gestion-de-estado.md) para el porqué y el riesgo identificado (Riverpod no impone por sí solo la separación de CRUDs de la [decisión 0009](../decisiones/0009-cruds-independientes-por-entidad.md) — por eso este documento existe: para que la separación quede explícita y concreta, no dependiente de que alguien la recuerde).

## Regla dura

**Un `Notifier`/provider por entidad de negocio, con exactamente los métodos que su ciclo de vida real permite.** Nunca una clase base genérica (`CrudNotifier<T>`, `Repository<T>`) con `create/read/update/delete` compartida entre entidades. Si dos Notifiers se ven parecidos, eso está bien — la duplicación es preferible a una abstracción que no respeta que cada entidad tiene un ciclo de vida distinto (0009).

## Regla dura #2 — responsabilidad única también *dentro* de cada servicio

No basta con "un Notifier por entidad" (regla de arriba). Un servicio que mezcla varias tareas no relacionadas (ej. "descubrir dispositivos en la red" + "resolver conflictos de datos" + "exponer estado a la UI" en una sola clase) es tan problemático como un `CrudNotifier<T>` genérico — solo que la mezcla es de *tareas* en vez de *entidades*. Ver [decisión 0019](../decisiones/0019-descomponer-servicios-responsabilidad-unica.md) para el razonamiento completo detrás de la descomposición de abajo.

## Notifiers y servicios previstos, y sus operaciones permitidas

Esta lista es la referencia concreta contra la que comparar antes de escribir código. Si al implementar aparece una entidad nueva o una operación no listada aquí, **actualizar esta tabla primero**, no solo el código.

### Entidades de negocio (CRUD independiente por entidad — 0009)

| Notifier | Entidad/responsabilidad | Operaciones permitidas | Operaciones que NO debe tener |
|----------|--------------------------|--------------------------|-------------------------------|
| `ProductoNotifier` | Producto — solo escritura + lectura base | crear, leer/listar base (**todos**, descontinuados incluidos), actualizar, **descontinuar**, **recontinuar**, **purgar** (solo si descontinuado + cero ventas asociadas + `SyncNotifier` confirma todos los dispositivos sincronizados — [0015](../decisiones/0015-purgar-producto-borrado-fisico-condicional.md)) | "revertir"; **orden/búsqueda de presentación** (eso es `ProductoQueryProvider`, abajo) |
| `CategoriaNotifier` | Categoria | crear, leer/listar, actualizar, **descontinuar** | eliminar físicamente, "revertir" |
| `VentaEnCursoNotifier` | El "carrito" de una venta que se está armando (antes de guardar) | agregar línea de catálogo, **agregar línea libre** (nombre + precio sin Producto — [0016](../decisiones/0016-linea-libre-en-venta.md)), quitar línea, editar precio/cantidad/nota de una línea, agregar `detalle` general, **guardar** (persiste como Venta `activa`) | editar/borrar una venta ya guardada — esta clase deja de aplicar una vez guardada |
| `VentaNotifier` (o `VentasNotifier` para listados) | Venta ya persistida | leer/listar, **revertir** (exige motivo, cambia `estado` a `revertida`) | crear (eso lo hace `VentaEnCursoNotifier` al guardar), editar, eliminar |
| `CajaNotifier` | Los cortes de caja del día — apertura, medio día, cierre ([0037](../decisiones/0037-corte-de-caja-y-jornada-en-dos-turnos.md)) | **registrar** (y solo el momento que toca: apertura habilita medio día, medio día habilita cierre), leer el estado de la caja de hoy | **actualizar, eliminar** — un corte se cuenta, se valida y se cierra; poder reescribirlo es justo lo que un corte existe para impedir. Tampoco "leer días pasados": el cuadro es de la jornada en curso |
| *(Futuro)* `InsumoNotifier` | Materias primas — ciclo de vida aún no definido | a definir cuando se implemente esta feature | no reusar la forma de `ProductoNotifier` sin volver a evaluar si aplica |

### Presentación derivada (no son entidades, no mutan datos)

| Provider | Responsabilidad | Depende de |
|----------|------------------|------------|
| `ProductoQueryProvider` | Combina lista base + orden + búsqueda para producir la lista final que ve la UI ([0018](../decisiones/0018-orden-y-busqueda-de-producto.md)). Dos salidas: `productoQueryProvider` (solo activos, para vender) y `productoCatalogoProvider` (incluye descontinuados, para el catálogo del Gerente). **Quién ve un descontinuado es presentación, no dato** — la lista base ya no filtra | `ProductoNotifier` (datos) + `PreferenciasNotifier` (orden) + término de búsqueda local de pantalla |
| `reportesProvider` (`FutureProvider.family<ReporteResultado, ReportesParametros>`) | Cálculo de reportes (agrupación por turno/período, ranking excluyendo líneas libres — [reportes.md](../funciones/reportes.md)) | Consulta directa a `venta`/`linea_venta`/`producto` — solo lectura, sin estado propio que mutar |

### Sesión y dispositivo (separado en 3 — 0019)

| Servicio | Responsabilidad | No sabe nada de |
|----------|------------------|-------------------|
| `SesionNotifier` | Rol activo, login/logout — lo que la UI consulta para renderizar condicionalmente | cómo se verifica una contraseña, ni el `device_id` |
| `CredencialesService` | Hashear/verificar la contraseña local (Argon2id — [0011](../decisiones/0011-credenciales-almacenamiento-nativo.md)) | sesión, UI, `device_id` |
| `DeviceIdentityService` | Generar/leer el `device_id` persistente para sync (detalle pendiente, [0007](../decisiones/0007-topologia-sync.md)) | contraseñas, rol, UI |
| `PreferenciasNotifier` | Preferencias de UI locales no sensibles: orden de productos (0018), acento visual (0020) y modo de tema claro/oscuro/sistema (0023), almacenamiento local simple (`shared_preferences`) | nada de esto vive en el almacenamiento seguro — no es sensible, no se mezcla con lo de arriba |

Nunca existe una noción de "cuenta" o CRUD de usuarios — no aplica (0002).

### Sincronización (separado por responsabilidad — 0019)

| Servicio | Responsabilidad | No sabe nada de |
|----------|------------------|-------------------|
| `DeviceDiscoveryService` (`BonsoirDeviceDiscoveryService`) | Anuncia el rol activo de este dispositivo vía mDNS (incluyendo el puerto real de `SyncServer`), descubre pares visibles — **implementado** con `bonsoir` (0021) | LWW, ni qué datos se sincronizan |
| `SyncGroupCoordinator` | Calcula el orquestador del grupo (UUID más bajo visible — 0007) — **implementado**, lógica pura | cómo se mezclan filas |
| `RowSyncEngine` | Aplica LWW fila por fila entre dos conjuntos de datos, dado un `id` y `updated_at` — **implementado**, lógica pura reutilizada por `RowUpserter` | red, mDNS, topología de grupos, cómo llegan las filas |
| `RowUpserter` | Aplica un lote de filas remotas contra una tabla local, fila por fila, vía `RowSyncEngine` — **implementado** ([0022](../decisiones/0022-protocolo-transporte-sync-shelf-puerto-dinamico.md)), compartido entre `SyncClient` y `TiketdataService` | de dónde vinieron las filas (archivo o red) |
| `SyncServer` | Servidor HTTP embebido (`shelf`), expone `GET /sync/exportar` con el contenido completo de las 5 tablas sincronizables, puerto asignado por el SO — **implementado** ([0022](../decisiones/0022-protocolo-transporte-sync-shelf-puerto-dinamico.md)) | quién le pide los datos, ni resolución de conflictos |
| `SyncClient` | Hace *pull* de `/sync/exportar` en un peer y aplica el resultado vía `RowUpserter` — **implementado** ([0022](../decisiones/0022-protocolo-transporte-sync-shelf-puerto-dinamico.md)), probado con round-trip HTTP real en `test/sync_transport_test.dart` | descubrimiento, topología de grupos |
| `SyncNotifier` | Fachada Riverpod-facing: compone `DeviceDiscoveryService` + `SyncServer` + `SyncClient` + `SyncGroupCoordinator`, expone estado (`idle`/`syncing`/`error`) y pares visibles — **sync intra-grupo implementada**. **`todosLosDispositivosSincronizados` sigue devolviendo `false` siempre** — falta la coordinación *entre* grupos vía orquestadores (ver `docs/arquitectura/sincronizacion.md`) | — es pura composición, no reimplementa nada de lo anterior |

### Importación de datos (separado por tipo de archivo — 0019)

| Servicio | Responsabilidad | Reutiliza |
|----------|------------------|-----------|
| `TiketbackNotifier`/`TiketbackService` | Exportar/restaurar el backup completo cifrado — **implementado** (Argon2id + AES-256-GCM, [0006](../decisiones/0006-encriptacion-backup.md)/[0017](../decisiones/0017-importar-datos-tiketdata-vs-tiketback.md)), con prueba de round-trip en `test/tiketback_service_test.dart` | — restaurar es siempre reemplazo total, no usa `RowSyncEngine`. No incluye rol/contraseña/`device_id` en el bundle (defensa en profundidad, ver 0006) |
| `TiketdataNotifier`/`TiketdataService` | Exportar/importar el paquete de catálogo, modo Reemplazar o Fusionar — **implementado**, con pruebas en `test/tiketdata_service_test.dart` (0017) | **`RowSyncEngine`** — mismo mecanismo LWW de sync (método `resolver`, fila por fila), no una copia |

## Gotcha real — `late final` en un campo asignado dentro de `build()`

Bug encontrado en producción (2026-07-29): al importar un catálogo o restaurar
un backup, la app crasheaba con `LateInitializationError: Field '_dao' has
already been initialized`. Afectaba a `ProductoNotifier`, `CategoriaNotifier`
y `VentaNotifier` — los tres declaraban `late final XDao _dao;` y lo asignaban
dentro de `build()`.

La causa: para un `NotifierProvider`/`AsyncNotifierProvider` normal (sin
`autoDispose`), Riverpod **reutiliza la misma instancia** de Notifier en cada
rebuild — `ref.invalidate(provider)` o que cambie una dependencia observada
(acá, `databaseProvider` al restaurar un backup) no crea un Notifier nuevo,
vuelve a llamar `build()` sobre el mismo objeto. Un campo `late final`
asignado ahí revienta en la segunda vuelta. Fix: `late` sin `final` en los
tres Notifiers. Regresión cubierta en `test/producto_notifier_test.dart`
(invalida el provider dos veces seguidas y confirma que no revienta).

**Regla derivada:** cualquier campo de un Notifier que se asigna dentro de
`build()` (no en un constructor aparte) debe ser `late`, nunca `late final`.
Si un campo realmente necesita ser inmutable, se asigna en el constructor,
no en `build()`.

### La misma causa, con el síntoma invertido (2026-07-30)

`VentaEnCursoNotifier` tenía `final String ventaIdBorrador = _uuid.v4();`
como **inicializador de campo**, con un comentario que afirmaba que
`ref.invalidateSelf()` lo regeneraba. No lo regenera: como Riverpod reutiliza
la instancia, un inicializador de campo corre **una sola vez en la vida del
provider**.

Consecuencia: el id de venta nunca cambiaba y **solo se podía guardar una
venta por sesión** — la segunda moría con `UNIQUE constraint failed:
venta.id`. En una app de punto de venta, la caja dejaba de funcionar después
del primer cobro.

Es la misma causa raíz que el `LateInitializationError` de arriba, con el
síntoma al revés: allá el problema era una reasignación que explotaba, acá una
asignación que **nunca ocurría**. Por eso el primer caso se detectó rápido y
este sobrevivió: no lanza nada, solo hace lo incorrecto en silencio.

Fix: `late String` (sin `final`) asignado dentro de `build()`, que sí se
vuelve a ejecutar en cada invalidación. Regresión en
`test/venta_en_curso_notifier_test.dart` — guarda tres ventas seguidas y exige
tres ids distintos y tres filas persistidas.

**Regla derivada 2:** un Notifier **nunca** usa inicializadores de campo para
valores que deban renovarse por ciclo (ids, timestamps, borradores). Van en
`build()`. Un inicializador de campo en un Notifier solo sirve para
dependencias inmutables que viven tanto como el provider (por ejemplo un
servicio sin estado).

Y una lección de prueba: ninguna prueba hacía **dos** ventas seguidas, que es
el caso más normal del negocio. Cuando una operación se repite en uso real,
probarla una sola vez no la cubre.

## Ejemplo concreto de lo que NO hacer

```dart
// ❌ NO: abstracción genérica compartida entre entidades con ciclos de vida distintos
abstract class CrudNotifier<T> extends Notifier<List<T>> {
  Future<void> create(T item);
  Future<void> update(T item);
  Future<void> delete(String id); // Venta no tiene "delete" — esto la fuerza a mentir con un no-op o una excepción
}
```

```dart
// ✅ Sí: cada Notifier con exactamente lo que su entidad permite
class ProductoNotifier extends Notifier<List<Producto>> {
  Future<void> crear(Producto p) { /* ... */ }
  Future<void> actualizar(Producto p) { /* ... */ }
  Future<void> descontinuar(String id) { /* ... */ } // soft-delete, no "delete"
}

class VentaNotifier extends Notifier<List<Venta>> {
  Future<void> revertir(String id, MotivoReversion motivo) { /* ... */ } // no existe "actualizar" ni "eliminar"
}
```
