# 0008 — Modelo de venta multi-línea y terminología Producto vs Plato

**Fecha:** 2026-07-26
**Estado:** Aceptada — opción A (multi-línea + renombrar a Producto)

## Decisión final

Una **Venta** contiene una o más líneas; cada línea referencia un **Producto** del inventario y guarda: precio aplicado (base o editado en el momento) y **cantidad** (explícita, en vez de repetir el mismo producto como líneas separadas — evita filas redundantes y es el modelo estándar para este tipo de app). El término "Plato" se reemplaza por "Producto" en modelo de datos y features.

## Contexto

Order.feature actual describe un "Pedido" con **un** "Plato" seleccionado del menú (precio + nota). La descripción del flujo de cobro dada por el usuario habla de "agregar **productos** [plural] a cobrar" y de guardar "**Productos**, Precios, hora y día" — lo que sugiere que una venta contiene varias líneas, no una sola.

También usa el término "Producto" de forma natural en vez de "Plato", lo cual encaja mejor con un inventario que puede incluir bebidas, snacks, etc., no solo platos de comida.

## Opciones

**A — Venta multi-línea + renombrar Plato → Producto (recomendada)**
Una "Venta" (o "Pedido") contiene N líneas, cada una con: producto, precio aplicado (base o editado), y probablemente cantidad. El término de dominio pasa de "Plato" a "Producto" en modelo de datos y features.
- Ventaja: coincide directamente con la forma en que el usuario describió el flujo real; más flexible para un inventario mixto (comida + bebidas + otros).

**B — Multi-línea sin renombrar**
Igual que A pero manteniendo "Plato" como término (ej. "Pedido" tiene N "ItemPedido", cada uno referenciando un "Plato").
- Ventaja: no toca las features ya escritas.
- Desventaja: "Plato" queda semánticamente raro para una bebida o un snack.

**C — Un producto por pedido (como está hoy en Order.feature)**
- No recomendada: no coincide con "agregar productos" (plural) descrito por el usuario.

## Recomendación

A — pero confirmar con el usuario si además de producto+precio cada línea necesita **cantidad** explícita (ej. "2x Café"), o si agregar el mismo producto dos veces como dos líneas separadas es suficiente.
