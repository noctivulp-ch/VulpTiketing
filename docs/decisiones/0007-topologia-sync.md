# 0007 — Topología de sincronización multi-dispositivo

**Fecha:** 2026-07-26
**Estado:** Aceptada — opción B (dos redes con orquestador electo), con el diseño detallado abajo

## Contexto

El esquema debe soportar una Gerente principal y posiblemente varias Registradoras, cada una en su propio dispositivo (los roles son de interfaz, no de privilegio estricto — [decisión 0002](0002-roles-funcionales-no-seguridad.md)).

Propuesta inicial del usuario: dos "redes" lógicas — dispositivos Gerente sincronizan entre sí, dispositivos Registradora sincronizan entre sí. Cuando una red no tiene tareas de sync pendientes, pregunta el estado de la otra red; si ninguna tiene tareas pendientes y hay cambios, sincronizan ambas redes entre sí. En cada red se elige de forma agnóstica un cliente "principal" que orquesta los syncs de esa red.

## Opciones

**A — Sync par-a-par oportunista, sin orquestador (recomendada)**
Cualquier dispositivo sincroniza con cualquier peer que descubra vía mDNS, sin distinguir "red Gerente" vs "red Registradora" ni elegir un orquestador. Cuando dos dispositivos se conectan (por estar en la misma red Wi-Fi), intercambian y aplican LWW fila por fila. Con el tiempo, los cambios se propagan a todos los dispositivos por "contagio" (gossip).
- Ventaja: no hay elección de líder ni estados de red que mantener — bastante menos código y menos casos borde para depurar. Escala naturalmente a N Gerentes y N Registradoras sin lógica adicional.
- Desventaja: en el peor caso (todos los dispositivos rotando conexión sin coincidir nunca), la propagación completa tarda más rondas que con un hub fijo — para un local pequeño con pocos dispositivos y personal presente, esto no debería ser un problema real.

**B — Dos redes con orquestador electo (idea original del usuario)**
Tal como se describió arriba.
- Ventaja: menos tráfico de red si hubiera muchos dispositivos (no es el caso de una soda pequeña).
- Desventaja: requiere implementar elección de líder y el estado de "red Gerente"/"red Registradora" con sus transiciones — bastante más superficie de bugs para el beneficio que aporta a esta escala.

**C — Hub fijo (Gerente principal siempre orquesta)**
Las Registradoras solo sincronizan contra la Gerente principal, nunca entre sí directamente.
- Ventaja: más simple que A y B.
- Desventaja: si la Gerente principal está apagada, dos Registradoras no pueden verse los cambios entre sí hasta que la Gerente vuelva a estar en línea.

## Recomendación (histórica, no elegida)

A hubiera sido más simple de implementar, pero el usuario prefirió conservar el modelo de dos redes con orquestador para reducir tráfico de sync, con el entendimiento de que hay que pulir el diseño. Diseño final abajo.

## Diseño acordado

Dos grupos lógicos según el rol del dispositivo: **red Gerente** (dispositivos con rol Gerente) y **red Registradora** (dispositivos con rol Registradora).

1. **Intra-grupo**: cualquier dispositivo sincroniza directo (pairwise) con los pares de su mismo grupo que descubra por mDNS, aplicando LWW normal. No hace falta orquestador para esto.
2. **Elección de orquestador por grupo**: cada grupo elige, de forma agnóstica y recalculada cada vez que cambia la membresía visible, un dispositivo "principal" que actúa como orquestador del grupo — regla simple y determinista (ej. el UUID de dispositivo más bajo entre los actualmente visibles), sin necesidad de un protocolo de consenso distribuido.
3. Cuando un grupo no tiene tareas de sync intra-grupo pendientes (todos sus miembros visibles están al día entre sí), su orquestador consulta el estado del orquestador del otro grupo (si lo tiene visible en la red — no requiere que ambos grupos estén en el mismo Wi-Fi físico si hay algún puente, pero el caso normal es misma red local).
4. Si ambos orquestadores confirman que no tienen tareas pendientes en su propio grupo y detectan cambios que el otro grupo no tiene, sincronizan entre sí (orquestador-a-orquestador) y cada uno propaga lo recibido a su grupo por el mecanismo normal del paso 1.

### Notas de robustez

- La elección de orquestador es *best-effort*, no consenso distribuido estricto: si dos dispositivos se creen orquestador momentáneamente (ej. por una partición de red pasajera), el peor caso es una sincronización cruzada redundante — inofensiva, porque LWW es idempotente.
- Si el orquestador elegido se desconecta, el grupo recalcula la regla en el siguiente ciclo de descubrimiento mDNS — no requiere un mecanismo explícito de "renuncia".
- La sync nunca es requisito para operar: toda la app funciona 100% offline; esto corre en segundo plano cuando hay red disponible.

## Addendum (2026-07-27) — la pertenencia a una red es una propiedad en vivo, no fija

Al diseñar el flujo de Login se estableció que el rol de un dispositivo se puede **re-elegir en cada login** (no queda fijado una sola vez en el primer setup) — pensado para un dispositivo compartido donde ocasionalmente se necesita cambiar de rol (evento infrecuente, no cada vez que se abre la app). Esto planteó la duda de si contradice el diseño de arriba, que habla de "dispositivos con rol Gerente"/"con rol Registradora" como si fuera una propiedad estable.

No hay contradicción, y no hace falta rediseñar nada: la pertenencia a "red Gerente" o "red Registradora" siempre fue una propiedad **derivada en vivo** del rol activo en ese momento (leído del almacenamiento seguro nativo — [0011](0011-credenciales-almacenamiento-nativo.md)) y anunciada vía mDNS cada vez que el dispositivo se anuncia en la red — nunca una lista fija registrada en algún lado. Un cambio de rol es, para efectos del algoritmo, exactamente el mismo tipo de evento que un dispositivo que se desconecta de un grupo y aparece en el otro: cada grupo simplemente recalcula su orquestador entre los dispositivos actualmente visibles, que es justo lo que ya hace en cada ciclo de descubrimiento mDNS (ver "Notas de robustez" arriba). Es el mismo patrón que usan protocolos de membership dinámico ya probados (gossip, elección de líder tipo Raft/SWIM) — a la escala de un puñado de dispositivos en una sola red local, esto no presenta dificultades nuevas.

Única consecuencia práctica: existe una ventana transitoria breve, acotada por el intervalo de descubrimiento mDNS, donde el liderazgo de un grupo puede quedar desactualizado justo después de un cambio de rol — inofensivo, mismo caso ya aceptado de "sincronización cruzada redundante".
