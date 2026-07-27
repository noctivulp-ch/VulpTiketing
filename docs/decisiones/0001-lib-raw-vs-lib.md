# 0001 — `lib_raw/` en vez de `lib/` para recursos crudos

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

La convención de AppCreator (`CLAUDE.md` del workspace) usa `lib/` como carpeta gitignored para recursos externos en crudo. En Flutter, `lib/` es el directorio de código fuente Dart principal — se commitea siempre y el tooling (`flutter analyze`, `pub`, IDEs) lo asume así.

## Decisión

Usar `lib_raw/` para recursos externos crudos en este proyecto. `lib/` queda libre para el código fuente Flutter estándar.

## Alternativas descartadas

- Mover el código Dart a otro directorio (ej. `src/`) para liberar `lib/` — rompe la convención estándar de Flutter y confunde al tooling.

## Consecuencias

Cualquier referencia futura a "lib/" en la documentación de AppCreator debe leerse como `lib_raw/` específicamente en VulpTiketing.
