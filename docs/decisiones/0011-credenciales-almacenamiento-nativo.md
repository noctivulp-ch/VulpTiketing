# 0011 — Credenciales de dispositivo en almacenamiento seguro nativo, no en SQLite

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

Al diseñar el esquema exacto surgió la duda de si la contraseña local del dispositivo (0002) debía vivir en una tabla SQLite (`usuario`) o en otro mecanismo. Un archivo SQLite es trivial de abrir con cualquier visor de bases de datos, incluso hasheada la contraseña ahí sigue siendo más expuesta de lo necesario para algo que es configuración de un solo dispositivo, no una entidad de negocio.

## Decisión

Eliminar la tabla `usuario`. El rol del dispositivo (`gerente`/`registradora`) y el hash de la contraseña local viven en almacenamiento seguro nativo del sistema operativo (ej. `flutter_secure_storage`, que usa Keychain en iOS/macOS y Keystore en Android; en Windows/Linux usa el almacén de credenciales del SO). La contraseña se hashea con Argon2id antes de guardarse (misma dependencia ya elegida para el backup en [0006](0006-encriptacion-backup.md)).

## Alternativas descartadas

- Tabla `usuario` en SQLite con contraseña hasheada — descartada porque mezclar config de dispositivo con el esquema de negocio no aporta nada (esta info nunca se sincroniza ni se reporta) y expone innecesariamente el hash en un archivo fácil de copiar.

## Consecuencias

- El `device_id` para el esquema de sync (0007) también vivirá en este mismo almacenamiento, junto al rol y la contraseña — ver `docs/arquitectura/esquema-db.md`.
- El esquema SQLite queda compuesto únicamente por entidades de negocio (Producto, Categoria, Venta, LineaVenta, y a futuro Insumo).
