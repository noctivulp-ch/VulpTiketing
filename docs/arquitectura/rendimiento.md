# Rendimiento

Todo lo de acá está **medido en el teléfono del negocio, en modo profile**, con
`scripts/banco-rendimiento.sh`. Ningún número sale de leer código ni de correr
la app en la computadora: en debug todos los frames pasan del presupuesto y las
consultas cargan con el interpretador, y la computadora es tan rápida que
esconde los cuellos que en el aparato se sienten.

Volumen de referencia: 120 productos, 10.800 ventas, 32.400 líneas — medio año
de la soda.

## Cómo medir

```fish
scripts/banco-rendimiento.sh              # informe completo → build/banco/informe.md
```

Los experimentos comparan opciones entre sí sobre el mismo volumen:

```fish
flutter drive --driver=test_driver/banco_driver.dart \
  --target=integration_test/experimento_reporte_test.dart --profile -d <id>
flutter drive --driver=test_driver/banco_driver.dart \
  --target=integration_test/experimento_scroll_test.dart --profile -d <id>
```

No son pruebas de regresión y no corren en CI: existen para responder "¿cuál de
estas opciones gana?" cuando aparece un cuello.

## Arranque

| etapa | ms |
|---|---|
| abrir la base | 0 |
| cargar el catálogo | 7–15 |
| leer el rol del almacén seguro (1.ª vez del proceso) | 1104–1573 |
| leer el rol del almacén seguro (2.ª vez) | 0–3 |
| leer las preferencias simples | 0 |

El arranque lento **no eran los datos**: era abrir el almacén cifrado. Resuelto
en la [decisión 0027](../decisiones/0027-arranque-optimista-de-sesion.md) — la
app abre con una pista en preferencias y verifica por detrás. `restaurar sesión`
pasó de ~1200 ms a 0.

## Reporte del año: 200 ms, y por qué se dejó así

Es la consulta más cara de la app. Se probaron cinco caminos
(`integration_test/experimento_reporte_test.dart`, cifras de las dos consultas
agregadas, no del reporte completo):

| opción | ms | contra la base |
|---|---|---|
| como está | 120 | — |
| `ANALYZE` | 120 | 0 % |
| mmap de 64 MB | 114 | −5 % |
| índice cubriente en `linea_venta` | 105 | −12 % |
| **fecha denormalizada en `linea_venta` (sin JOIN)** | **74** | **−39 %** |

**Decisión: no se cambia nada por ahora.** La única opción con ganancia
apreciable pide una columna redundante que habría que mantener sincronizada en
cada venta, en cada importación y en cada restauración de backup, más una
migración de esquema. Eso es una invariante nueva a sostener para siempre, a
cambio de ahorrar unos 80 ms en la consulta que menos se pide — el reporte del
año se mira de vez en cuando, no en cada cobro. El techo tampoco crece sin
límite: el [archivado rodante](../decisiones/0025-archivado-anual-rodante.md)
cierra el libro al año, así que el volumen máximo de esta consulta está acotado.

Si algún día molesta de verdad, el camino ya está medido y es ese. `ANALYZE` no
sirve para nada acá y no hace falta volver a probarlo.

## Desplazar listas: el costo es el texto tallado

Al desplazar el catálogo, el banco encontró 102 de 106 frames fuera de
presupuesto, con el costo en **raster** (19,5 ms) y no en build (3,4). Raster es
la GPU pintando: la culpa está en qué se dibuja, no en el código que lo arma.

Variantes medidas sobre la misma cuadrícula
(`integration_test/experimento_scroll_test.dart`):

| variante | raster prom | frames lentos |
|---|---|---|
| como está | 12,9 ms | 50/125 |
| **sin texto tallado** | **7,9** | **4/125** |
| sin velo superior | 11,3 | 30/125 |
| sin tallado ni velo | 8,7 | 14/125 |
| con `RepaintBoundary` por tarjeta | 13,3 | 54/124 |

El **texto tallado** es el costo dominante: pinta el mismo texto varias veces
desplazado, y quitarlo lleva los frames lentos de 50 a 4. No se quita —es la
identidad visual de la app— pero es ahí donde hay que trabajar si el
desplazamiento tiene que ir más fino: abaratar el tallado, no aislar capas ni
tocar el velo.

`RepaintBoundary` por tarjeta **no sirve**: sale igual o peor. Flutter ya
envuelve cada ítem de una lista por su cuenta (`addRepaintBoundaries` es `true`
por defecto en `SliverChildBuilderDelegate`), así que agregarlo solo duplica
capas.

### Cómo medir esto sin engañarse

La primera versión del experimento midió cada variante **una sola vez, en
orden**, y dio una mejora enorme a las últimas — hasta "RepaintBoundary baja el
raster un 68 %". Era falso: lo que mejoraba entre variante y variante era el
proceso, con los shaders ya compilados y la GPU caliente. El error llegó a
aplicarse a las cuatro listas de la app antes de que el banco, sobre la pantalla
real, mostrara exactamente cero diferencia.

Por eso el experimento hace **dos pasadas y descarta la primera**. Cualquier
comparación de variantes gráficas en el mismo proceso necesita eso, o mide el
calentamiento en vez de la variante.
