# Roles y Autenticación

Ver también: [../arquitectura/seguridad](../arquitectura/seguridad.md) · [../../features/Authentication.feature](../../features/Authentication.feature)

## Propósito real de la autenticación

La separación en dos roles (**Gerente**, **Registradora**) es **funcional/de interfaz**, no un control de seguridad estricto entre usuarios internos — ambos roles son personal de confianza del mismo negocio. El propósito real de pedir credenciales es evitar que **terceros ajenos al negocio** accedan a los datos si el dispositivo cae en otras manos.

Esto significa: el diseño de permisos por rol prioriza que cada quien vea la UI relevante a su trabajo (POS simple para Registradora, control completo para Gerente), no modelar un adversario interno.

## Credenciales

- No hay backend de autenticación — no aplica registro remoto de usuarios.
- Cada dispositivo se configura con un rol y una contraseña local de app, cambiable después desde configuración — no hardcodeada a compilación.
- La contraseña (hasheada con Argon2id) y el rol viven en almacenamiento seguro nativo del sistema operativo (ej. `flutter_secure_storage`), **no** en una tabla SQLite ni sincronizada entre dispositivos. Ver [decisión 0011](../decisiones/0011-credenciales-almacenamiento-nativo.md) y [esquema-db](../arquitectura/esquema-db.md).

## Multi-dispositivo

El esquema no asume un único Gerente ni una única Registradora: puede haber una Gerente principal y varias Registradoras (cada una en su propio dispositivo). Ver [sincronización](../arquitectura/sincronizacion.md) para cómo eso afecta el diseño de sync.
