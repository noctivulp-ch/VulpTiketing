# 0036 — Sync par a par, con ronda periódica

**Estado:** Aceptada
**Fecha:** 2026-08-09

Sustituye el modelo de dos redes con orquestador de la
[0007](0007-topologia-sync.md), que quedó a medio implementar.

## Contexto

El dueño pidió probar la sincronización con cuatro nodos, en los cuatro cruces
posibles de rol. Se montó con tres teléfonos en la misma WiFi y se midió
contando filas en la base de cada uno, no mirando la pantalla.

El resultado, con el catálogo importado en un Gerente:

| Caso | categorías | productos | ventas |
|---|---|---|---|
| Gerente → Gerente | 8 | 39 | 1 |
| Gerente → **Registradora** | **0** | **0** | **0** |

La Registradora **veía** al Gerente por mDNS —está en su log, con
`"rol":"gerente"`— y no sincronizaba nunca. Arrancaba vacía y se quedaba vacía
con el catálogo entero a un metro.

La causa era una línea: `for (final par in _paresDelMismoRol)`. El diseño de la
0007 separaba dos redes por rol y las unía con un handshake entre orquestadores
—el paso 3/4—, que nunca se implementó. Sin ese paso, los dos grupos no se
tocan.

Salieron otros dos fallos del mismo montaje, ninguno visible con dos nodos:

- **El sync solo ocurría al descubrir.** Se disparaba con el stream de mDNS, o
  sea al aparecer o desaparecer un aparato. Se importó el catálogo con los dos
  gerentes ya conectados y el receptor se quedó en cero: la membresía no había
  cambiado. Había que apagar y encender el interruptor a mano.
- **La pantalla no se enteraba.** Las filas entran directo a la base sin pasar
  por los notifiers. El receptor tenía 39 productos y Venta Rápida seguía
  diciendo "la bandeja está vacía" hasta reiniciar la app.

## Decisión

### Se sincroniza con todos los pares, no solo con los del mismo rol

Es volver a la **opción A** que la propia 0007 había puesto sobre la mesa y
descrito como "más simple", descartada entonces para reducir tráfico.

La separación **no era por seguridad** — conviene dejarlo escrito, porque un
lector futuro podría suponerlo. Los roles son de interfaz, no de privilegio
([0002](0002-roles-funcionales-no-seguridad.md)), y los dos grupos comparten
exactamente los mismos datos.

A la escala real —cuatro aparatos, doce conexiones por ronda, filas que caben en
un JSON de kilobytes— el ahorro que buscaba la 0007 no compra nada, y costaba
que la función no existiera. `_paresDelMismoRol` se conserva porque el
coordinador lo sigue usando para elegir orquestador: si algún día hiciera falta
el ahorro, la pieza está.

### Hay una ronda cada 15 segundos

Los pares ya conocidos se repasan aunque la red no cambie. Quince segundos
porque lo que viaja es una venta de mostrador: que tarde un cuarto de minuto no
molesta a nadie, y preguntar más seguido gasta batería en varios teléfonos a la
vez.

Con un cerrojo, para que la ronda y un evento de descubrimiento no se pisen. Dos
pasadas a la vez no corrompen nada —LWW es idempotente— pero duplican tráfico y
escrituras justo cuando la red ya está movida.

### Al terminar una ronda se refresca la pantalla

Se invalidan producto, categoría, venta y reportes. Una vez por ronda y no por
peer: con cuatro aparatos, invalidar dentro del bucle reconstruiría el catálogo
tres veces para acabar en el mismo sitio.

## Verificado en los aparatos

Tras el cambio, con un Gerente y una Registradora en la misma WiFi:

- **Gerente → Registradora**: 8 categorías, 39 productos y la venta. Era el caso
  que daba 0/0/0.
- **Registradora → Gerente**: se hizo una venta en la Registradora y apareció en
  el Gerente **sin tocar nada**, en la ronda siguiente.
- **Gerente ↔ Gerente**: seguía funcionando y sigue.

## Lo que sigue abierto

- **El interruptor no persiste.** Al reiniciar la app el sync queda apagado y
  hay que activarlo a mano. La 0007 ya anotaba que arrancarlo solo es una
  decisión de producto pendiente; ahora hay un motivo más concreto para
  tomarla.
- **El anuncio mDNS conserva el rol viejo** un rato después de cambiar de rol:
  se vio un aparato anunciándose como `gerente` con la app ya en Registradora.
  Con el cruce implementado es inofensivo —se sincroniza igual— pero deja la
  elección de orquestador mirando datos viejos.
- **`todosLosDispositivosSincronizados`** sigue en `false` cuando hay pares
  conocidos. El gate de purga ([0015](0015-purgar-producto-borrado-fisico-condicional.md)) no
  cambió en esta decisión.
