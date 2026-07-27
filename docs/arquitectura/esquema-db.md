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
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT                    -- NULL = activo. Set = descontinuado (0005)
);
```

## Venta

```sql
CREATE TABLE venta (
  id                TEXT PRIMARY KEY,   -- UUID v4
  fecha_hora        TEXT NOT NULL,      -- ISO-8601, usado para turnos/reportes
  detalle           TEXT,               -- nota opcional, libre
  estado            TEXT NOT NULL DEFAULT 'activa'
                     CHECK (estado IN ('activa', 'revertida')),
  motivo_reversion  TEXT,               -- JSON, solo si estado='revertida' (0010)
  updated_at        TEXT NOT NULL
  -- sin deleted_at a propósito: una Venta nunca se borra, solo cambia de estado (0009)
  -- sin campo de total a propósito: se calcula sumando linea_venta, nunca se duplica aquí (ver nota abajo)
);
```

**Por qué no hay un campo de total:** guardar un total en `venta` sería un valor derivado y redundante frente a la suma de sus líneas — con datos duplicados, un bug en cualquier punto que actualice uno y no el otro genera un total mentiroso, justo el tipo de error que una app de contabilidad no se puede permitir. Se calcula con `SUM(precio_aplicado * cantidad)` al leer. Si algún día el volumen de datos lo justificara, se podría agregar como columna de caché — pero para una soda pequeña con SQLite local no hay necesidad real de esa optimización.

## LineaVenta

```sql
CREATE TABLE linea_venta (
  id               TEXT PRIMARY KEY,    -- UUID v4
  venta_id         TEXT NOT NULL REFERENCES venta(id),
  producto_id      TEXT NOT NULL REFERENCES producto(id),
  precio_aplicado  REAL NOT NULL,       -- "foto" del precio al momento de vender, nunca vacío
  cantidad         INTEGER NOT NULL DEFAULT 1,
  nota             TEXT,                -- descriptivo opcional, típicamente para justificar precio_aplicado distinto al base; NULL si no se escribió
  updated_at       TEXT NOT NULL
  -- sin deleted_at: inmutable, vive y muere con su Venta (0009)
);
```

**Sobre `precio_aplicado`:** nunca queda vacío. Al agregar un producto a una venta, el campo se llena automáticamente con el `precio_base` del producto *en ese momento* (una copia, no una referencia viva; el placeholder de "precio base" en el input es puro comportamiento de UI, no requiere nada adicional en la base), y el usuario puede sobreescribirlo antes de guardar. Es intencional que sea una copia y no un lookup a `producto.precio_base`: si el precio base cambia después, las ventas ya registradas deben conservar el precio real que se cobró ese día — de lo contrario los reportes históricos cambiarían solos cada vez que se actualiza el catálogo.

**Sobre `nota`:** descriptivo opcional por línea, pensado principalmente para justificar un `precio_aplicado` distinto al `precio_base` (ej. "promoción", "cliente frecuente", "producto en mal estado"), aunque nada impide usarlo para cualquier otra anotación puntual de esa línea. Es distinta de `venta.detalle` (nota general de toda la venta). Va como columna `TEXT` simple en la propia fila — no como JSON — porque cada línea ya es su propia fila; un JSON en `venta` keyed por nombre de producto colisionaría si el mismo producto aparece dos veces en la misma venta con notas distintas (ver [decisión 0013](../decisiones/0013-nota-por-linea-no-json-en-venta.md)).

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

## ⚠ Puntos aún pendientes

### `device_id` para el esquema de sync

Confirmado que una ID única generada localmente es la mejor opción, pero se deja pendiente de diseñar a detalle cuando se implemente sync (decisión 0007) — no bloquea el resto del esquema. Pista para esa sesión: generar un UUID v4 una sola vez en el primer arranque de la app y guardarlo junto al rol y la contraseña en el mismo almacenamiento seguro nativo (ver sección de configuración local arriba) — no necesita su propia tabla ni mecanismo de storage distinto.

### Índices (bajo riesgo, se resuelve al implementar)

Cuando se cierre el resto del esquema: índices sobre `linea_venta.venta_id`, `linea_venta.producto_id`, `venta.fecha_hora` (se consulta en cada reporte), `producto.deleted_at` y `producto.categoria_id`.
