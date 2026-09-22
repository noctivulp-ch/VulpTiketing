# 0040 — Costeo de recetas como módulo informativo, con "aplicar precio" opcional

**Estado:** Aceptada
**Fecha:** 2026-09-21

## Contexto

Existe una hoja de cálculo de costos y precios (`AppCreator/Tablas/`, con su
propia documentación en `docs/CalculoCostoRecetas/`): insumos con merma,
recetas por lote, mano de obra, costos fijos repartidos, precio sugerido con
margen y comisión, margen real, punto de equilibrio. La [idea 4](../ideas-abiertas.md)
comparó traerla como app aparte o como módulo, y el dueño eligió módulo.

Dos reglas del dueño que mandan sobre todo lo demás:

- **El módulo es soporte e información.** *"La opción de sincronizar los
  precios según el cálculo que sea estrictamente opcional; hay personas que
  llevan el manejo de precios por aparte por diversas razones. El
  comportamiento debe ser de soporte e información, con la opción de ser
  herramienta principal. Tiketing al final es una libreta de apuntes con
  esteroides."*
- **No se generaliza la app.** Añadir el módulo no es hacer tiketing genérico.

## Decisión

### 1. El cálculo es un paquete Dart puro

`packages/costeo/`, sin Flutter ni base: `calcularCatalogo(config, costosFijos,
insumos, articulos, recetas) → ResultadoCosteo`. Determinista y sin efectos, con
las fórmulas de la hoja (`01-modelo-de-costos.md`) y pruebas con números a
mano. Es un paquete aparte para que **no pueda** importar Flutter: la pureza se
impone por estructura, no por disciplina. Si algún día conviene la app aparte,
se levanta entero.

### 2. Tablas propias; `producto` no se toca

| Tabla | Qué es |
|---|---|
| `insumo` | Catálogo maestro de materias primas: unidad base (g/ml/u), contenido por compra, precio de compra, merma, proveedor |
| `costo_fijo` | Alquiler, servicios, sueldos… monto mensual por concepto |
| `config_costeo` | Una fila (`id = 'unica'`): días abiertos, margen objetivo, comisión de medios de pago, merma por defecto, tarifa de mano de obra, redondeo, método de reparto |
| `articulo_costeo` | Lo que la hoja añade a un producto **o a una variante**: unidades por lote, otros costos directos, minutos por lote, unidades estimadas al mes, margen objetivo propio, ajuste de precio. Clave `(producto_id, variante_id)`, con `variante_id` vacío para el producto sin variantes |
| `linea_receta` | `(articulo_id, insumo_id, cantidad_por_lote)` |

Todas con `id` UUID, `updated_at` y `deleted_at` donde aplica: **se
sincronizan** entre aparatos como el catálogo (entran en
`tablasSincronizables`). `esquemaSync` ya subió a 5 en esta versión por las
variantes; estas tablas entran en la misma subida. El Gerente costea en un
aparato y lo ve en todos.

### 3. Volumen: ventas reales, con la estimación de reserva

El dato más sensible del modelo es cuántas unidades se venden al mes. Acá
**son las ventas reales**: por defecto, las del último mes con ventas, por
producto y variante, leídas de los libros. `unidades_estimadas_mes` queda de
reserva para un artículo sin historial, y la pantalla dice de dónde salió cada
número.

### 4. Informa; no toca `precio_base`

La pantalla muestra, por artículo: costo de insumos, mano de obra, overhead,
costo total, **precio sugerido**, **margen real contra lo que hoy se cobra**
(`precio_base`), y alertas (sin receta, sin volumen, margen bajo objetivo, se
vende a pérdida). Nada de eso escribe en el catálogo.

**"Aplicar precio"** es un botón explícito, por artículo, que copia el precio
sugerido a `precio_base` (o al precio de la variante). Nunca en bloque ni
automático: cambiar el volumen de un artículo mueve el overhead de todos, y
repreciar la carta en silencio sería un desastre. Quien lleva los precios
aparte no lo pulsa y el módulo le sirve igual.

### 5. Solo Gerente, sexta ventana

Una ventana más del dashboard, visible solo con sesión de Gerente. La
Registradora sigue viendo cinco: sus gestos y atajos no cambian.

## Alternativas descartadas

- **App aparte**: catálogo duplicado y un puente de importación que mantener;
  y el volumen real —que es lo que hace bueno al modelo— solo está acá.
- **Precio calculado aplicado automáticamente**: es lo que el dueño vetó. Y
  técnicamente es peligroso: el cálculo es de catálogo, no de producto.
- **Reparto de costos fijos por ingreso**: circular (ADR-003 de la hoja).
  Quedan `UNIDAD` y `TIEMPO`.

## Consecuencias

- Migración v6 → v7: cinco tablas nuevas, vacías. Sin datos que mover.
- Cinco Notifiers nuevos, uno por entidad, con solo sus operaciones (0009).
- Un `costeoProvider` derivado que junta base + ventas y llama al paquete puro.
- Sub-recetas (una masa base en cinco productos), historial de precios de
  insumo y simulador ("si el huevo sube 20 %") quedan para después; el modelo
  no los impide.
