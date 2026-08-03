# 0034 — La cara de un producto: iconos por categoría, y fotos apagables por ventana

**Estado:** Aceptada
**Fecha:** 2026-08-03

Sustituye la parte de figuras abstractas de la [0033](0033-banco-de-imagenes.md);
el resto de aquella decisión —el banco, las fotos fuera del backup, la
referencia de texto sin columna nueva— sigue en pie.

## Contexto

La 0033 resolvió el banco con **figuras abstractas** generadas por semilla:
distintas entre sí, estables y sin ocupar disco. El dueño las probó en el
aparato y el veredicto fue corto: no sirven.

Tenía razón, y el motivo es más interesante que "son feas". Aquellas figuras
cumplían todo lo que se les pidió *menos lo único que importaba*: **no
significan nada**. Un triángulo y dos círculos no dicen "café", así que para
encontrar algo en la lista había que leer el nombre igual — la imagen solo
ocupaba sitio. El objetivo declarado en la 0033 era "se reconoce por el rabillo
del ojo antes de leer el nombre", y una figura arbitraria no puede hacer eso por
construcción.

Además aparecieron dos fallos al conectar el banco a las pantallas de venta:

1. **La imagen elegida nunca se pintaba.** Venta Rápida y el carrito mostraban
   un `Icons.image_outlined` fijo —el mismo para todos— porque ese código era
   anterior al banco y nunca se cableó. Se veía "hay una imagen aquí" en vez de
   la imagen.
2. **El hueco salía del nombre.** La imagen competía con el texto por el espacio
   sobrante (`Expanded` contra `Expanded`), así que se llevaba media celda y
   dejaba "Arroz con pollo, tipo chino (medio)" cortado a media línea.

Y la 0033 daba por cerrado que en las pantallas de venta no cabían imágenes. Sí
caben: lo que no cabía era una imagen que le quitara el sitio al nombre.

## Decisión

### 1. Iconos de la casa, no figuras abstractas

Un catálogo de 16 iconos con significado —café, casado, batido, sopa,
repostería…— sacados de la carta de la soda. Siguen sin ocupar disco (son glifos
de la fuente que la app ya carga) y siguen fuera del backup.

La referencia pasa de `abs:` a `ico:`, pero **se sigue leyendo `abs:`**: el
aparato ya tenía productos con figura elegida, y dejar de entender el prefijo
viejo les habría borrado la imagen a todos de golpe. Las claves `figura-N` se
reparten por el catálogo en vez de caer todas en el icono neutro — no acierta el
significado, nadie puede, pero conserva que sean distintas entre sí, que es lo
único que aquellas figuras daban.

### 2. La categoría decide el icono por defecto

Un producto sin imagen elegida muestra el icono que le toca **por su
categoría**: "Arroces" → tazón, "Batidos en Leche" → licuadora. Sale del nombre
de la categoría, no de una columna nueva: las categorías ya las escribe el
negocio, y pedirle además que le asigne un dibujo a cada una sería trabajo de
configuración para llegar al mismo sitio.

Se comparan **principios de palabra**, no fragmentos sueltos. Buscar el
fragmento en cualquier posición era peor de lo que parece: `te` casaba dentro de
"reposTEría" y dejaba la repostería con cara de café. Con prefijo de palabra
además funciona el plural, que es como están escritas de verdad ("Arroces"
contra la pista `arroc`).

Consecuencia: **todo producto tiene cara**, y por eso ahora el hueco se reserva
siempre. Una cuadrícula donde unas celdas tienen dibujo y otras no se lee peor
que una donde todas lo tienen — las filas dejan de alinearse sin que eso
signifique nada.

### 3. La celda crece; el nombre no se recorta

El alto de la celda de Venta Rápida se **calcula** —hueco de imagen + tres
líneas de nombre + precio + aires— en vez de salir de una proporción con el
ancho. Ninguna de esas tres cosas depende de lo ancha que sea la columna.

Caben menos productos por pantalla. Es el precio de mostrar las dos cosas
enteras, y es la salida que el dueño eligió cuando planteó las dos posibles:
*"o se quita la imagen o se agranda el cuadro para siempre mostrar"*.

El cálculo usa los estilos del tema y el `textScaler` del sistema, no
constantes: con la letra grande de Android las tres líneas ocupan bastante más,
y un alto fijo volvería a cortar el nombre.

### 4. Las fotos se apagan por ventana

Configuración → Optimización gana un interruptor **por cada ventana que dibuja
fotos** (Venta Rápida, Venta, Inventario), junto al de efectos que ya existía.

Por ventana y no uno solo para toda la app porque no cuestan lo mismo ni sirven
para lo mismo: en Venta Rápida hay una cuadrícula entera que se desplaza con el
pulgar —donde un teléfono lento se nota—, mientras que en Inventario las fotos
son justamente lo que se está administrando. Quien atiende la caja puede querer
la carta sin fotos y el inventario con ellas.

**Apagarlas no deja el hueco vacío**: en su lugar va el icono de la categoría.
Lo que se ahorra es decodificar y escalar un JPEG por celda; un glifo no cuesta
nada. Así la pantalla sigue diciendo qué es cada cosa — es una optimización, no
una función que se quita.

### 5. El aspa de "fuera de la carta", a una esquina

Centrada y del mismo tamaño que el icono de abajo, las dos marcas se pisaban y
no se leía ninguna — un cubierto y una prohibición superpuestos son un borrón,
no dos datos. Y son dos datos que hacen falta a la vez: qué es el producto y que
está fuera de la carta. La respuesta es apartarlas, no callar una.

El aspa pasa a insignia pequeña en la esquina inferior derecha, con fondo propio
porque encima de una foto clara desaparecía.

## Alternativas descartadas

**Una columna `icono` en `categoria`.** Correcta en abstracto y más flexible,
pero pide migración de esquema, sync y una pantalla para elegir el icono de cada
categoría. Todo eso para llegar a lo que el nombre de la categoría ya dice.
Queda como salida si algún día el acierto por nombre resulta insuficiente.

**Derivar el icono del nombre del producto.** Más fino que por categoría, pero
mucho más frágil: "Arroz con pollo" tendría que decidir entre arroz y pollo, y
un desacierto por producto es más visible que uno por categoría.

**Un solo interruptor de fotos para toda la app.** Más simple, pero obliga a
elegir entre la carta rápida y el inventario con fotos, que son necesidades
distintas del mismo aparato.

**Apagar las fotos dejando el hueco vacío.** Ahorraría también el espacio, pero
convierte una opción de rendimiento en una pérdida de información.

## Qué queda sin resolver

- La cámara y la galería del banco siguen sin probarse en el aparato: abren apps
  del sistema y necesitan que alguien toque la pantalla.
