# 0030 — Gestos: un dedo navega, dos o tres actúan

**Estado:** Aceptada
**Fecha:** 2026-08-03

## Contexto

Cambiar de ventana solo se podía tocando la banda de navegación. En un teléfono
que se sostiene con una mano mientras la otra cobra, alcanzar cinco iconos con
el pulgar es un movimiento que se repite cientos de veces al día.

Al pedir el gesto de deslizar, el usuario dejó dicho hacia dónde va esto:
*"después usamos gestos con dos dedos para otras acciones, tomalo en cuenta
(navegación con un dedo, acciones con dos o tres dedos)"*.

Eso convierte una función suelta en una **convención**: lo que se decida ahora
sobre cuántos dedos reclama cada gesto condiciona todo lo que se agregue
después.

## Decisión

**Un dedo navega. Dos o tres hacen cosas.**

- **Un dedo, arrastre horizontal** → cambia de ventana. A la izquierda, la
  siguiente; a la derecha, la anterior. Como pasar la hoja de un cuaderno.
- **Dos y tres dedos** → acciones. La primera: **dos dedos hacia abajo abren el
  panel de productos de Ventana 2; hacia arriba lo cierran.**

`NavegacionPorGesto` cuenta los punteros en pantalla con un `Listener` y anula
el arrastre en cuanto hay más de uno — incluso a mitad del gesto. **No basta con
usar un `HorizontalDragGestureRecognizer`**: ese sigue atendiendo al primer dedo
aunque aparezca un segundo, así que dos dedos deslizando cambiarían de ventana
igual, y la primera acción de dos dedos que se agregara pelearía con la
navegación en la arena de gestos.

Detalles que salieron de usarlo:

- **En los extremos no da la vuelta.** Saltar de Configuración a Venta Rápida de
  un tirón desorienta más de lo que ahorra.
- **Umbral por fracción del ancho** (18 %), no por píxeles: acostado la pantalla
  mide el doble y pedir el mismo recorrido haría el gesto el doble de trabajoso.
- **O por velocidad** (320 px/s): el gesto rápido de pasar la hoja, que con el
  pulgar se hace sin estirar.
- **Manda el signo del recorrido, no el de la velocidad.** Al soltar se puede
  frenar hacia atrás, y entonces la velocidad final apunta al revés de lo que se
  arrastró.
- **`HitTestBehavior.deferToChild`**: lo que ya escucha un toque —un botón, una
  lista— lo sigue recibiendo. El gesto solo entra donde nadie lo reclama.

### Acciones de dos dedos

`GestoDeDosDedos` usa un `ScaleGestureRecognizer`, que es el único reconocedor
de la casa que sabe **cuántos dedos hay** (`pointerCount`). Un
`VerticalDragGestureRecognizer` sigue al primer puntero y no distingue uno de
dos, que es la distinción sobre la que se apoya toda esta convención.

- **Dispara al cruzar el umbral, no al soltar.** La app prioriza velocidad;
  esperar a que se levanten los dedos agrega una espera que no aporta.
- **Umbral de 48 dp**, un objetivo táctil: lo bastante como para no saltar al
  reacomodar el agarre, y lo bastante poco como para hacerse con el pulgar y el
  índice sin mover la mano.
- **Una vez por gesto.** Sin eso, seguir arrastrando dispararía en cada frame.
- **El sentido que no corresponde se pasa como `null`.** Repetir el gesto hacia
  abajo no puede cerrar lo que acaba de abrir.
- **El botón de la costura sigue estando.** El gesto es un atajo para quien
  cobra con una mano todo el día, no la única forma de hacerlo.

Abrir "hacia abajo" es el sentido de desplegar algo recogido, y da igual que el
panel esté arriba de pie y al costado acostado: lo que se recuerda es el sentido
del gesto, no dónde aparece la caja.

## Alternativas descartadas

- **`PageView` en vez de `IndexedStack`**: daría el arrastre con la ventana
  siguiendo al dedo, gratis. Pero `PageView` construye y destruye páginas al
  moverse, y el `IndexedStack` está ahí a propósito — fue lo que quitó el
  parpadeo al cambiar de pestaña (decisión 0023). Cambiar el shell entero por
  una animación de arrastre no compensa.
- **`GestureDetector` con `onHorizontalDrag`**: es lo obvio y es lo que no
  distingue un dedo de dos.
- **Dar la vuelta en los extremos**: probado mentalmente contra el uso real —
  quien está en Configuración y desliza no quiere aterrizar en la caja.

## Consecuencias

- El gesto **no mueve la ventana mientras se arrastra**: el cambio ocurre al
  soltar. **No se va a animar**: el usuario fijó el orden de prioridades de la
  app —velocidad y usabilidad primero, después ser intuitiva, y la estética al
  final— y una transición cuesta frames en un teléfono de gama baja para no
  agregar información.
- Acostado el gesto es menos intuitivo —las ventanas se leen en horizontal y el
  dedo también va en horizontal—, y el usuario ya lo dio por bueno.
- Cualquier gesto nuevo tiene que declarar cuántos dedos usa **antes** de
  escribirse. Uno es territorio de la navegación.
