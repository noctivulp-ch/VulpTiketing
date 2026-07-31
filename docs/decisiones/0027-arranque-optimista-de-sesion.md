# 0027 — Arranque optimista de sesión: el rol se duplica como pista en preferencias

**Fecha:** 2026-07-31
**Estado:** aceptada

## Contexto

La app tardaba en abrirse cuando ya había sesión iniciada. La causa era una
suposición equivocada —que el peso estaba en cargar los datos— y solo se
resolvió midiendo en el teléfono del negocio, en modo profile, con
`scripts/banco-rendimiento.sh`:

| etapa del arranque | ms |
|---|---|
| abrir la base de datos | 0 |
| cargar el catálogo | 7–15 |
| **leer el rol del almacén seguro (1.ª vez del proceso)** | **1104–1573** |
| leer el rol del almacén seguro (2.ª vez) | 0–3 |
| leer las preferencias simples | 0 |

La segunda lectura es instantánea, así que el costo no es leer el dato: es
**abrir** el almacén cifrado (Keystore + EncryptedSharedPreferences). En este
aparato eso es más de un segundo, y el arranque entero lo esperaba porque
`VulpTiketingApp` no decide qué pantalla mostrar hasta saber si hay sesión.

Optimizar la consulta no servía de nada. La decisión real era **dónde vive el
rol activo**.

## Decisión

El rol activo se **duplica**: la verdad sigue en el almacén seguro y se agrega
una *pista* en las preferencias simples (`rol_activo_pista`).

Al arrancar:

1. Se lee la pista (0 ms) y, si existe, la app abre **ya** con ese rol.
2. La lectura del almacén seguro sigue por detrás, sin bloquear.
3. Cuando llega, manda sobre la pista: si difieren, corrige — y corregir puede
   significar cerrar la sesión y mandar al Login.
4. Si **no** hay pista, se espera como antes. Es el caso de la primera apertura
   tras actualizar desde una versión que no la escribía, y ahí vale más un
   arranque lento que un parpadeo del Login.

Cerrar sesión borra las dos, y una pista huérfana —sin sesión real detrás— se
borra sola en la verificación.

## Qué se acepta a cambio

Durante aproximadamente un segundo, alguien que hubiera **manipulado las
preferencias internas de la app** podría ver la pantalla de un rol que no le
corresponde, hasta que la verificación lo eche.

Se acepta porque:

- quien puede escribir en las preferencias de la app ya puede leer y escribir
  su base de datos completa —ventas, precios, catálogo—, que es el activo real
  del negocio: la pista no abre una puerta que ese acceso no tenga abierta;
- la **contraseña sí es un secreto** y no se mueve: su hash Argon2id y su salt
  siguen únicamente en el almacén seguro. La pista no permite autenticarse,
  solo adelanta qué pantalla pintar;
- la corrección es automática y no depende de que el usuario haga nada.

Lo que **no** se hizo, y por qué:

- *Mover el rol a preferencias y punto*: deja la sesión falsificable de forma
  permanente, no por un segundo.
- *Precalentar el almacén en `main()`*: el costo es el mismo y sigue cayendo
  dentro del arranque; ya se leía en paralelo con el montaje.
- *Cambiar el modo de cifrado del plugin*: invalidaría lo ya guardado —sesión y
  contraseñas— y el ahorro no está medido.

## Verificación

- `test/sesion_arranque_test.dart` cubre los cuatro casos, y el que importa es
  el de la pista que miente: si una pista falsa sobreviviera, esto sería un
  agujero y no una optimización.
- En el aparato, `restaurar sesión (con pista)` pasó de ~1200 ms a **0 ms**.
  La medición se hace como primera operación del proceso a propósito: si el
  banco tocara el almacén antes, mediría con la caché puesta y diría que todo
  va rápido.
