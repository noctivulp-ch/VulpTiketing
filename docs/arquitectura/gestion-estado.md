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
| `ProductoNotifier` | Producto — solo escritura + lectura base | crear, leer/listar base (filtrando `deleted_at IS NULL`), actualizar, **descontinuar**, **purgar** (solo si descontinuado + cero ventas asociadas + `SyncNotifier` confirma todos los dispositivos sincronizados — [0015](../decisiones/0015-purgar-producto-borrado-fisico-condicional.md)) | "revertir"; **orden/búsqueda de presentación** (eso es `ProductoQueryProvider`, abajo) |
| `CategoriaNotifier` | Categoria | crear, leer/listar, actualizar, **descontinuar** | eliminar físicamente, "revertir" |
| `VentaEnCursoNotifier` | El "carrito" de una venta que se está armando (antes de guardar) | agregar línea de catálogo, **agregar línea libre** (nombre + precio sin Producto — [0016](../decisiones/0016-linea-libre-en-venta.md)), quitar línea, editar precio/cantidad/nota de una línea, agregar `detalle` general, **guardar** (persiste como Venta `activa`) | editar/borrar una venta ya guardada — esta clase deja de aplicar una vez guardada |
| `VentaNotifier` (o `VentasNotifier` para listados) | Venta ya persistida | leer/listar, **revertir** (exige motivo, cambia `estado` a `revertida`) | crear (eso lo hace `VentaEnCursoNotifier` al guardar), editar, eliminar |
| *(Futuro)* `InsumoNotifier` | Materias primas — ciclo de vida aún no definido | a definir cuando se implemente esta feature | no reusar la forma de `ProductoNotifier` sin volver a evaluar si aplica |

### Presentación derivada (no son entidades, no mutan datos)

| Provider | Responsabilidad | Depende de |
|----------|------------------|------------|
| `ProductoQueryProvider` | Combina lista base + orden + búsqueda para producir la lista final que ve la UI ([0018](../decisiones/0018-orden-y-busqueda-de-producto.md)) | `ProductoNotifier` (datos) + `PreferenciasNotifier` (orden) + término de búsqueda local de pantalla |
| `reportesProvider` (`FutureProvider.family<ReporteResultado, ReportesParametros>`) | Cálculo de reportes (agrupación por turno/período, ranking excluyendo líneas libres — [reportes.md](../funciones/reportes.md)) | Consulta directa a `venta`/`linea_venta`/`producto` — solo lectura, sin estado propio que mutar |

### Sesión y dispositivo (separado en 3 — 0019)

| Servicio | Responsabilidad | No sabe nada de |
|----------|------------------|-------------------|
| `SesionNotifier` | Rol activo, login/logout — lo que la UI consulta para renderizar condicionalmente | cómo se verifica una contraseña, ni el `device_id` |
| `CredencialesService` | Hashear/verificar la contraseña local (Argon2id — [0011](../decisiones/0011-credenciales-almacenamiento-nativo.md)) | sesión, UI, `device_id` |
| `DeviceIdentityService` | Generar/leer el `device_id` persistente para sync (detalle pendiente, [0007](../decisiones/0007-topologia-sync.md)) | contraseñas, rol, UI |
| `PreferenciasNotifier` | Preferencias de UI locales no sensibles: orden de productos (0018) y acento visual (0020), almacenamiento local simple (`shared_preferences`) | nada de esto vive en el almacenamiento seguro — no es sensible, no se mezcla con lo de arriba |

Nunca existe una noción de "cuenta" o CRUD de usuarios — no aplica (0002).

### Sincronización (separado en 4 — 0019)

| Servicio | Responsabilidad | No sabe nada de |
|----------|------------------|-------------------|
| `DeviceDiscoveryService` | Anuncia el rol activo de este dispositivo vía mDNS, descubre pares visibles | LWW, ni qué datos se sincronizan |
| `SyncGroupCoordinator` | Calcula el orquestador del grupo (UUID más bajo visible — 0007) y si hay tareas pendientes | cómo se mezclan filas |
| `RowSyncEngine` | Aplica LWW fila por fila entre dos conjuntos de datos, dado un `id` y `updated_at` — **reutilizada también por `TiketdataNotifier`** (ver abajo) | red, mDNS, topología de grupos |
| `SyncNotifier` | Fachada Riverpod-facing: compone las tres anteriores, expone estado (`idle`/`syncing`/`error`) y si todos los dispositivos están sincronizados (consultado por `ProductoNotifier.purgar`, 0015) | — es pura composición, no reimplementa nada de lo anterior |

### Importación de datos (separado por tipo de archivo — 0019)

| Servicio | Responsabilidad | Reutiliza |
|----------|------------------|-----------|
| `TiketbackNotifier`/`TiketbackService` | Exportar/restaurar el backup completo cifrado ([0006](../decisiones/0006-encriptacion-backup.md)/[0017](../decisiones/0017-importar-datos-tiketdata-vs-tiketback.md)) | — restaurar es siempre reemplazo total, no usa `RowSyncEngine` |
| `TiketdataNotifier`/`TiketdataService` | Exportar/importar el paquete de catálogo, modo Reemplazar o Fusionar (0017) | **`RowSyncEngine`** — mismo mecanismo LWW de sync, no una copia |

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
