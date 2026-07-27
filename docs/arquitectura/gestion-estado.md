# Gestión de Estado

Ver también: [stack](stack.md) · [datos](datos.md) · [../decisiones/0009](../decisiones/0009-cruds-independientes-por-entidad.md) · [../decisiones/0014](../decisiones/0014-riverpod-como-gestion-de-estado.md)

**Antes de crear o modificar cualquier Notifier: leer este archivo completo y el ciclo de vida real de la entidad en [datos.md](datos.md). No copiar la forma de otro Notifier "por consistencia" si esa entidad no tiene las mismas operaciones.**

## Elegido: Riverpod

Ver [decisión 0014](../decisiones/0014-riverpod-como-gestion-de-estado.md) para el porqué y el riesgo identificado (Riverpod no impone por sí solo la separación de CRUDs de la [decisión 0009](../decisiones/0009-cruds-independientes-por-entidad.md) — por eso este documento existe: para que la separación quede explícita y concreta, no dependiente de que alguien la recuerde).

## Regla dura

**Un `Notifier`/provider por entidad de negocio, con exactamente los métodos que su ciclo de vida real permite.** Nunca una clase base genérica (`CrudNotifier<T>`, `Repository<T>`) con `create/read/update/delete` compartida entre entidades. Si dos Notifiers se ven parecidos, eso está bien — la duplicación es preferible a una abstracción que no respeta que cada entidad tiene un ciclo de vida distinto (0009).

## Notifiers previstos y sus operaciones permitidas

Esta lista es la referencia concreta contra la que comparar antes de escribir código. Si al implementar aparece una entidad nueva o una operación no listada aquí, **actualizar esta tabla primero**, no solo el código.

| Notifier | Entidad/responsabilidad | Operaciones permitidas | Operaciones que NO debe tener |
|----------|--------------------------|--------------------------|-------------------------------|
| `ProductoNotifier` | Producto | crear, leer/listar (filtrando `deleted_at IS NULL` por defecto), actualizar, **descontinuar** | eliminar físicamente, "revertir" |
| `CategoriaNotifier` | Categoria | crear, leer/listar, actualizar, **descontinuar** | eliminar físicamente, "revertir" |
| `VentaEnCursoNotifier` | El "carrito" de una venta que se está armando (antes de guardar) | agregar línea, quitar línea, editar precio/cantidad/nota de una línea, agregar `detalle` general, **guardar** (persiste como Venta `activa`) | editar/borrar una venta ya guardada — esta clase deja de aplicar una vez guardada |
| `VentaNotifier` (o `VentasNotifier` para listados) | Venta ya persistida | leer/listar, **revertir** (exige motivo, cambia `estado` a `revertida`) | crear (eso lo hace `VentaEnCursoNotifier` al guardar), editar, eliminar |
| `AuthNotifier` / `DeviceConfigNotifier` | Rol y contraseña de este dispositivo (almacenamiento seguro nativo, no SQL — [0011](../decisiones/0011-credenciales-almacenamiento-nativo.md)) | leer rol activo, cambiar contraseña local, (futuro) leer/generar `device_id` | cualquier noción de "cuenta" o CRUD de usuarios — no existe tal cosa (0002) |
| `SyncNotifier`/`SyncService` | Orquesta descubrimiento mDNS + sync LWW ([0007](../decisiones/0007-topologia-sync.md)) | iniciar sync, detener sync, exponer estado (`idle`/`syncing`/`error`) como Stream | create/read/update/delete — no es una entidad de negocio, es un servicio |
| `ReportesNotifier` (o providers derivados, ej. `FutureProvider` por consulta) | Cálculo de reportes (agrupación por turno/período) | consultar/leer únicamente — todo se deriva de `Venta`/`LineaVenta`, no tiene estado propio que mutar | cualquier operación de escritura |
| *(Futuro)* `InsumoNotifier` | Materias primas — ciclo de vida aún no definido | a definir cuando se implemente esta feature | no reusar la forma de `ProductoNotifier` sin volver a evaluar si aplica |

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
