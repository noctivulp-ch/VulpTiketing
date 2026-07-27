# 0005 — Manejo de borrados en sync

**Fecha:** 2026-07-26
**Estado:** Aceptada — opción A (soft-delete / tombstone)

## Contexto

LWW (Last Write Wins) sobre `updated_at` resuelve conflictos de *actualización*: si dos dispositivos editan la misma fila offline, gana la de timestamp más reciente. Pero **un borrado no dice nada nuevo en `updated_at`** — si el dispositivo A borra un Producto y el dispositivo B lo actualizó offline al mismo tiempo, un borrado físico no deja rastro para que B sepa que debía respetar el borrado (o que A sepa que hay un update más nuevo).

## Opciones

**A — Soft-delete con tombstone (recomendada)**
Agregar columna `deleted_at` (nullable, ISO-8601) a las tablas sincronizables. Borrar = poner `deleted_at` + actualizar `updated_at`. Nunca se borra la fila físicamente durante la vida útil de la sync; las queries de la app filtran `WHERE deleted_at IS NULL`. LWW aplica igual que a cualquier otro cambio, comparando `updated_at`.
- Ventaja: cero mecanismos nuevos — reutiliza la misma columna `updated_at` y la misma lógica LWW que ya existe para updates.
- Desventaja: las tablas nunca se "achican" solas (para una soda pequeña, el volumen de filas es bajo — no es un problema real).

**B — Log de IDs borrados aparte**
Tabla separada `deleted_ids (id, tabla, deleted_at)`. Permite purgar físicamente las filas originales tras propagar el borrado.
- Ventaja: las tablas de negocio quedan limpias.
- Desventaja: una estructura de sync adicional a mantener, más lógica al reconciliar.

**C — Sin borrado duro, solo "desactivar"**
Nunca se borra un Producto, solo se marca inactivo (a nivel de negocio, no de sync). Evita el problema por completo.
- Ventaja: simplicidad total.
- Desventaja: es una decisión de producto (¿tiene sentido "desactivar" en vez de "borrar" para el usuario?), no solo técnica — y no cubre el caso de borrar una Venta por error.

## Recomendación

A. Es la que menos superficie nueva agrega y encaja directamente con el patrón `updated_at`/LWW que ya está definido en Architecture.feature.

## Nota posterior (2026-07-26)

Esta decisión aplica a tablas cuyo ciclo de vida incluye descontinuación (Producto, Categoria). **No aplica a Venta**: la desventaja mencionada arriba en la opción C ("no cubre el caso de borrar una Venta por error") quedó resuelta de otra forma — [decisión 0009](0009-cruds-independientes-por-entidad.md) estableció que una Venta nunca se borra (ni hard ni soft-delete), solo se **revierte** (transición de `estado`, no un tombstone). Venta y LineaVenta no llevan columna `deleted_at`.
