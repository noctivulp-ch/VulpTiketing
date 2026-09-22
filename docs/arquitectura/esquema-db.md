# Esquema de Base de Datos — Prototipo

**Estado:** mayormente cerrado. Cada decisión de columna/tipo se formaliza como ADR apenas se cierra (no se espera a cerrar todo el documento). Solo quedan abiertos `device_id` (nota abajo) e índices (bajo riesgo).

Ver también: [datos](datos.md) · [stack](stack.md) · [../decisiones/0005](../decisiones/0005-borrados-en-sync.md) · [../decisiones/0009](../decisiones/0009-cruds-independientes-por-entidad.md) · [../decisiones/0010](../decisiones/0010-motivo-reversion-como-json.md) · [../decisiones/0011](../decisiones/0011-credenciales-almacenamiento-nativo.md) · [../decisiones/0012](../decisiones/0012-precios-como-real.md) · [../decisiones/0013](../decisiones/0013-nota-por-linea-no-json-en-venta.md)

## Reglas comunes (recordatorio)

- PK: `TEXT` con UUID v4
- `updated_at TEXT` en ISO-8601, usado por LWW en sync
- `deleted_at TEXT` (nullable, ISO-8601) — **solo** en tablas cuyo ciclo de vida incluye borrado/descontinuación (ver ⚠ punto 1 abajo, hay una inconsistencia a resolver)

---

## Categoria

Agrupa productos para navegación/búsqueda al armar una venta — no tiene peso en reportes por ahora. Tabla normalizada (en vez de texto libre en `producto`) para evitar categorías inconsistentes por typos ("Bebidas" vs "bebida").

```sql
CREATE TABLE categoria (
  id            TEXT PRIMARY KEY,      -- UUID v4
  nombre        TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT                   -- NULL = activa. Set = descontinuada, mismo patrón que Producto
);
```

## Producto

```sql
CREATE TABLE producto (
  id            TEXT PRIMARY KEY,       -- UUID v4
  nombre        TEXT NOT NULL,
  imagen        TEXT,                   -- ruta/URI local a la imagen, opcional
  categoria_id  TEXT REFERENCES categoria(id),  -- nullable: un producto puede no tener categoría
  precio_base   REAL NOT NULL,          -- colones (₡) — REAL en vez de centavos, ver decisión 0012
  variantes     TEXT,                   -- JSON: [{id, nombre, precio, porDefecto?}, …]; NULL = sin variantes (0039)
  tasa_iva      REAL,                   -- 0.13, 0.04, 0.02, 0.01, 0; NULL = la por defecto de Ajustes (0042, solo régimen general)
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT                    -- NULL = activo. Set = descontinuado (0005)
);
```

**`producto.variantes`** son las formas de vender el mismo producto a otro
precio —tamaños, cortes, con o sin acompañamiento— como JSON dentro de la
fila, no como tabla: una variante se crea, edita y borra en el formulario del
producto y muere con él, así que no es una entidad ni tiene Notifier propio.
Con variantes, `precio_base` es el precio de la **por defecto**. Cada variante lleva un `id` estable
para que el costeo pueda apuntarle aunque se renombre. `NULL` y `[]` son lo
mismo y se guarda siempre `NULL`. Ver
[decisión 0039](../decisiones/0039-variantes-de-producto-como-json.md).

**Ciclo de vida completo:** crear, leer, actualizar, **descontinuar** (soft-delete, arriba), y **purgar** — borrado físico real, solo Gerente, solo si ya está descontinuado, tiene cero `linea_venta` que lo referencien, y todos los dispositivos conocidos están sincronizados. Ver [decisión 0015](../decisiones/0015-purgar-producto-borrado-fisico-condicional.md).

**`producto.imagen`** guarda una **referencia al banco de imágenes**, no una
ruta: `abs:<semilla>` para una figura de fábrica, o el **nombre** de un archivo
del banco. Solo el nombre porque el directorio de datos cambia entre
instalaciones y entre sistemas. El banco es local y no se sincroniza; una
referencia que no resuelve se ve como la figura propia del producto. Ver
[decisión 0033](../decisiones/0033-banco-de-imagenes.md).

## Venta

