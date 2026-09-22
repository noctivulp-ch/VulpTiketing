# Costeo de recetas

Ventana 6, solo Gerente ([decisión 0040](../decisiones/0040-costeo-de-recetas-como-modulo.md)).
Dice cuánto cuesta de verdad cada artículo de la carta y qué precio sostiene
el margen. **Informa; no toca la carta** salvo que se pulse "Aplicar" en un
artículo concreto.

## Las cuatro secciones

| Sección | Qué se hace |
|---|---|
| **Artículos** | El resultado. Arriba, el negocio a los precios de hoy y el volumen de los últimos 30 días: utilidad, ingreso, costos fijos, margen neto, unidades, punto de equilibrio (al mes y por día), colchón. Debajo, un pozo por artículo: precio actual, costo total, precio sugerido, margen real (en rojo si no llega al objetivo o se vende a pérdida) y avisos |
| **Insumos** | Materias primas y **sus compras** ([0041](../decisiones/0041-libro-de-compras-de-insumos.md)). El insumo se registra una vez (nombre, en qué se usa, merma, proveedor, precio de arranque); cada vez que se abastece se **anota una compra** (cuántas, de cuánto, pagado). La lista muestra el costo efectivo por unidad base con merma y de dónde salió (promedio de 90 días / última compra / arranque). Abajo, lo comprado en el mes y en el trimestre — la base del régimen simplificado |
| **Fijos** | Alquiler, servicios, sueldos… monto mensual por concepto, y el total |
| **Ajustes** | Margen objetivo (sobre el PRECIO), comisión de medios de pago, merma por defecto, tarifa de mano de obra por hora, redondeo del precio, días abiertos, y reparto de fijos por unidad o por tiempo |

## El detalle de un artículo

Tocar un artículo abre su detalle:

- **Por unidad**: insumos, mano de obra, otros directos, costos fijos que
  absorbe, costo total; precio sugerido con el margen, redondeado (y
  ajustado), lo que se cobra hoy, margen real, y de dónde salió el volumen
  (vendidas en 30 días, o estimado).
- **Receta**: una línea por insumo con la cantidad **por lote**. "+ Insumo"
  agrega (pide crear insumos primero si no hay); tocar una línea cambia la
  cantidad; ✕ la quita.
- **Parámetros del artículo**: unidades por lote, minutos del lote, otros
  costos directos, unidades estimadas al mes (solo cuentan si no hay ventas),
  margen propio, ajuste con signo.
- **Aplicar ₡X**: copia el precio final del modelo al precio del artículo
  (base, o el de la variante — y el base si es la por defecto). Pide
  confirmación y dice que solo toca ese artículo. Apagado si no hay precio
  calculable o ya se cobra exactamente eso.

## De dónde sale el costo de un insumo

Del **promedio ponderado de sus compras de los últimos 90 días**
(Σ pagado ÷ Σ unidades). Si no hay ninguna en la ventana, la última compra;
si no hay compras, el precio de arranque del insumo. La pantalla lo dice.
Anular una compra la saca del promedio sin borrarla del libro. Las compras
viven en el mismo libro rodante que las ventas.

## De dónde sale el volumen

El dato más sensible del modelo son las unidades vendidas al mes. Se leen de
las **ventas reales de los últimos 30 días**, por producto y variante, de los
libros (cerrados incluidos). Una venta sin variante de un producto que hoy
las tiene se atribuye a la por defecto. Solo si no hubo ventas manda la
estimación a mano, y el artículo lo dice ("Volumen estimado").

## Variantes

Cada variante es un artículo aparte: el café grande tiene su receta y su
precio. Un producto sin variantes es un artículo.

## Lo que el módulo NO hace

- No cambia precios solo. Nunca en bloque. Quien lleva los precios aparte no
  pulsa "Aplicar" y el módulo le sirve igual.
- No modela sub-recetas (una masa base en cinco productos), historial de
  precios de insumo ni simulaciones ("si el huevo sube 20 %"). Están en el
  `ToDo.md` del proyecto como trabajo futuro.
