# 0015 — Purgar Producto: borrado físico condicional

**Fecha:** 2026-07-27
**Estado:** Aceptada

## Contexto

Al diseñar la Ventana 3 (CRUD de Producto), el usuario señaló que "descontinuar" (soft-delete, [0005](0005-borrados-en-sync.md)) no resuelve un problema real: productos creados por error humano (duplicados, productos custom de un solo uso que nunca se van a reutilizar) se acumulan como descontinuados para siempre, sin forma de limpiarlos de verdad.

Un borrado físico sin condiciones no es aceptable: `linea_venta.producto_id` referencia `producto.id`, y si un producto alguna vez fue vendido, borrarlo de verdad rompería el reporte histórico de esa venta — inaceptable para una app cuya función principal es la contabilidad.

## Decisión

Agregar una acción **"Purgar"** (Gerente-only, distinta de "Descontinuar" y de "eliminar línea" del carrito de venta), habilitada **solo cuando se cumplen las tres condiciones**:

1. El producto ya está descontinuado (`deleted_at IS NOT NULL`).
2. Cero filas de `linea_venta` referencian su `producto_id` (nunca fue vendido).
3. Se confirma que **todos los dispositivos conocidos están sincronizados** — reutiliza la señal "sin tareas de sync pendientes" ya modelada en [decisión 0007](0007-topologia-sync.md), no se inventa un mecanismo nuevo.

Al purgar: `DELETE` físico real de la fila. No hace falta tombstone para esta operación — dado que se confirmó que ningún dispositivo tiene una venta pendiente sin sincronizar que referencie este producto, ningún dispositivo necesita enterarse de la purga después del hecho.

## Por qué el gate de sincronización es necesario

"Cero ventas" visto desde un solo dispositivo no garantiza que otro dispositivo, todavía offline, no tenga una venta pendiente sin sincronizar que use ese producto. Sin el gate, purgar sería una apuesta: si ese dispositivo offline sincroniza después con una `linea_venta` que referencia un `producto_id` que ya no existe, el registro queda huérfano — se rompe exactamente lo que 0005 quería evitar. Exigir sincronización completa antes de habilitar la purga cierra ese hueco sin necesitar un protocolo de consenso distribuido.

## Alternativas descartadas

- **Purgar sin el gate de sincronización** — más simple, pero con riesgo real de corromper un reporte histórico si un dispositivo offline tenía una venta pendiente con ese producto.
- **Log de IDs purgados aparte** (opción B ya descartada en [0005](0005-borrados-en-sync.md)) — innecesario aquí: el gate de sincronización completa ya garantiza que todos los dispositivos "están de acuerdo" (sin ventas, sincronizados) en el momento de purgar, no hace falta que ningún dispositivo se entere después.
- **No purgar nunca, solo descontinuar** — deja sin resolver el problema real de acumulación de duplicados/errores que señaló el usuario.

## Consecuencias

- El servicio de sync (`SyncNotifier`, [0007](0007-topologia-sync.md)) debe exponer un estado consultable de "todos los dispositivos conocidos están sincronizados" — detalle a definir al implementar sync. La acción "Purgar" en la UI queda deshabilitada mientras ese estado no sea `true`.
- No modifica el mecanismo de tombstone de [0005](0005-borrados-en-sync.md) — sigue siendo necesario para todo borrado que no cumpla las tres condiciones de purgar (o para cualquier otra tabla con ciclo de vida de descontinuación, ej. Categoria).
- Ver `docs/arquitectura/gestion-estado.md` — `ProductoNotifier` gana la operación `purgar`.
