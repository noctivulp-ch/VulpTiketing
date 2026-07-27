# Backup

Ver también: [../arquitectura/seguridad](../arquitectura/seguridad.md) · [../../features/Data.feature](../../features/Data.feature)

## Qué hace

Exporta un bundle de la base de datos SQLite + configuración de la app, encriptado, como archivo `.sodabak` al sistema de archivos local. Es una operación manual disponible para cualquier rol.

## Esquema de encriptación

Contraseña de exportación propia (distinta del login) → clave derivada con Argon2id/PBKDF2 → AES-256-GCM. Ver [seguridad](../arquitectura/seguridad.md) y [decisión 0006](../decisiones/0006-encriptacion-backup.md).
