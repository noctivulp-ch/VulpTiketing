# 0029 — Exportar a Descargas por MediaStore, con código nativo

**Estado:** Aceptada
**Fecha:** 2026-08-02

## Contexto

Lo que la app exportaba —backups, catálogos, reportes— caía en
`Android/data/<paquete>/files/VulpTiketing`. Esa carpeta se eligió porque no
pide ningún permiso y se ve al conectar el teléfono por USB
(ver `carpeta_exportacion.dart`).

El problema es el "por USB": para quien atiende la soda, un backup que solo
existe conectando el teléfono a una computadora no es un backup. No aparece en
el gestor de archivos, no se puede mandar por WhatsApp, no se puede subir a
ningún lado. La función estaba, y el archivo era inalcanzable.

Escribir en `/storage/emulated/0/Download` desde Dart **no se puede** desde
Android 10: el almacenamiento es *scoped* y `dart:io` recibe
`Permission denied (errno 13)` aunque la carpeta exista y se vea en cualquier
explorador. Comprobado en el aparato de pruebas (MAR-LX3A, Android 10), no
deducido de la documentación.

## Decisión

Después de escribir el archivo en la carpeta privada, la app lo **publica** en
`Descargas/VulpTiketing` a través de **MediaStore**, con un `MethodChannel`
propio (`vulp/almacen_publico`) implementado en `MainActivity.kt`.

- Android 10+ → `MediaStore.Downloads` con `RELATIVE_PATH` y `IS_PENDING`, que
  es la única vía **sin pedirle permisos al usuario**.
- Android 9 y anteriores → escritura directa, que ahí sí funciona.
- Fuera de Android → no hay nada que publicar; la carpeta elegible sigue
  valiendo, porque en escritorio `dart:io` escribe donde le digan.

El archivo de la carpeta privada se borra tras publicar: era el paso intermedio.

`IS_PENDING` se baja al terminar de copiar, así que nadie ve un backup a medio
escribir.

Los formatos propios (`.tiketback`, `.tiketdata`) se publican como
`application/octet-stream` **aunque `.tiketdata` sea JSON por dentro**:
MediaStore renombra el archivo para que la extensión case con el tipo, y con
`application/json` el catálogo salía como `catalogo.tiketdata.json`. La
extensión es parte del formato — es por lo que el selector de importar lo
reconoce. PDF y CSV sí llevan su tipo real, que es lo que hace que tocarlos
desde Descargas ofrezca con qué abrirlos.

## Alternativas descartadas

- **`MANAGE_EXTERNAL_STORAGE`**: acceso a todo el almacenamiento para escribir
  cinco archivos propios. Desproporcionado, y Play lo rechaza sin una
  justificación que esta app no tiene.
- **`WRITE_EXTERNAL_STORAGE` + `requestLegacyExternalStorage`**: funcionaría en
  el teléfono de pruebas (Android 10) y no en el del negocio, que es más nuevo.
  Arreglar el aparato equivocado.
- **SAF con carpeta elegida una vez**: es la vía "correcta" de Android, pero
  devuelve un `content://` que `dart:io` no sabe abrir, así que obligaría a
  reescribir el camino de escritura de los tres formatos —incluido el escritor
  por trozos del backup, que existe precisamente para no cargar el archivo
  entero en memoria—. Mucho más trabajo y más riesgo por una elección que nadie
  pidió: quien exporta quiere el archivo en Descargas.
- **Un plugin de pub para MediaStore**: una dependencia más, con su ciclo de
  vida, para 60 líneas de Kotlin que no van a cambiar.

## Consecuencias

- Se escribe dos veces (privado → Descargas). Para el backup de 332 KB de la
  base de pruebas es imperceptible; si algún día pesara cientos de MB habría que
  escribir directo al `OutputStream` de MediaStore.
- Hay código nativo Android que mantener. Es el primero del proyecto.
- Publicar puede fallar sin que exportar falle: el archivo ya está escrito, y la
  app devuelve la ruta privada en vez de decir "no se pudo", que sería mentira.
- El arnés gana `exportar_catalogo` y `exportar_backup`, que ejercitan el camino
  real —el del botón— en vez de escribir a una ruta dada saltándose justamente
  la parte que hay que comprobar.
