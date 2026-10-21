# Referencias visuales — cómo "se ve" realmente una caja bento

Imágenes de referencia (2026-07-29), guardadas para corregir un sesgo de diseño real detectado por el usuario en la UI actual.

> Las fotografías son de terceros y no se publican con el repositorio: aquí queda solo su descripción.

## Las 6 referencias

| Archivo | Qué muestra |
|---|---|
| `bento-01-lacado-rojo-brillante.jpeg` | Bandeja lacada roja, compartimentos de tamaño desigual, brochetas cruzando por encima de dos casillas |
| `bento-02-lacado-marron-formal.jpeg` | Bandeja de laca oscura formal, grid 3×2 + sopa aparte, papel/palillos apoyados sobre la bandeja exterior |
| `bento-03-madera-tallada.jpeg` | Caja de madera oscura torneada, un solo divisor recto separando arroz de guarnición |
| `bento-04-apilado-diagonal.png` | 3 bandejas cuadradas apiladas en diagonal, cada una con su propio grid interno |
| `bento-05-lacado-negro-mate.jpeg` | Laca negra mate, grid asimétrico, un cuenco de vidrio real insertado en una celda |
| `bento-06-lacado-rojo-negro.jpeg` | Bandeja roja/negra, grid 2×3, líneas divisorias diagonales finas dentro de una celda grande |

## El hallazgo — "hundido" vs. botón genérico

Cita textual del usuario: *"si te fijas bien como funciona una caja bento, todo se ordena y muestra sin ocultar nada, pero también el contenido está contenido, en nuestra app se ve como si fueran botones por la elección de colores, tiene que parecer que los elementos están 'hundidos', actualmente se ve genérico, te dejaste llevar por el sesgo de diseño por defecto."*

En las 6 referencias, cada compartimento es un **hueco tallado/moldeado en el mismo bloque de material** de la bandeja — no una pieza separada puesta encima. Eso se lee visualmente así:

- La pared interior de cada celda proyecta una sombra sutil hacia adentro (arriba/lateral), y el fondo de la celda recibe menos luz que el borde exterior de la bandeja. La lectura es "esto es un pozo", no "esto es una tarjeta flotando".
- El borde entre celdas es un **muro compartido** (una sola pared separa dos compartimentos), nunca dos bordes redondeados enfrentados con un gap de fondo entre ellos.
- El color de la bandeja (laca roja, negra, madera) es uniforme en toda la pieza — las celdas no cambian de color para "destacarse", se distinguen por la geometría del hueco y la comida que contienen.

Nuestra UI actual (`bento_theme.dart` + los widgets de cada pantalla) usa el patrón contrario, que es el default de Material Design: contenedores con `color: surfaceContainer` más claro/distinto que el fondo, radio de esquina redondeado en las 4 esquinas, y sombra/elevación hacia **afuera** (o ausencia total de sombra, lo cual sin sombra interna tampoco ayuda) — eso es exactamente lo que hace que algo se lea como una **tarjeta elevada o un botón**, no como un compartimento hundido en una superficie continua.

## Implicación para el próximo trabajo de diseño

Pendiente de trabajar en la próxima sesión (el usuario adelantó "un estilo más bento", sin detallar aún). Lo que ya se puede anticipar del hallazgo:

- Revisar todo uso de `BoxShadow` en `bento_theme.dart`/widgets de cada pantalla — hoy probablemente no hay ninguna, o es una sombra "de tarjeta" (hacia afuera). Un compartimento hundido necesita una sombra **interior** (`inset` — Flutter no tiene `BoxShadow` con inset nativo, se logra con un `Container` decorado con gradiente sutil hacia el borde, o un segundo `Container` interior con `BoxDecoration` y offset negativo simulando el borde superior/izquierdo más oscuro).
- Revisar la paleta: si cada celda tiene un color de fondo distinto al contenedor padre (en vez de compartir el mismo tono de "bandeja" y diferenciarse solo por la geometría del hueco), eso refuerza la lectura de "botón separado" en vez de "pozo en la misma superficie".
- Los separadores entre celdas de la [decisión 0023](../../decisiones/0023-refinamiento-bento-post-implementacion.md) (figuras conectadas con matices) van en la dirección correcta conceptualmente, pero probablemente faltó el detalle de sombra/luz que hace que la unión se lea como "hundido" y no solo "pegado".
