# 0009 — CRUDs independientes por entidad, ninguno se recicla

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

Al detallar el ciclo de vida de Producto y Venta quedó claro que son fundamentalmente distintos:

- **Producto**: Crear, Leer, Actualizar, Descontinuar (soft-delete vía `deleted_at`).
- **Venta**: Crear o Revertir — nunca editar, nunca borrar (ni hard ni soft-delete). Revertir es una transición de estado propia con motivo, no un borrado.
- **(Futuro) Insumo/MateriaPrima**: tendrá su propio ciclo de vida, tampoco reutilizará el de Producto ni el de Venta.

## Decisión

No construir una abstracción genérica de CRUD (ej. una interfaz `Repository<T>` con `create/read/update/delete` compartida) que todas las entidades deban implementar. Cada entidad tiene su propio conjunto de operaciones, modelado explícitamente según su ciclo de vida real.

## Alternativas descartadas

- Repositorio genérico con las 4 operaciones CRUD estándar para todas las entidades — descartado porque forzaría a Venta a tener una operación `update`/`delete` que no debe existir (o a implementarla como no-op/excepción, lo cual es peor que no tenerla).

## Consecuencias

- Cada entidad define su propia clase de casos de uso / repositorio, sin interfaz común forzada.
- Evita que alguien "por accidente" edite o borre una Venta usando un método genérico pensado para Producto.
