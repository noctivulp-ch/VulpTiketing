# Backup e Importación de Datos

Ver también: [../arquitectura/seguridad](../arquitectura/seguridad.md) · [../../features/Data.feature](../../features/Data.feature) · [decisión 0017](../decisiones/0017-importar-datos-tiketdata-vs-tiketback.md)

Dos tipos de archivo con propósitos distintos — ver [decisión 0017](../decisiones/0017-importar-datos-tiketdata-vs-tiketback.md) para el razonamiento completo.

## `.tiketback` — backup completo (cifrado)

- Contenido: todo el estado del dispositivo (Producto, Categoria, Venta, LineaVenta históricas + configuración).
- Exportar: disponible para cualquier rol. Restaurar: solo Gerente.
- Esquema de encriptación: contraseña de exportación propia (distinta del login) → clave derivada con Argon2id/PBKDF2 → AES-256-GCM. Ver [seguridad](../arquitectura/seguridad.md) y [decisión 0006](../decisiones/0006-encriptacion-backup.md).
- Restaurar es **siempre un reemplazo completo** del estado local — no existe modo "fusionar" para este archivo (fusionar dos historiales de ventas no tiene sentido contable).

## `.tiketdata` — paquete de catálogo (sin cifrar)

- Contenido: **solo** Producto y Categoria — nunca Ventas. Pensado para compartirse (ej. un menú prearmado entre negocios), por eso no está cifrado.
- Formato: JSON, preservando los UUID originales de cada fila (reimportar el mismo paquete dos veces no crea duplicados).
- Exportar e importar: solo Gerente.
- Al importar, el usuario elige:
  - **Reemplazar** — descontinúa (soft-delete) todo lo local que no esté en el archivo, y aplica upsert de lo que sí viene.
  - **Fusionar** — aplica upsert solo de lo que viene en el archivo, sin tocar el resto del catálogo.
  - Ambos modos reutilizan el mismo mecanismo LWW de la sync entre dispositivos (0005) — no es un algoritmo de merge nuevo.
