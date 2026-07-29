# 0006 — Esquema de encriptación del backup `.tiketback`

**Fecha:** 2026-07-26
**Estado:** Aceptada — opción A (contraseña de exportación + AES-256-GCM)

## Contexto

Data.feature pide que el bundle de SQLite + configuración se encripte antes de exportarse como `.tiketback`, sin especificar algoritmo ni de dónde sale la clave.

## Opciones

**A — Contraseña de exportación + AES-256-GCM (recomendada)**
Al exportar, el usuario define una contraseña (independiente de la contraseña de login). Se deriva una clave con Argon2id (o PBKDF2 si Argon2id no está disponible fácil en Flutter) y se encripta el bundle con AES-256-GCM. Para restaurar, se pide la misma contraseña.
- Ventaja: estándar de la industria, librerías maduras en el ecosistema Dart/Flutter (`cryptography` package), la clave nunca se guarda en ningún lado — solo existe en la memoria del usuario.
- Desventaja: si el usuario olvida la contraseña de backup, el backup es irrecuperable (comportamiento esperado de un buen cifrado, no un bug).

**B — Reusar la contraseña de login del dispositivo**
Igual que A pero sin pedir una contraseña nueva — deriva la clave de la contraseña de login del Gerente.
- Ventaja: un paso menos para el usuario.
- Desventaja: acopla la seguridad del backup a la del login; si cambia la contraseña de login, los backups viejos quedan con una clave "huérfana" difícil de re-derivar.

**C — Clave fija embebida en la app**
- Descartada: cualquiera con acceso al binario de la app puede extraer la clave y desencriptar cualquier backup — no cumple el objetivo de "evitar que terceros accedan a los datos" (ver [decisión 0002](0002-roles-funcionales-no-seguridad.md)).

## Recomendación

A. Es el único que da protección real si el archivo `.tiketback` se pierde o se comparte por error, que es justamente el escenario que esta feature busca cubrir.

## Nota posterior (2026-07-27)

Archivo renombrado de `.sodabak` a `.tiketback` — ver [decisión 0017](0017-importar-datos-tiketdata-vs-tiketback.md), que además introduce `.tiketdata` (paquete de catálogo, sin cifrar, con propósito distinto) y define cómo se importa cada uno.

## Nota posterior (2026-07-28) — qué cuentan como "settings" al implementar

Data.feature dice "bundle the SQLite database and settings" sin precisar qué es "settings". Al implementar `TiketbackService` se decidió: **sí** incluye las preferencias de UI no sensibles (orden de productos, acento — `PreferenciasNotifier`); **no** incluye rol, contraseña ni `device_id`, porque esos viven en almacenamiento seguro nativo ([0011](0011-credenciales-almacenamiento-nativo.md)), son específicos de cada dispositivo físico, y sacarlos de ahí para meterlos en un archivo exportable sería exponerlos innecesariamente aunque el archivo vaya cifrado (defensa en profundidad: minimizar qué sale del storage seguro, no depender solo de que el cifrado del backup nunca falle). Consecuencia práctica: restaurar un `.tiketback` en un dispositivo nuevo no cambia el rol/contraseña de ese dispositivo — sigue siendo el que ya tenía (de fábrica, o configurado ahí).
