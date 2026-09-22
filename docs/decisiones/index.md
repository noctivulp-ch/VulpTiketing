# Decisiones — Índice

Volver a [../index](../index.md)

| # | Título | Estado |
|---|--------|--------|
| [0001](0001-lib-raw-vs-lib.md) | `lib_raw/` en vez de `lib/` para recursos crudos | Aceptada |
| [0002](0002-roles-funcionales-no-seguridad.md) | Roles como separación funcional, no de seguridad interna | Aceptada |
| [0003](0003-turnos-sin-corte-de-caja.md) | Turnos horarios fijos, sin corte de caja | Sustituida por la [0037](0037-corte-de-caja-y-jornada-en-dos-turnos.md) |
| [0004](0004-alcance-base-vs-futuro.md) | Impresión e inventario de insumos: pospuestos, no descartados | Aceptada |
| [0005](0005-borrados-en-sync.md) | Manejo de borrados en sync (tombstones) | Aceptada |
| [0006](0006-encriptacion-backup.md) | Esquema de encriptación del backup | Aceptada |
| [0007](0007-topologia-sync.md) | Topología de sincronización multi-dispositivo | Aceptada |
| [0008](0008-modelo-venta-multilinea-terminologia.md) | Modelo de venta multi-línea y terminología Producto vs Plato | Aceptada |
| [0009](0009-cruds-independientes-por-entidad.md) | CRUDs independientes por entidad, ninguno se recicla | Aceptada |
| [0010](0010-motivo-reversion-como-json.md) | Motivo de reversión de Venta como JSON en columna TEXT | Aceptada |
| [0011](0011-credenciales-almacenamiento-nativo.md) | Credenciales de dispositivo en almacenamiento seguro nativo, no SQLite | Aceptada |
| [0012](0012-precios-como-real.md) | Precios como REAL, no INTEGER en unidad mínima | Aceptada |
| [0013](0013-nota-por-linea-no-json-en-venta.md) | Nota descriptiva por línea en linea_venta, no JSON en venta | Aceptada |
| [0014](0014-riverpod-como-gestion-de-estado.md) | Riverpod como gestión de estado | Aceptada |
| [0015](0015-purgar-producto-borrado-fisico-condicional.md) | Purgar Producto: borrado físico condicional | Aceptada |
| [0016](0016-linea-libre-en-venta.md) | Línea libre en Venta (sin Producto de catálogo) | Aceptada |
| [0017](0017-importar-datos-tiketdata-vs-tiketback.md) | Importar datos: `.tiketdata` (catálogo) vs `.tiketback` (backup completo) | Aceptada |
| [0018](0018-orden-y-busqueda-de-producto.md) | Orden y búsqueda de Producto: agrupación por categoría + ranking nombre > categoría | Aceptada |
| [0019](0019-descomponer-servicios-responsabilidad-unica.md) | Descomponer servicios grandes en clases de responsabilidad única | Aceptada |
| [0020](0020-iconografia-vectorial-propia.md) | Iconografía vectorial propia: Python + SVG + tinte en runtime | Aceptada |
| [0021](0021-paquete-mdns-bonsoir.md) | Paquete de mDNS para sync: `bonsoir` | Aceptada |
| [0022](0022-protocolo-transporte-sync-shelf-puerto-dinamico.md) | Protocolo de transporte de sync: HTTP embebido (`shelf`) + puerto dinámico | Aceptada |
| [0023](0023-refinamiento-bento-post-implementacion.md) | Refinamiento bento: evitar overlays, figuras conectadas con matices, cascada invertida, tema claro/oscuro | Aceptada |
| [0024](0024-harness-flutter-driver-mcp.md) | Harness de `flutter_driver` + MCP para control remoto de la app | Aceptada |
| [0025](0025-archivado-anual-rodante.md) | Libros de ventas rodantes en archivos SQLite adjuntables | Aceptada |
| [0026](0026-cuadricula-bento-y-breakpoints.md) | Retícula bento de 6 columnas y tres tamaños de pantalla | Aceptada |
| [0027](0027-arranque-optimista-de-sesion.md) | Arranque optimista de sesión: el rol se duplica como pista en preferencias | Aceptada |
| [0028](0028-acciones-de-dialogo-al-costado-acostado.md) | Las acciones de un diálogo van al costado cuando la pantalla está acostada | Aceptada |
| [0029](0029-exportar-a-descargas-por-mediastore.md) | Exportar a Descargas por MediaStore, con código nativo | Aceptada |
| [0030](0030-gestos-un-dedo-navega-varios-actuan.md) | Gestos: un dedo navega, dos o tres actúan | Aceptada |
| [0031](0031-paridad-de-escritorio-teclado-y-touchpad.md) | Paridad de escritorio: teclado y touchpad | Aceptada |
| [0032](0032-metodo-de-pago-en-la-venta.md) | Método de pago en la venta, con referencia opcional anotada después | Aceptada |
| [0033](0033-banco-de-imagenes.md) | Banco de imágenes: figuras de fábrica y fotos propias | Sustituida en parte por la [0034](0034-iconos-por-categoria-y-fotos-apagables.md) |
| [0034](0034-iconos-por-categoria-y-fotos-apagables.md) | La cara de un producto: iconos por categoría, y fotos apagables por ventana | Aceptada |
| [0035](0035-token-para-el-harness-del-mcp.md) | Token aleatorio para el harness del MCP | Aceptada |
| [0036](0036-sync-par-a-par-con-ronda-periodica.md) | Sync par a par, con ronda periódica | Aceptada |
| [0037](0037-corte-de-caja-y-jornada-en-dos-turnos.md) | Corte de caja, y la jornada en dos turnos | Aceptada |
| [0038](0038-atajos-a-ajustes-y-abrir-archivos-propios.md) | Atajos a los ajustes de Android, abrir los archivos propios, y Acerca de | Aceptada |
| [0039](0039-variantes-de-producto-como-json.md) | Variantes de un producto como JSON en `producto`, y su nombre en la línea de venta | Aceptada |
| [0040](0040-costeo-de-recetas-como-modulo.md) | Costeo de recetas como módulo informativo, con "aplicar precio" opcional | Aceptada |
