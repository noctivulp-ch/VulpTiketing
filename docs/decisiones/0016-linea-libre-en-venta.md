# 0016 — Línea libre en Venta (sin Producto de catálogo)

**Fecha:** 2026-07-27
**Estado:** Aceptada

## Contexto

Casos custom de un solo uso (ej. un descuento puntual de desayuno para un cliente específico, que nunca se va a repetir) obligaban, con el modelo original, a crear un Producto permanente en el catálogo solo para venderlo una vez — y luego, en el mejor caso, purgarlo después ([0015](0015-purgar-producto-borrado-fisico-condicional.md)). Eso es fricción innecesaria para algo que en realidad nunca necesitó existir como entidad de catálogo.

## Decisión

`linea_venta.producto_id` pasa a ser **nullable**. Se agrega la columna `nombre_libre TEXT`, usada únicamente cuando `producto_id IS NULL`. Un `CHECK` garantiza que exactamente uno de los dos esté presente por línea:

```sql
CHECK (
  (producto_id IS NOT NULL AND nombre_libre IS NULL) OR
  (producto_id IS NULL AND nombre_libre IS NOT NULL)
)
```

El cajero escribe nombre y precio directamente en la línea, sin tocar el catálogo de Producto — el resto de la línea (`precio_aplicado`, `cantidad`, `nota`) funciona exactamente igual que con un producto de catálogo.

## Alternativas descartadas

- Crear siempre un Producto, incluso para casos de un solo uso, y purgarlo después si nunca se reutiliza — funciona, pero es más pasos (crear + vender + purgar) para algo que nunca necesitó ser una entidad persistente del inventario.

## Consecuencias

- `VentaEnCursoNotifier` gana la operación "agregar línea libre", distinta de "agregar producto del catálogo" — ver `docs/arquitectura/gestion-estado.md`.
- Los reportes que agrupan "producto más/menos vendido" deben decidir cómo tratar líneas libres (¿agruparlas bajo "Personalizado", listarlas individualmente por `nombre_libre`, o excluirlas del ranking?) — pendiente de resolver al diseñar Reports a detalle, no bloquea nada más. Ver `docs/funciones/reportes.md`.
- Una línea libre nunca tiene `producto_id`, por lo tanto nunca puede bloquear una purga ([0015](0015-purgar-producto-borrado-fisico-condicional.md)) ni beneficiarse de cambios futuros al precio base de un producto (no aplica, no hay producto).
