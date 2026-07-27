# 0013 — Nota descriptiva por línea en `linea_venta`, no JSON en `venta`

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

Se necesita poder dejar un descriptivo opcional por cada producto agregado a una venta — principalmente para justificar cuándo el precio aplicado difiere del precio base (ej. "promoción", "cliente frecuente"). La propuesta inicial fue un campo JSON en `venta` que relacionara `{nombre_producto: nota}`, dejando fuera del objeto los productos sin nota.

## Problema con la propuesta inicial

Si el mismo producto aparece dos veces en la misma venta con notas distintas (ej. dos "Café", uno con nota "sin azúcar" — o más precisamente, dos líneas con precio editado por motivos distintos), un JSON keyed por **nombre de producto** solo puede guardar una entrada por nombre — la segunda nota sobreescribe a la primera silenciosamente. Además, si el nombre del producto se edita después, el JSON histórico queda con un nombre que ya no coincide con nada, sin forma confiable de re-asociarlo.

## Decisión

Agregar una columna `nota TEXT` (nullable) directamente en `linea_venta`. Cada línea ya es su propia fila con su propio `producto_id` — no hace falta ninguna estructura adicional para saber a qué producto de esa venta corresponde una nota. Si no se escribe nota, el campo queda `NULL` (mismo comportamiento buscado: "si está vacío no se agrega").

## Alternativas descartadas

- JSON en `venta` keyed por nombre de producto — descartado por la colisión descrita arriba.
- JSON en `venta` keyed por `linea_venta.id` — resolvería la colisión, pero mantendría dos representaciones paralelas del mismo dato (las filas de `linea_venta` y un JSON aparte que las referencia), sin ningún beneficio sobre poner la nota directo en la fila.

## Consecuencias

- `linea_venta.nota` es independiente de `venta.detalle` (nota general de toda la venta) y de `venta.motivo_reversion` (JSON, solo aplica a ventas revertidas — [0010](0010-motivo-reversion-como-json.md)). Tres campos de texto con propósitos distintos, ninguno se mezcla con otro.
