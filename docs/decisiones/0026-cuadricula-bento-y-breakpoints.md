# 0026 — Una retícula bento de 6 columnas y tres tamaños de pantalla

## Estado

Aceptada — implementada el 2026-07-30.

## Contexto

Los flujos de la app eran correctos y no había queja sobre el estilo visual. El
problema era de **orden y acomodo**: cada pantalla resolvía su layout por su
cuenta, así que las cinco no se leían como una sola app.

Y el diseño responsive nunca se hizo. `flujo-descripcion.md` lo dice explícito:
*"El layout específico para pantallas pequeñas (teléfono) queda pospuesto a
propósito"*. La consecuencia era medible:

- **Un solo breakpoint en toda la app** — `width >= 720`, enterrado en
  `DashboardShell`. Ningún `LayoutBuilder` en ningún archivo de `lib/`.
- **Cuatro pantallas rompían a 360 dp**, que es el ancho lógico del Honor X6c
  del negocio:
  - Reportes: cuatro celdas en una `Row` fija; el hero quedaba en ~146 dp con un
    número de 40 px y cada turno en ~52 dp;
  - Panel Venta: la `Row` raíz repartía 3:4, o sea ~144 dp de carrito, donde no
    entra una línea de venta;
  - Panel Venta: Recibí + Cambio + Total + Finalizar en una sola fila;
  - Configuración: `GridView` con `shrinkWrap` y `NeverScrollableScrollPhysics`
    dentro de una `Column` — unos 880 dp de alto que **no scrolleaban**.
- **Las cuadrículas eran implícitas**: `SliverGridDelegateWithMaxCrossAxisExtent`
  reparte por ancho disponible, así que el número de columnas era un efecto
  secundario y no una decisión. Por eso no se leían como formas deliberadas.

## Decisión

### Una retícula de 6 columnas, igual en toda la app

Cada pieza declara cuántas columnas ocupa en cada tamaño. Una sola declaración,
tres formas.

**Seis** porque se divide en 2 y en 3, que son los repartos que piden estas
pantallas: mitades para los dos rankings, tercios para los tres turnos. Con
cuatro los tercios no cierran; con doce, a 360 dp cada columna queda en unos
21 dp y el número deja de significar nada.

### Tres tamaños, definidos una vez

| | Ancho | Aparato |
|---|---|---|
| `compacto` | < 600 dp | teléfono (360 dp es el caso de diseño) |
| `medio` | 600–1023 | tablet |
| `amplio` | ≥ 1024 | escritorio |

El `720` suelto desaparece: el rail de navegación aparece desde `medio`.

### `BentoCuadricula`, no `GridView`

- `GridView` no sabe de celdas que ocupen varias columnas sin traerse un paquete
  de grid escalonado.
- Reparte por `maxCrossAxisExtent`, que es exactamente el problema a resolver.
- Su `spacing` es un margen, y acá el hueco entre pozos es **material de
  bandeja** ([`DESIGN.md`](../../DESIGN.md) regla 2), no fondo asomándose.

Las celdas de una fila **comparten altura**. No es estético: es lo que hace que
se lea como una caja bento y no como columnas sueltas. Ya era el patrón de la
casa — la [decisión 0023](0023-refinamiento-bento-post-implementacion.md) lo
prescribía con `IntrinsicHeight` + `stretch`.

### Listas largas: retícula declarada, grilla perezosa

`BentoCuadricula` construye todas sus celdas de una, así que **no sirve para el
catálogo**, que las pruebas de volumen ejercitan con 5.000 productos. Esas
pantallas usan `GridView` con `crossAxisCount` explícito, calculado por
`bentoPorFila` a partir de los mismos spans. El vocabulario es el mismo; lo que
cambia es que la construcción es perezosa.

### `llenarAlto`

`IntrinsicHeight` le pide a sus hijos su alto natural, y un `ListView` no sabe
darlo: revienta con altura infinita. Los rankings de Reportes son scrollables,
así que sus filas se reparten el alto disponible en vez de medirlo. Era el mismo
tropiezo que ya tenía un comentario en esa pantalla desde antes.

## Consecuencias

**`Card` sale de toda la app.** Eran 7 en 4 pantallas, y la regla 8 de
`DESIGN.md` los prohibía desde hacía tiempo: *"`NavigationRail`, `Card` y
`VerticalDivider` dentro de una bandeja comprometida son fugas. Las celdas son
pozos."* `Card` trae elevación y radio propio, que es por donde se cuela el
aspecto de botón levantado que el usuario ya había rechazado una vez. Por lo
mismo salieron el relleno de `primaryContainer` del tile seleccionado de
Configuración —ahora lo marca la cresta del pozo— y el `Material(elevation: 4)`
de la barra de cobro, que la regla 1 prohíbe porque la escena de uso es sol
directo.

**El panel de Panel Venta se acopla al lado largo**: a la derecha cuando hay
ancho, abajo cuando no. Mismo panel persistente y mismo botón de la costura,
rotados — no un overlay, que es lo que la 0023 descarta. El icono apunta hacia
donde se va el panel.

**Aparece una red de seguridad que no existía.** `test/layout_responsive_test.dart`
monta 6 pantallas × 3 tamaños × 2 roles. Antes **no había ni un test que
redimensionara la ventana**, y por eso los cuatro desbordes llegaron hasta el
aparato. El rol se prueba aparte porque cambia el layout: el Gerente ve 9 tiles
de Configuración contra 7 y 4 segmentos de rango contra 2.

## Alternativas descartadas

- **Arreglar cada desborde donde aparece.** Habría cerrado los cuatro casos sin
  resolver la incoherencia, que era el pedido de fondo, y el quinto desborde
  habría aparecido con la próxima pantalla.
- **Un paquete de grid escalonado** (`flutter_staggered_grid_view`). Una
  dependencia para lo que son 60 líneas, y su modelo de spacing es de margen, no
  de material.
- **Doce columnas**, como los sistemas de retícula web. A 360 dp cada columna
  queda en 21 dp: los spans dejarían de decir nada sobre la forma.
