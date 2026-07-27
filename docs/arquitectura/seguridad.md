# Seguridad

Ver también: [../funciones/roles-y-auth](../funciones/roles-y-auth.md) · [../funciones/backup](../funciones/backup.md)

## Modelo de amenaza

No se diseña contra un adversario interno (Gerente/Registradora son personal de confianza del mismo negocio) — ver [decisión 0002](../decisiones/0002-roles-funcionales-no-seguridad.md). El objetivo real es evitar que **terceros ajenos** accedan a los datos del negocio si el dispositivo cae en otras manos, o si el archivo de backup se pierde/comparte accidentalmente.

## Autenticación de la app

- Login local por rol, sin backend.
- Contraseña editable en configuración, por dispositivo (no sincronizada como credencial entre dispositivos).
- Rol + contraseña (hasheada con Argon2id) viven en almacenamiento seguro nativo del sistema operativo (ej. `flutter_secure_storage`), **no** en una tabla SQLite. Ver [decisión 0011](../decisiones/0011-credenciales-almacenamiento-nativo.md).

## Backup encriptado

Al exportar un `.sodabak`, el usuario define una contraseña de exportación (independiente de la de login). La clave se deriva con Argon2id (o PBKDF2 si Argon2id no es práctico en el stack Flutter elegido) y el bundle se encripta con AES-256-GCM. La clave nunca se persiste — solo existe en memoria durante la operación de exportar/restaurar. Si se olvida la contraseña, el backup es irrecuperable por diseño. Ver [decisión 0006](../decisiones/0006-encriptacion-backup.md).
