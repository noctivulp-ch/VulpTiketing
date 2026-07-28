# 0018 — Orden y búsqueda de Producto: agrupación por categoría + ranking nombre > categoría

**Fecha:** 2026-07-28
**Estado:** Aceptada

## Contexto

Al quedar pendiente el hallazgo de que Ventana 1 (Venta Rápida) y Ventana 3 (CRUD Producto) no aprovechaban `categoria` para navegar un catálogo grande, el usuario propuso dos mecanismos concretos, independientes entre sí.

## Decisión

### 1. Orden de visualización (setting global en Configuración)

Un ajuste en Configuración con tres modos, aplicado consistentemente a cualquier listado de Producto (Ventana 1, el panel de agregar producto de la Ventana 2, y Ventana 3):

- **Alfabético** (default) — lista plana ordenada por nombre.
- **Precio** — lista plana ordenada por precio.
- **Categoría** — agrupado por categoría, cada grupo separado visualmente con el nombre de la categoría como encabezado. Productos sin categoría van en un grupo "Sin categoría" al final.

Es una preferencia de UI local del dispositivo, no un dato de negocio — vive en almacenamiento local simple (ej. `shared_preferences`), **no** en el almacenamiento seguro que usan rol/contraseña ([0011](0011-credenciales-almacenamiento-nativo.md)), porque no es sensible.

### 2. Búsqueda con ranking nombre > categoría (en toda barra de búsqueda de Producto)

Al escribir un término en cualquier buscador de Producto:

1. Primero se muestran los productos cuyo **nombre** coincide (tolerando errores ortográficos — coincidencia difusa/fuzzy, no solo substring exacto).
2. Después, si el término también coincide con el **nombre de una categoría** (misma tolerancia a errores), se agregan los productos de esa categoría — **excluyendo** los que ya aparecieron en el paso 1.

Esto es independiente del setting de orden de arriba — aplica siempre que se use un buscador, sin importar si la vista de fondo está en modo Alfabético, Precio o Categoría.

## Alcance no resuelto a propósito

El usuario señaló explícitamente que el mecanismo de coincidencia difusa "se puede mejorar para ser más smart" pero no especificó el algoritmo exacto. Se deja como decisión de implementación (ej. distancia de Levenshtein con umbral bajo, o una librería de fuzzy-matching en Dart) — no bloquea el diseño de UX, que ya queda claro: nombre siempre antes que categoría, sin duplicados.

## Alternativas descartadas

- Guardar el orden de visualización como dato sincronizado (tabla o columna en SQLite) — es una preferencia de UI por dispositivo, no de negocio; no tiene sentido que se sincronice ni que dispare LWW.
- Búsqueda exclusivamente por substring exacto — no cumple el objetivo explícito de "evitar lentitud por error ortográfico".

## Consecuencias

- `ProductoNotifier` gana capacidades de lectura: listar con un orden dado, y buscar con el ranking de dos niveles descrito arriba — sigue siendo lectura sobre la misma entidad, no una entidad nueva ni lógica compartida con otras entidades (consistente con [0009](0009-cruds-independientes-por-entidad.md)).
- Nuevo `PreferenciasNotifier` (o similar) para el setting de orden — separado de `AuthNotifier`/`DeviceConfigNotifier` porque no es información sensible y no debería vivir en almacenamiento seguro.
- Ver `docs/pantallas/prototipos-ascii.md` para los bocetos actualizados de Ventana 1, 2, 3 y 5.
