# Datos

Ver también: [stack](stack.md) · [sincronización](sincronizacion.md) · [../funciones/ventas](../funciones/ventas.md)

## Reglas comunes a todas las tablas sincronizables

- Primary key: UUID v4
- Columna `updated_at` en ISO-8601 (usada para LWW en sync)
- Columna `deleted_at` (nullable, ISO-8601) — **solo en tablas cuyo ciclo de vida incluye descontinuación** (Producto, Categoria; a futuro Insumo). Borrar = poner `deleted_at` + actualizar `updated_at`; nunca se borra físicamente durante la vida útil de la sync. Las queries de la app filtran `WHERE deleted_at IS NULL`. Venta y LineaVenta **no** llevan esta columna — su ciclo de vida no admite borrado, ver más abajo. Ver [decisión 0005](../decisiones/0005-borrados-en-sync.md) y [decisión 0009](../decisiones/0009-cruds-independientes-por-entidad.md).

## Entidades

Cada entidad tiene su propio ciclo de vida — **ningún CRUD se recicla entre entidades** (ver [decisión 0009](../decisiones/0009-cruds-independientes-por-entidad.md)).

- **Producto**: nombre, imagen (opcional), categoría (opcional, ver Categoria abajo), precio base.
  Ciclo de vida: crear, leer, actualizar, **descontinuar** (soft-delete vía `deleted_at` — ver arriba), **purgar** (borrado físico real, Gerente-only, solo si ya está descontinuado, cero ventas asociadas y todos los dispositivos sincronizados — ver [decisión 0015](../decisiones/0015-purgar-producto-borrado-fisico-condicional.md)). Un producto descontinuado no se borra, solo deja de aparecer en catálogo/ventas nuevas; purgar sí lo borra de verdad, pero solo cuando es 100% seguro para el historial.
- **Venta**: fecha y hora de registro, nota opcional (Detalle), `estado` (`activa` | `revertida`), `motivo_reversion` (TEXT con JSON, solo si `estado = revertida` — ver [decisión 0010](../decisiones/0010-motivo-reversion-como-json.md)), una o más **líneas**.
  Ciclo de vida: **crear** o **revertir** — nunca se edita ni se borra (ni hard ni soft-delete). Revertir es la única transición posible tras crear, para casos de devolución o pedido erróneo; la venta revertida permanece visible para trazabilidad contable pero se excluye de los totales de reportes.
- **LineaVenta**: referencia a Producto **o** un `nombre_libre` escrito a mano (línea libre, sin catálogo — ver [decisión 0016](../decisiones/0016-linea-libre-en-venta.md)), precio aplicado (base o editado en el momento, siempre una copia del precio en ese instante — nunca un lookup en vivo), cantidad, nota descriptiva opcional (típicamente para justificar un precio editado — ver [decisión 0013](../decisiones/0013-nota-por-linea-no-json-en-venta.md)). Inmutable una vez creada la Venta (no se edita por separado).
- **Categoria**: agrupa Productos para interfaz/búsqueda al armar una venta; mismo patrón de descontinuación que Producto. Sin peso en reportes por ahora. Uso concreto de interfaz definido en [decisión 0018](../decisiones/0018-orden-y-busqueda-de-producto.md): agrupación visual (modo "Categoría" del orden de productos) y segundo nivel de ranking en búsqueda (nombre de producto primero, categoría después).
- **(Futuro) Insumo/MateriaPrima**: ciclo de vida propio, aún no definido — no reusará el CRUD de Producto ni el de Venta.

**Rol y contraseña del dispositivo NO son una tabla SQL** — viven en almacenamiento seguro nativo del sistema operativo, no sincronizado entre dispositivos. Ver [decisión 0011](../decisiones/0011-credenciales-almacenamiento-nativo.md) y [roles-y-auth](../funciones/roles-y-auth.md).

Ver [decisión 0008](../decisiones/0008-modelo-venta-multilinea-terminologia.md) para el razonamiento detrás del modelo multi-línea y el renombre Plato → Producto.

## Esquema exacto de columnas

En desarrollo en [esquema-db.md](esquema-db.md) — documento de prototipo con las tablas SQL propuestas y los puntos abiertos a decidir.
