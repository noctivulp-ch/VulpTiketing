# 0004 — Impresión e inventario de insumos: pospuestos, no descartados

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

Ninguna feature base cubre impresión de tickets ni inventario de materias primas/insumos, pero ambas ideas existen para el producto.

## Decisión

Ambas quedan fuera de la implementación base, explícitamente pospuestas (no descartadas):

- **Impresión con impresora genérica**: no hay impresora disponible aún ni es necesaria para la función contable principal.
- **Inventario de materias primas/insumos**: feature próxima pensada para calcular gastos del local (entradas/salidas de dinero) y generar informes más completos.

## Consecuencias

El modelo de datos base no necesita reservar campos para stock de insumos ni para configuración de impresora, pero el diseño de "Producto" y "Venta" no debería hacer supuestos que compliquen agregar esto después (ej. evitar acoplar el modelo de venta a una impresión síncrona).
