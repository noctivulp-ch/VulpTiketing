# Roles y Autenticación

Ver también: [../arquitectura/seguridad](../arquitectura/seguridad.md) · [../../features/Authentication.feature](../../features/Authentication.feature)

## Propósito real de la autenticación

La separación en dos roles (**Gerente**, **Registradora**) es **funcional/de interfaz**, no un control de seguridad estricto entre usuarios internos — ambos roles son personal de confianza del mismo negocio. El propósito real de pedir credenciales es evitar que **terceros ajenos al negocio** accedan a los datos si el dispositivo cae en otras manos.

Esto significa: el diseño de permisos por rol prioriza que cada quien vea la UI relevante a su trabajo (POS simple para Registradora, control completo para Gerente), no modelar un adversario interno.

## Credenciales

- No hay backend de autenticación — no aplica registro remoto de usuarios.
- Las credenciales están pensadas originalmente como hardcodeadas a compilación, pero eso impediría cambiar una contraseña sin recompilar.
- **Decisión pendiente de confirmar en código**: agregar una opción en configuración para cambiar la contraseña de la app **en el dispositivo específico** (almacenada localmente, no sincronizada como credencial — ver [seguridad](../arquitectura/seguridad.md)).

## Multi-dispositivo

El esquema no asume un único Gerente ni una única Registradora: puede haber una Gerente principal y varias Registradoras (cada una en su propio dispositivo). Ver [sincronización](../arquitectura/sincronizacion.md) para cómo eso afecta el diseño de sync.