```sql
CREATE TABLE venta (
  id                TEXT PRIMARY KEY,   -- UUID v4
  fecha_hora        TEXT NOT NULL,      -- ISO-8601, usado para turnos/reportes
  detalle           TEXT,               -- nota opcional, libre
  estado            TEXT NOT NULL DEFAULT 'activa'
                     CHECK (estado IN ('activa', 'revertida')),
  motivo_reversion  TEXT,               -- JSON, solo si estado='revertida' (0010)
  metodo_pago       TEXT NOT NULL DEFAULT 'efectivo'
                     CHECK (metodo_pago IN ('efectivo', 'sinpe')),
  referencia_pago   TEXT,               -- identificador de la transferencia, anotado después (0032)
  updated_at        TEXT NOT NULL
  -- sin deleted_at a propósito: una Venta nunca se borra, solo cambia de estado (0009)
  -- sin campo de total a propósito: se calcula sumando linea_venta, nunca se duplica aquí (ver nota abajo)
);
```

**Por qué el método de pago vive acá y no en una tabla `pago`:** es una relación
1:1 obligatoria con dos campos. Una tabla aparte obligaría al sync a conocer una
quinta tabla, a cada libro a crearla y migrarla, y a toda consulta de ventas a
cargar con una junta — sin dar nada hoy. Si algún día hace falta un pago **mixto**
(parte efectivo, parte transferencia), la tabla se agrega entonces y estas dos
columnas se migran a ella. Ver [decisión 0032](../decisiones/0032-metodo-de-pago-en-la-venta.md).

**`referencia_pago` es la única columna que se escribe después de guardar la
venta**, aparte de la reversión. No es una edición de la venta: es una anotación
sobre cómo entró la plata, y no toca importes, líneas ni estado. Los libros ya
escritos ganan las dos columnas **al adjuntarse** —un libro es un archivo suelto
que puede venir de otro aparato o de un backup viejo—, con `ADD COLUMN`, que en
SQLite no reescribe las filas existentes.

**Por qué no hay un campo de total:** guardar un total en `venta` sería un valor derivado y redundante frente a la suma de sus líneas — con datos duplicados, un bug en cualquier punto que actualice uno y no el otro genera un total mentiroso, justo el tipo de error que una app de contabilidad no se puede permitir. Se calcula con `SUM(precio_aplicado * cantidad)` al leer. Si algún día el volumen de datos lo justificara, se podría agregar como columna de caché — pero para una soda pequeña con SQLite local no hay necesidad real de esa optimización.

## LineaVenta

```sql
CREATE TABLE linea_venta (
  id               TEXT PRIMARY KEY,    -- UUID v4
  venta_id         TEXT NOT NULL REFERENCES venta(id),
  producto_id      TEXT REFERENCES producto(id),  -- nullable: NULL si es línea libre (0016)
  nombre_libre     TEXT,                -- solo si producto_id IS NULL: nombre escrito a mano
  precio_aplicado  REAL NOT NULL,       -- "foto" del precio al momento de vender, nunca vacío
  cantidad         INTEGER NOT NULL DEFAULT 1,
  nota             TEXT,                -- descriptivo opcional, típicamente para justificar precio_aplicado distinto al base; NULL si no se escribió
  variante         TEXT,                -- NOMBRE de la variante vendida, foto del día; NULL si el producto no tenía (0039)
  updated_at       TEXT NOT NULL,
  CHECK (
    (producto_id IS NOT NULL AND nombre_libre IS NULL) OR
    (producto_id IS NULL AND nombre_libre IS NOT NULL)
  )
  -- sin deleted_at: inmutable, vive y muere con su Venta (0009)
);
```

**Sobre `nombre_libre`:** permite agregar una línea de venta sin que exista un Producto de catálogo — casos custom de un solo uso (ej. un descuento puntual para un cliente específico) que nunca se van a repetir, sin ensuciar el inventario. Ver [decisión 0016](../decisiones/0016-linea-libre-en-venta.md). Una línea libre nunca bloquea una purga de Producto (0015) porque, por definición, no referencia ninguno.

**Sobre `precio_aplicado`:** nunca queda vacío. Al agregar un producto a una venta, el campo se llena automáticamente con el `precio_base` del producto *en ese momento* (una copia, no una referencia viva; el placeholder de "precio base" en el input es puro comportamiento de UI, no requiere nada adicional en la base), y el usuario puede sobreescribirlo antes de guardar. Es intencional que sea una copia y no un lookup a `producto.precio_base`: si el precio base cambia después, las ventas ya registradas deben conservar el precio real que se cobró ese día — de lo contrario los reportes históricos cambiarían solos cada vez que se actualiza el catálogo.

