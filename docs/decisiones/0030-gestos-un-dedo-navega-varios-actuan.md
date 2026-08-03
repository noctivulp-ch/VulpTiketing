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
- **Dos y tres dedos** → reservados para acciones. Todavía no hay ninguna, pero
  el gesto de navegación ya se aparta de ellos.

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
  soltar. Se acepta a cambio de no tocar el shell. Si molesta en uso real, la
  salida es una animación de transición, no un `PageView`.
- Acostado el gesto es menos intuitivo —las ventanas se leen en horizontal y el
  dedo también va en horizontal—, y el usuario ya lo dio por bueno.
- Cualquier gesto nuevo tiene que declarar cuántos dedos usa **antes** de
  escribirse. Uno es territorio de la navegación.
