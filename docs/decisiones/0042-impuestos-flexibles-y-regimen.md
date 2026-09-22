# 0042 — Impuestos por régimen, tasa por producto y comisión por medio de pago

**Estado:** Aceptada
**Fecha:** 2026-09-21

## Contexto

El costeo (0040) tenía una sola "comisión de medios de pago" y ningún
impuesto. El dueño pidió *"una manera flexible de agregar impuestos por
producto o medio"*, y la [investigación](../investigacion/costeo-tributacion-y-versatilidad.md)
mostró que en Costa Rica hay dos mundos: el **simplificado**, donde el
impuesto es una fracción de las compras del trimestre y no se cobra IVA en la
venta, y el **general**, donde cada producto lleva su tasa (13, 4, 2, 1 %,
exento) dentro del precio.

## Decisión

### Régimen, en Ajustes del costeo

- **Simplificado** (de fábrica): dos factores sobre compras —IVA y renta— con
  los valores de 2026 para una soda como arranque (3,0 % y 2,5 %). Por unidad
  se imputa `costo de insumos × (factor IVA + factor renta)` como un costo
  más: no depende del precio. Ajustes muestra el trimestre en curso ya
  calculado con lo comprado (0041): es lo que se declara el 15 del mes
  siguiente.
- **General**: cada producto lleva su **tasa de IVA** (`producto.tasa_iva`,
  nula = la tasa por defecto de Ajustes). Como el precio al público incluye
  el IVA, la fracción del precio que se va en impuesto es `tasa / (1 + tasa)`
  y entra en el divisor del precio sugerido y en el margen real, igual que la
  comisión. El resumen muestra el IVA dentro de lo vendido en el mes.

### Comisión por medio de pago

`comision_efectivo` y `comision_sinpe` en `config_costeo`. **La comisión que
usa el cálculo es el promedio de las dos ponderado por el mix real de cobro
de los últimos 30 días** (`mixDePagoProvider`, de los libros). Así la cifra
es la que de verdad se paga, y para un negocio que cobra todo por
transferencia o plataforma (Patreon) es simplemente la de SINPE al 100 %.

### Lo que NO se hace

- Facturación ni retención: la app es una libreta, no un contador. Ajustes lo
  dice y pide comprobar las cifras con el decreto vigente.
- Renta por tramos sobre la utilidad (negocio digital): es anual y sobre la
  utilidad, no sobre el precio; queda fuera del cálculo de precio.

## Alternativas descartadas

- **Sumar el IVA a la comisión**: funciona numéricamente pero mezcla dos
  cosas con distinta base y distinta declaración.
- **Una tabla `impuesto` genérica** con reglas por producto y por medio: más
  flexible de lo que hoy hace falta; la tasa por producto y la comisión por
  medio cubren los casos reales (soda, comercio, servicios), y una tabla se
  agrega el día que aparezca un tercer tipo.

## Consecuencias

- Esquema **v8**: `producto.tasa_iva`; `config_costeo` gana `regimen`,
  `factor_iva_compras`, `factor_renta_compras`, `tasa_iva_por_defecto`,
  `comision_efectivo`, `comision_sinpe`. La comisión única de antes se copia
  a SINPE en la migración. `comision_medios_pago` queda sin uso en la tabla.
- `packages/costeo`: `ConfigCosteo.impuestoSobreCompras`,
  `Articulo.tasaImpuesto`, líneas nuevas en el resultado.
- El formulario de producto gana el desplegable de IVA (solo pesa en general).