**Sobre `variante`:** el nombre de la variante vendida, y no su `id`, por la
misma razón que `precio_aplicado` es una copia: si "Grande" pasa a llamarse
"Mediano" el año que viene, el libro de hoy sigue diciendo lo que se vendió
hoy. Los reportes agrupan por `(producto_id, variante)`. Ver
[decisión 0039](../decisiones/0039-variantes-de-producto-como-json.md).

**Sobre `nota`:** descriptivo opcional por línea, pensado principalmente para justificar un `precio_aplicado` distinto al `precio_base` (ej. "promoción", "cliente frecuente", "producto en mal estado"), aunque nada impide usarlo para cualquier otra anotación puntual de esa línea. Es distinta de `venta.detalle` (nota general de toda la venta). Va como columna `TEXT` simple en la propia fila — no como JSON — porque cada línea ya es su propia fila; un JSON en `venta` keyed por nombre de producto colisionaría si el mismo producto aparece dos veces en la misma venta con notas distintas (ver [decisión 0013](../decisiones/0013-nota-por-linea-no-json-en-venta.md)).

## CorteCaja

Los tres conteos de caja del día ([decisión 0037](../decisiones/0037-corte-de-caja-y-jornada-en-dos-turnos.md)).

Vive en la base **principal** y no en el libro de ventas aunque sea un dato diario: son tres filas al día —mil al año— y el libro existe para lo que crece sin techo ([0025](../decisiones/0025-archivado-anual-rodante.md)). Meterlas ahí obligaría a abrir libros viejos para leer un número de hoy.

```sql
CREATE TABLE corte_caja (
  id            TEXT PRIMARY KEY,      -- UUID v4
  dia           TEXT NOT NULL,         -- '2026-08-10'. Redundante con fecha_hora a propósito:
                                       -- la regla de orden es POR DÍA, y comparar una fecha
                                       -- suelta es más barato y menos delicado que recortar
                                       -- un instante con zona horaria en cada consulta
  momento       TEXT NOT NULL,         -- 'apertura' | 'medioDia' | 'cierre'
  monto         REAL NOT NULL,         -- lo que QUEDA en la caja, no lo que se contó: en el
                                       -- cambio de turno se guarda la mayor parte del efectivo
  fecha_hora    TEXT NOT NULL,         -- separa las ventas de antes del corte de las de después
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT
);
CREATE INDEX idx_corte_caja_dia ON corte_caja(dia);
```

Se **sincroniza** como el resto: si el Gerente mira los reportes en su teléfono y la caja se cuenta en el de la caja, el corte tiene que estar en los dos.

## Costeo (decisión 0040) — v7

Cinco tablas, sincronizables, sin `REFERENCES` al catálogo. DDL exacto en
`AppDatabase.esquemaCosteo`.

| Tabla | Clave | Qué guarda |
|---|---|---|
| `insumo` | id | nombre, `unidad_base` (gramo/mililitro/unidad), `contenido_por_compra`, `precio_compra`, `merma` (nullable → la global), proveedor, notas; `updated_at`, `deleted_at` |
| `costo_fijo` | id | concepto, `monto_mensual`, notas; `updated_at`, `deleted_at` |
| `config_costeo` | id = `'unica'` | días abiertos, margen objetivo, merma por defecto, tarifa de mano de obra, redondeo, `metodo_reparto`; y desde v8 (0042) `regimen`, `factor_iva_compras`, `factor_renta_compras`, `tasa_iva_por_defecto`, `comision_efectivo`, `comision_sinpe` (`comision_medios_pago` queda sin uso) |
| `articulo_costeo` | id; UNIQUE (`producto_id`, `variante_id`) con `variante_id = ''` sin variantes | unidades por lote, otros costos directos, minutos del lote, unidades estimadas al mes, margen propio (nullable), ajuste con signo |
| `linea_receta` | id; UNIQUE (`articulo_id`, `insumo_id`) | `cantidad_por_lote` en la unidad base del insumo |

**`compra_insumo` vive en el libro** (`ventas-<inicio>.db`), no acá
([0041](../decisiones/0041-libro-de-compras-de-insumos.md)): id, `insumo_id`,
`fecha`, `presentaciones`, `contenido` (por presentación, en unidad base),
`pagado`, notas, `updated_at`, `deleted_at`. El libro pasa a ser el del
negocio: lo que entra y lo que sale. `insumo.precio_compra` y
`contenido_por_compra` son el **precio de arranque**: mandan solo hasta la
primera compra anotada.

