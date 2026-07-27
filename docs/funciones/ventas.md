# Ventas y Cobro

Ver también: [reportes](reportes.md) · [../arquitectura/datos](../arquitectura/datos.md) · [../../features/Order.feature](../../features/Order.feature) · [../../features/Operations.feature](../../features/Operations.feature)

## Propósito

La función principal de la app **no es un punto de venta con manejo de caja** — es llevar contabilidad de forma fácil de lo que se vende en el local. No hay apertura/cierre de caja, ni conciliación de efectivo.

## Flujo

1. Existe un **inventario de Productos** vendidos en el local: nombre, imagen (opcional), precio base.
   - Gerente: CRUD completo.
   - Registradora: solo lectura y edición de campos existentes (no crea ni elimina productos) — ver [Operations.feature](../../features/Operations.feature).
2. Al registrar una venta, el usuario **agrega productos a cobrar** (una o varias líneas), cada línea con:
   - El producto seleccionado del inventario.
   - Precio: el precio base se carga automáticamente (aparece como texto de fondo/placeholder en el campo), con opción de editarlo manualmente en el momento (ej. descuento puntual, promoción). Si el usuario no lo toca, se aplica el base; si escribe otro valor, se aplica ese.
   - Nota opcional de esa línea, pensada principalmente para justificar un precio editado (ver [decisión 0013](../decisiones/0013-nota-por-linea-no-json-en-venta.md)) — distinta del "Detalle" general de toda la venta.
3. Al guardar, la venta persiste: líneas de producto + precio aplicado + cantidad + nota (si hay) + hora + fecha.
4. No hay confirmación de método de pago ni corte de caja — el registro es puramente para efectos contables/reportes.

## Modelo de datos

Una **Venta** es multi-línea (carrito): agrupa una o más **líneas**, cada una con Producto + precio aplicado + cantidad + nota opcional. El término de dominio es "Producto" (no "Plato") para cubrir inventario mixto (comida, bebidas, etc.). Ver [datos](../arquitectura/datos.md) y [decisión 0008](../decisiones/0008-modelo-venta-multilinea-terminologia.md).

## Ciclo de vida de una Venta: crear o revertir, nunca editar

A diferencia de un Producto (que se puede crear, editar y descontinuar), una Venta **solo se crea o se revierte**. No existe edición ni borrado de una venta ya guardada.

**Revertir** cubre casos de devolución o pedido registrado por error:
- Cambia el `estado` de la venta a `revertida`.
- Exige un **motivo**, guardado como JSON en un campo de texto (ver [decisión 0010](../decisiones/0010-motivo-reversion-como-json.md)): tipo de motivo (ej. devolución, pedido erróneo), detalle en texto libre, quién revirtió y cuándo.
- La venta revertida **no desaparece** — queda visible para trazabilidad, pero se excluye de los totales en [reportes](reportes.md).

Este ciclo de vida es independiente del de Producto — no comparten lógica de CRUD (ver [decisión 0009](../decisiones/0009-cruds-independientes-por-entidad.md)).

## Fuera de alcance en la implementación base

- **Impresión de tickets**: existe la idea de soportar una impresora genérica a futuro, pero no hay impresora disponible aún ni es necesaria para la función contable — pospuesto. Ver [decisión 0004](../decisiones/0004-alcance-base-vs-futuro.md).
- **Inventario de materias primas/insumos**: feature próxima (no base) pensada para calcular gastos del local (entradas/salidas de dinero) y reportes más completos. Ver [decisión 0004](../decisiones/0004-alcance-base-vs-futuro.md).
