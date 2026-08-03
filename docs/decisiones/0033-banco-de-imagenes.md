# 0033 — Banco de imágenes: figuras de fábrica y fotos propias

**Estado:** Aceptada
**Fecha:** 2026-08-03

## Contexto

`producto.imagen` existía en el esquema desde el principio y **nunca se usó**:
el formulario lo dejaba fuera a propósito porque sincronizar el archivo entre
dispositivos era una pregunta sin resolver, y medio adjuntar una foto —elegirla
y que nunca llegue al otro aparato— es una promesa rota.

El dueño lo pidió acotado y con la forma resuelta: un **banco de imágenes** con
figuras genéricas por defecto y la posibilidad de sumar fotos desde la galería o
la cámara. Y **solo para gestión de inventario**: en las pantallas de venta no
entran, se probó al diseñarlas y una foto por tarjeta dejaba el nombre y el
precio —lo que de verdad se lee al cobrar— sin sitio.

## Decisión

### Un banco, no un adjunto por producto

Las imágenes viven en el banco y los productos las **referencian**. Una foto
agregada sirve para todos los que la quieran: cuatro presentaciones del mismo
casado no obligan a sacar cuatro fotos iguales.

### Figuras que se dibujan, no archivos

El banco trae doce **figuras abstractas de fábrica**: no hay que agregar nada
para tener de dónde elegir, y no pesan ni un byte. Se dibujan con un
`CustomPainter` a partir de una semilla, así que son idénticas en todos los
aparatos sin que nadie las copie.

Y un producto **sin imagen elegida** no se ve con un icono genérico: se ve con
una figura derivada de su propio id. En una lista de treinta y nueve productos,
treinta y nueve iconos idénticos no ayudan a encontrar nada — son ruido con
forma de dato. Una figura propia se reconoce por el rabillo del ojo antes de
leer el nombre, que es como se busca en una lista larga.

### La referencia es texto, sin columna ni tabla nuevas

En `producto.imagen` va una cadena, y de ella sale qué es:

- `abs:<semilla>` → una figura
- cualquier otra cosa → el **nombre** de un archivo del banco

Solo el nombre, nunca la ruta: el directorio de datos cambia entre
instalaciones y entre sistemas, y una ruta absoluta guardada en la base deja de
resolver en cuanto el aparato es otro — o el mismo, reinstalado.

Con esto el esquema, la sincronización y el backup quedan **exactamente como
estaban**.

### El banco NO va en el backup

El `.tiketback` es la copia de la contabilidad. Meterle las fotos lo
multiplicaría de tamaño para proteger algo que no es un dato contable y que se
puede volver a sacar con la cámara.

Un producto cuya foto no está en este aparato —base restaurada, o traída por
sincronización— se ve con su figura propia: exactamente lo mismo que uno que
nunca eligió imagen. No hay hueco en blanco ni mensaje de error, porque no hay
nada roto.

## Alternativas descartadas

- **Meter las fotos en el backup.** Fue el primer intento y estaba escrito
  —piezas nuevas en el manifiesto cifrado, restauración a su carpeta— antes de
  que el dueño lo corrigiera. Se revirtió entero: hinchaba el backup con datos
  no contables.
- **Guardar la ruta del archivo que eligió el usuario.** El original se mueve, se
  borra, o vive en una carpeta que la app deja de poder leer, y el producto se
  queda con una ruta muerta. Por eso se copia al banco.
- **Una tabla `imagen` en la base.** Haría falta enseñarle una quinta tabla al
  sync y crearla en cada libro para no ganar nada: el banco es local por
  diseño, y lo único que se sincroniza es la referencia, que ya cabe en la
  columna que existe.
- **Guardar las figuras como SVG en `assets/`.** Ya hay infraestructura de
  iconografía vectorial (0020), pero doce archivos para algo que se dibuja con
  veinte líneas es peso de repositorio y una lista que mantener.

## Consecuencias

- Dependencia nueva: `image_picker`, que es la que da galería **y** cámara. El
  `file_picker` que ya estaba no abre la cámara.
- Permiso `CAMERA` en Android, declarado con `uses-feature required="false"`:
  sin cámara la app sigue sirviendo entera, solo se pierde el atajo de sacar la
  foto en el momento.
- **No se pide permiso de almacenamiento**: las fotos de galería llegan por el
  selector del sistema, que entrega el archivo sin que la app pueda leer nada
  más.
- Las fotos se piden ya reducidas a 512 px al selector: el destino es una
  miniatura de 44 dp y una vista previa, no un archivo de impresión.
- Borrar una foto del banco no comprueba quién la usaba. El producto que la
  tuviera se queda con una referencia que no resuelve, y eso ya se ve como una
  figura. Bloquear el borrado obligaría a recorrer el catálogo entero para
  contestar algo que el usuario ya decidió al tocar "quitar".
