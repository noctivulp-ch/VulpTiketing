# 0012 — Precios como `REAL`, no `INTEGER` en unidad mínima

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

Para evitar errores de redondeo de punto flotante, el estándar en sistemas de facturación es guardar montos como enteros en la unidad mínima de la moneda (centavos). Pero la moneda de la soda es el colón costarricense (₡), que normalmente no usa céntimos en el manejo de efectivo diario.

## Decisión

Usar `REAL` para `producto.precio_base` y `linea_venta.precio_aplicado`, en vez de `INTEGER` en céntimos. Se deja como `REAL` (no `INTEGER` de colones exactos) por si en algún caso puntual hiciera falta un decimal.

## Alternativas descartadas

- `INTEGER` en céntimos — más seguro contra imprecisión de punto flotante, pero no se justifica para una moneda que en la práctica no opera con céntimos; hubiera sido complejidad sin beneficio real para este negocio.

## Consecuencias

- Los reportes que sumen montos (`SUM(precio_aplicado * cantidad)`) deben tener en cuenta que `REAL` en SQLite es de punto flotante — para los montos y volúmenes de una soda pequeña esto no es un riesgo práctico, pero si en el futuro se requiriera precisión exacta (ej. reportes fiscales estrictos), se podría revisar esta decisión.
