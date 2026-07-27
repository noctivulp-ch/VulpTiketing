# Datos

Ver también: [stack](stack.md) · [sincronización](sincronizacion.md) · [../funciones/ventas](../funciones/ventas.md)

## Reglas comunes a todas las tablas sincronizables

- Primary key: UUID v4
- Columna `updated_at` en ISO-8601 (usada para LWW en sync)
- Columna `deleted_at` (nullable, ISO-8601) — soft-delete/tombstone. Borrar = poner `deleted_at` + actualizar `updated_at`; nunca se borra físicamente durante la vida útil de la sync. Las queries de la app filtran `WHERE deleted_at IS NULL`. Ver [decisión 0005](../decisiones/0005-borrados-en-sync.md).

## Entidades

Cada entidad tiene su propio ciclo de vida — **ningún CRUD se recicla entre entidades** (ver [decisión 0009](../decisiones/0009-cruds-independientes-por-entidad.md)).

- **Producto**: nombre, imagen (opcional), precio base.
  Ciclo de vida: crear, leer, actualizar, **descontinuar** (soft-delete vía `deleted_at` — ver arriba). Un producto descontinuado no se borra, solo deja de aparecer en catálogo/ventas nuevas.
- **Venta**: fecha y hora de registro, nota opcional (Detalle), `estado` (`activa` | `revertida`), `motivo` (TEXT con JSON, solo si `estado = revertida` — ver [decisión 0010](../decisiones/0010-motivo-reversion-como-json.md)), una o más **líneas**.
  Ciclo de vida: **crear** o **revertir** — nunca se edita ni se borra (ni hard ni soft-delete). Revertir es la única transición posible tras crear, para casos de devolución o pedido erróneo; la venta revertida permanece visible para trazabilidad contable pero se excluye de los totales de reportes.
- **LineaVenta**: referencia a Producto, precio aplicado (base o editado en el momento, siempre una copia del precio en ese instante — nunca un lookup en vivo), cantidad, nota descriptiva opcional (típicamente para justificar un precio editado — ver [decisión 0013](../decisiones/0013-nota-por-linea-no-json-en-venta.md)). Inmutable una vez creada la Venta (no se edita por separado).
- **Categoria**: agrupa Productos para interfaz/búsqueda al armar una venta; mismo patrón de descontinuación que Producto. Sin peso en reportes por ahora.
- **(Futuro) Insumo/MateriaPrima**: ciclo de vida propio, aún no definido — no reusará el CRUD de Producto ni el de Venta.

**Rol y contraseña del dispositivo NO son una tabla SQL** — viven en almacenamiento seguro nativo del sistema operativo, no sincronizado entre dispositivos. Ver [decisión 0011](../decisiones/0011-credenciales-almacenamiento-nativo.md) y [roles-y-auth](../funciones/roles-y-auth.md).

Ver [decisión 0008](../decisiones/0008-modelo-venta-multilinea-terminologia.md) para el razonamiento detrás del modelo multi-línea y el renombre Plato → Producto.

## Esquema exacto de columnas

En desarrollo en [esquema-db.md](esquema-db.md) — documento de prototipo con las tablas SQL propuestas y los puntos abiertos a decidir.
