# 0031 — Paridad de escritorio: teclado y touchpad

**Estado:** Aceptada
**Fecha:** 2026-08-03

## Contexto

La app corre en Android y en escritorio, pero todo lo que se agregó últimamente
se pensó con un teléfono en la mano. Cambiar de ventana, abrir el panel de
productos, recorrer los rangos de Reportes, exportar: en el aparato son gestos, y
en escritorio **no existía ninguno de esos caminos**.

Peor que "faltan gestos": exportar un reporte solo se podía mantener presionado
el total con el ratón — un gesto táctil traducido mal a un dispositivo que tiene
teclado. Quien trabaja con teclado hacía el doble de camino para todo, y no
había **un solo atajo** en la app.

## Decisión

Dos caminos, cada uno con lo que su dispositivo hace bien.

### Touchpad: dos dedos en horizontal cambian de ventana

Es el equivalente del deslizamiento de **un** dedo del teléfono, y no contradice
la regla de la [decisión 0030](0030-gestos-un-dedo-navega-varios-actuan.md): en
un trackpad no existe arrastrar con un dedo sin apretar —eso mueve el cursor—,
así que el gesto de moverse es el de dos.

- **El vertical no se toca.** Ahí el gesto de dos dedos es el scroll de toda la
  vida, y robárselo a las listas sería cambiar un atajo por un estorbo.
- Llega como `PointerScrollEvent` con `scrollDelta.dx`, no como punteros, así
  que el gesto táctil no lo ve: hay un `Listener(onPointerSignal:)` aparte.
- **Se acumula.** Un gesto de trackpad llega en decenas de eventos diminutos;
  actuar con el primero cambiaría de ventana con el roce más leve. Hacen falta
  120 px y hay una pausa de 250 ms entre gestos, para que seguir deslizando no
  encadene saltos hasta el final.
- El signo va al revés que el arrastre: el trackpad manda `dx` positivo cuando
  los dedos van a la izquierda.

### Teclado: lo que en el teléfono es gesto

| | |
|---|---|
| `Ctrl+1`…`Ctrl+5` | ir a una ventana |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | siguiente / anterior |
| `Ctrl+←` `Ctrl+→` | ídem |
| `←` `→` en Reportes | recorrer rangos, o pasar de página dentro del detalle |
| `RePág` `AvPág` | pasar de página |
| `Ctrl+E` | exportar lo que se está mirando |
| `Ctrl+F` | elegir el período |
| `Esc` | salir del detalle |
| `Ctrl+P` en Panel de Venta | abrir o cerrar el panel de productos |

**Qué lleva `Ctrl` y qué no:** con `Ctrl` lo que podría chocar con escribir
—letras, dígitos, flechas donde hay campos—; sin `Ctrl` lo que no. Reportes no
tiene un solo campo de texto, así que ahí las flechas y las teclas de página van
directas; Panel de Venta sí tiene el de Recibí, y por eso su atajo es `Ctrl+P`.

En los extremos no se da la vuelta, ni con teclado ni con touchpad: la misma
regla que con el dedo.

## Alternativas descartadas

- **Gestos de tres dedos en el touchpad** para las acciones, replicando el "dos
  dedos" del teléfono: en Linux los toma el compositor —Niri los usa para
  cambiar de espacio— así que ni siquiera llegan a la app.
- **`Shortcuts`/`Actions` con intents propios**: la maquinaria completa de
  Flutter para acciones que no viajan por el árbol. `CallbackShortcuts` en cada
  pantalla hace lo mismo y se lee de un vistazo; lo que no coincide sigue
  subiendo solo.
- **Traducir el "mantener presionado" al ratón y dejarlo así**: es lo que había,
  y es exactamente el gesto táctil mal traducido que motivó esta decisión.

## Consecuencias

- Las acciones de dos dedos (abrir panel, elegir período, exportar) **no** tienen
  gesto en escritorio: van por teclado. Se acepta porque ahí el rail está siempre
  visible y los botones también — el gesto era el atajo de un sitio donde no
  caben botones.
- Un atajo nuevo obliga a decidir si lleva `Ctrl`, y eso depende de si la
  pantalla tiene campos de texto.
- `test/paridad_escritorio_test.dart` cubre las dos vías, incluido lo que **no**
  debe pasar: el scroll vertical no navega, y las flechas sin `Ctrl` tampoco.
