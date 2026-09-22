# 0039 — Variantes de un producto como JSON en `producto`, y su nombre en la línea de venta

**Estado:** Aceptada
**Fecha:** 2026-09-21

## Contexto

Un café de máquina se vende pequeño y grande. Hoy la única forma de cobrarlos
distinto es crear dos productos, y la carta real ya lo hace por todas partes:

```
Pollo frito (cadera y muslo)   2300     Hamburguesa              1350
Pollo frito (pechuga y ala)    2500     Hamburguesa con papas    2500
Tacos sencillos                2000     7UP (355ml) · Kerns (330ml)
Tacos dobles con papas         3500     Batido de ×6 · Nestlé ×10
```

No son solo tamaños: cortes, con o sin acompañamiento, presentaciones,
sabores. La pieza se llama **variante**, y una variante es un nombre y un
precio. Nada más.

Llega junto con el módulo de costeo (idea 4 de `ideas-abiertas.md`), que
necesita una receta por variante: el café grande gasta más leche.

## Decisión

**Una columna JSON en `producto`**, nula para el producto sin variantes:

```
producto.variantes TEXT
  [{"id":"a1f3","nombre":"Pechuga y ala","precio":2500},
   {"id":"7c02","nombre":"Cadera y muslo","precio":2300}]
```

**Y el nombre de la variante vendida en la línea**, como foto del día:

```
linea_venta.variante TEXT   -- NULL cuando el producto no tiene variantes
```

`precio_base` es el precio del producto sin variantes. **Con variantes, es el
precio de la variante por defecto** (`"porDefecto": true` en el JSON; si
ninguna lo dice, la primera), y el formulario los guarda en sincronía. Lo
pidió el dueño al probar: con variantes, un precio base suelto "queda de
facto sin uso". Así todo lo que lee `precio_base` —tarjetas, listas,
exportación— sigue valiendo, y el campo del formulario se convierte en el
señalador de cuál es la por defecto en vez de un número.

## Por qué JSON y no una tabla

El proyecto ya tiene la regla, en dos decisiones que parecen contradecirse:

- [0010](0010-motivo-reversion-como-json.md) puso el motivo de reversión en
  JSON porque **vive y muere con su fila** y no es clave de nada.
- [0013](0013-nota-por-linea-no-json-en-venta.md) rechazó JSON para las notas
  porque **colisionaba por nombre** y duplicaba filas que ya existían.

Una variante pasa el test de la 0010: se crea, edita y borra dentro del
formulario del producto, no tiene vida propia, y muere con él. No cae en la
trampa de la 0013 porque la línea de venta ya es su propia fila; ahí solo
hace falta anotar cuál se vendió.

Consecuencias concretas de elegir JSON:

- **Sin `VarianteNotifier`.** La [0009](0009-cruds-independientes-por-entidad.md)
  pide un Notifier por entidad con su ciclo de vida real. La variante no es
  una entidad: es un campo de `Producto`. Una tabla habría pedido CRUD propio,
  `deleted_at`, y una entrada más en `tablasSincronizables`.
- **La migración es `ALTER TABLE producto ADD COLUMN variantes TEXT`**, el
  patrón de `categoria.icono`. Los productos existentes quedan intactos.
- **El id dentro del JSON** existe por el costeo: `producto_costeo` apunta a
  la variante por id, y renombrarla no rompe su receta.

## Por qué el nombre en la venta, y no el id

`precio_aplicado` ya guarda el precio del día y no el actual. La variante
sigue la misma lógica: si "Grande" pasa a llamarse "Mediano", el libro de hoy
sigue diciendo lo que se vendió hoy. Un libro contable es una foto, no una
referencia. Los reportes agrupan por `(producto_id, variante)` y el ranking
dice "Pollo frito · Pechuga y ala".

## Lo que cuesta, y queda aceptado

- **Conflicto de sync por producto entero.** Si dos aparatos editan las
  variantes del mismo producto a la vez, gana `producto.updated_at` y el otro
  cambio se pierde completo. Con filas habría sobrevivido cada uno. El
  catálogo lo edita el Gerente en un aparato; se acepta.
- **`esquemaSync` sube.** El sync inserta la fila remota completa
  (`row_upserter.dart`); un aparato viejo que reciba un producto con
  `variantes` falla por columna desconocida. Esto pasa igual con tabla.
  Variantes y costeo van en **la misma** subida de esquema.
- **Cada variante es un toque más** para quien cobra. Vale para lo que es una
  elección real (tamaño, corte, con o sin papas), no para partir los batidos
  en "Batido → Fresa". Lo decide el dueño producto por producto; el que no
  tiene variantes sigue siendo un toque.

## Alternativas descartadas

- **Tabla `variante`** (id, producto_id, nombre, precio, orden, updated_at,
  deleted_at). Sobrevive mejor al conflicto de sync y admite consultas SQL
  directas. Descartada porque obliga a un Notifier, un borrado lógico y una
  tabla sincronizable más para algo que no tiene ciclo de vida propio, y
  porque SQLite trae `json_each` si algún día hiciera falta consultar dentro.
- **Seguir con un producto por variante.** Es lo que hay. Infla la cuadrícula,
  reparte las ventas de un mismo plato en varios renglones del ranking, y
  obliga a repetir la receta en el costeo.
- **Id de variante en la línea de venta** en vez del nombre. Rompe la foto
  al renombrar, y obliga a resolver el JSON para leer un reporte.

## Consecuencias

- `Producto` gana `List<Variante>? variantes`; el formulario, una lista
  editable de nombre y precio.
- Al tocar un producto con variantes en la venta se abre un selector con una
  opción grande por variante, la por defecto destacada; sin variantes, un
  toque como hoy. En Venta Rápida la por defecto viene **preseleccionada** y
  se cobra de un toque: cambiar de tamaño es la excepción. (Primero se
  obligaba a elegir siempre; al existir una por defecto elegida por el
  Gerente, esa es la decisión.)
- La tarjeta muestra el precio de la por defecto, sin "desde".
- **El orden de las variantes es el del arreglo**, y lo fija el Gerente en el
  formulario con las flechas ▲▼. Ninguna pantalla ordena por nombre ni por
  precio: chips y selector repiten el orden tal cual. La app depende de la
  monotonía para generar memoria muscular — "el segundo botón" tiene que ser
  siempre el mismo.
- `linea_venta.variante`, y el ranking de reportes agrupa por producto y
  variante.
- Migración de `producto` y de los libros de ventas; `esquemaSync` sube junto
  con las tablas del costeo.
- El costeo trata a cada variante como una fila de `producto_costeo`
  (producto_id, variante_id).
