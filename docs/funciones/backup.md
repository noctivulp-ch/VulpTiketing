# Backup e Importación de Datos

Ver también: [../arquitectura/seguridad](../arquitectura/seguridad.md) · [../../features/Data.feature](../../features/Data.feature) · [decisión 0017](../decisiones/0017-importar-datos-tiketdata-vs-tiketback.md)

Dos tipos de archivo con propósitos distintos — ver [decisión 0017](../decisiones/0017-importar-datos-tiketdata-vs-tiketback.md) para el razonamiento completo.

## `.tiketback` — backup completo (cifrado)

**Implementado** (`TiketbackService`/`TiketbackNotifier`, con prueba de round-trip en `test/tiketback_service_test.dart`).

- Contenido: la base de datos SQLite completa (Producto, Categoria, Venta, LineaVenta históricas) + preferencias de UI no sensibles (orden de productos, acento). **No incluye** rol, contraseña ni `device_id` — esos son de almacenamiento seguro nativo, específicos de cada dispositivo, y se quedan ahí a propósito aunque el archivo ya vaya cifrado (defensa en profundidad). Restaurar un backup en un dispositivo nuevo deja su rol/contraseña como estaban en ese dispositivo (de fábrica, o lo que se haya configurado ahí).
- Exportar: disponible para cualquier rol. Restaurar: **solo Gerente** (aplicado en `ConfiguracionScreen`).
- Esquema de encriptación: contraseña de exportación propia (distinta del login) → clave derivada con Argon2id → AES-256-GCM (`package:cryptography`). Ver [seguridad](../arquitectura/seguridad.md) y [decisión 0006](../decisiones/0006-encriptacion-backup.md).
- Restaurar es **siempre un reemplazo completo** del estado local — no existe modo "fusionar" para este archivo (fusionar dos historiales de ventas no tiene sentido contable). La UI pide confirmación explícita antes de pedir la contraseña, por ser irreversible.
- **Dónde queda el archivo**: en **Descargas › VulpTiketing**, sin selector — se exporta con un toque y el aviso dice el nombre. Antes caía en `Android/data/<paquete>/`, visible solo conectando el teléfono a una computadora: un backup así no es un backup. Va por MediaStore con código nativo, que es la única vía sin pedir permisos desde Android 10 ([decisión 0029](../decisiones/0029-exportar-a-descargas-por-mediastore.md)).
- **Para IMPORTAR** sí se abre el selector nativo (`file_picker`): ahí el usuario tiene que decir qué archivo, y eso no se puede adivinar.

## `.tiketdata` — paquete de catálogo (sin cifrar)

**Implementado** (`TiketdataService`/`TiketdataNotifier`, con pruebas en `test/tiketdata_service_test.dart` cubriendo fusionar, reemplazar, y que LWW respeta un cambio local más reciente).

- Contenido: **solo** Producto y Categoria **activos** (no se exportan descontinuados) — nunca Ventas. Pensado para compartirse (ej. un menú prearmado entre negocios), por eso no está cifrado.
- Formato: JSON, preservando los UUID originales de cada fila (reimportar el mismo paquete dos veces no crea duplicados).
- Exportar e importar: solo Gerente (aplicado en `ConfiguracionScreen`).
- Al importar, el usuario elige:
  - **Reemplazar** — descontinúa (soft-delete, nunca borrado físico) todo lo local activo que no esté en el archivo, y aplica upsert de lo que sí viene.
  - **Fusionar** — aplica upsert solo de lo que viene en el archivo, sin tocar el resto del catálogo. La UI pide confirmación explícita solo para "Reemplazar" (afecta datos existentes).
  - Ambos modos reutilizan `RowSyncEngine.resolver()` fila por fila — el mismo mecanismo LWW de la sync entre dispositivos (0005), no es un algoritmo de merge nuevo.
- Exportar deja el archivo en **Descargas › VulpTiketing**, igual que el backup. Importar abre el selector nativo (`file_picker`), también igual.
- El catálogo se publica como `application/octet-stream` **aunque sea JSON por dentro**: MediaStore renombra el archivo para que la extensión case con el tipo, y con `application/json` salía `catalogo.tiketdata.json` — y la extensión es lo que hace que el selector de importar lo reconozca.

## Abrir un archivo tocándolo en el explorador

Un `.tiketdata` o un `.tiketback` se abren en la app al tocarlos en Archivos, o al recibirlos compartidos desde WhatsApp o el correo ([decisión 0038](../decisiones/0038-atajos-a-ajustes-y-abrir-archivos-propios.md)).

**Siempre pregunta antes de aplicar nada.** Tocar un archivo es un gesto fácil de dar por error y lo que hay detrás no lo es:

| Archivo | Qué ofrece |
|---|---|
| `.tiketdata` | Fusionar (agrega y actualiza) o Reemplazar (deja el catálogo igual al del archivo) |
| `.tiketback` | Avisa de que reemplaza TODO y pide la contraseña **del archivo** — la que se eligió al exportarlo, no la de la app |

La asociación puede quedar tomada por otra app. Se rehace desde **Configuración › Sistema › Abrir archivos de la app**.

## Configuración › Sistema

Atajos a los ajustes de Android que la app necesita. No conceden nada —una app no puede darse permisos a sí misma—: abren la pantalla donde se marca.

El que importa de verdad es **la optimización de batería**: sin la exención, el sistema congela la app al apagarse la pantalla y la sincronización se corta sin que nada avise. En marcas como Huawei o Xiaomi hay además una lista propia de apps protegidas, fuera de estos ajustes; el panel lo dice, con el fabricante del aparato.