Nada derivado se guarda: costos, precios sugeridos y márgenes salen de
`packages/costeo` en cada lectura; el costo de cada insumo, del promedio de
sus compras.

## Configuración local del dispositivo (fuera de SQLite)

No son tablas de negocio — viven en almacenamiento seguro nativo del dispositivo (ej. `flutter_secure_storage`, que usa Keychain/Keystore del sistema operativo), no en la base de datos SQLite ni se sincronizan entre dispositivos (ver decisión 0011):

- **rol**: `"gerente"` | `"registradora"` — asignado a este dispositivo específico.
- **contrasena_hash**: hash de la contraseña local de la app en este dispositivo (Argon2id, misma dependencia que el backup en 0006). Nunca texto plano.
- **device_id** *(pendiente — ver ⚠ punto 4)*: identificador estable de este dispositivo, necesario para el esquema de sync (0007). Probablemente un UUID v4 generado una sola vez en el primer arranque y guardado junto a lo anterior. No bloquea el resto del esquema — se diseña a detalle cuando se implemente sync.

---

## Decisiones cerradas en esta ronda

1. **`deleted_at` no es universal** — corregido en `Architecture.feature`: solo tablas con ciclo de vida de descontinuación (Producto, Categoria, futura Insumo) lo llevan; Venta/LineaVenta no.
2. **Dinero → `REAL`, no centavos enteros.** Moneda: colón costarricense (₡), que normalmente no usa céntimos en efectivo — pero se deja `REAL` "por si acaso" se necesite un decimal puntual. Aplica a `producto.precio_base` y `linea_venta.precio_aplicado`.
3. **Credenciales → almacenamiento seguro nativo, no tabla SQLite.** Se elimina la tabla `usuario`; rol + hash de contraseña viven en `flutter_secure_storage` (Keychain/Keystore). Ver [decisión 0011](../decisiones/0011-credenciales-almacenamiento-nativo.md).
4. **Categoría → sí, de una.** Tabla normalizada `categoria`, uso principal de interfaz/búsqueda al armar una venta, sin peso en reportes por ahora.
5. **Nota por línea → columna `TEXT` en `linea_venta`, no JSON en `venta`.** Pensada para justificar un `precio_aplicado` distinto al base. Ver [decisión 0013](../decisiones/0013-nota-por-linea-no-json-en-venta.md).
6. **Purgar Producto → sí, condicional.** Borrado físico real (Gerente-only), solo si ya está descontinuado, tiene cero ventas asociadas, y todos los dispositivos están sincronizados. Ver [decisión 0015](../decisiones/0015-purgar-producto-borrado-fisico-condicional.md).
7. **Línea libre en Venta → sí.** `linea_venta.producto_id` nullable + `nombre_libre`, para casos custom de un solo uso sin ensuciar el catálogo. Ver [decisión 0016](../decisiones/0016-linea-libre-en-venta.md).

## ⚠ Puntos aún pendientes

### `device_id` para el esquema de sync

Confirmado que una ID única generada localmente es la mejor opción, pero se deja pendiente de diseñar a detalle cuando se implemente sync (decisión 0007) — no bloquea el resto del esquema. Pista para esa sesión: generar un UUID v4 una sola vez en el primer arranque de la app y guardarlo junto al rol y la contraseña en el mismo almacenamiento seguro nativo (ver sección de configuración local arriba) — no necesita su propia tabla ni mecanismo de storage distinto.

### Estado consultable de "todos los dispositivos sincronizados" (para Purgar, 0015)

La acción "Purgar" depende de que el servicio de sync pueda confirmar que no hay dispositivos conocidos con tareas pendientes. Se apoya en la misma señal ya prevista en la topología de sync (0007), pero falta definir la API exacta (`SyncNotifier` expone esto como un booleano/estado consultable) — se diseña junto con el resto de sync, no bloquea el resto del esquema.

### Índices (bajo riesgo, se resuelve al implementar)

Cuando se cierre el resto del esquema: índices sobre `linea_venta.venta_id`, `linea_venta.producto_id`, `venta.fecha_hora` (se consulta en cada reporte), `producto.deleted_at` y `producto.categoria_id`.
