# 0038 — Atajos a los ajustes de Android, y abrir los archivos propios

**Estado:** Aceptada
**Fecha:** 2026-08-10

## Contexto

Dos huecos que aparecen al poner la app en manos de alguien, no al programarla.

**El sistema mata la sincronización y nada lo dice.** Sin la exención de
optimización de batería, Android congela la app cuando se apaga la pantalla: la
caja deja de compartir ventas y en la app no cambia nada — el interruptor sigue
encendido y el panel sigue diciendo que busca dispositivos. El ajuste está a
cinco toques de profundidad y con un nombre distinto en cada marca
("Optimización de batería", "Inicio automático", "Aplicaciones protegidas").

**Los archivos propios no se abren al tocarlos.** Un `.tiketdata` o un
`.tiketback` en el explorador no hacía nada: había que abrir la app, entrar en
Configuración y buscarlo con el selector. Para un respaldo que llega por WhatsApp
eso son seis pasos y saber dónde lo dejó la descarga.

## Decisión

### Una sección "Sistema" en Configuración, con atajos

Cuatro, cada uno abriendo la pantalla de Android donde se marca:

| Atajo | Para qué |
|---|---|
| Optimización de batería | Que el sistema no congele la sincronización |
| Permisos de la app | La cámara, para la foto de un producto |
| Uso en segundo plano | Hablar con las otras cajas estando atrás |
| Abrir archivos de la app | La asociación de `.tiketdata` y `.tiketback` |

**Son atajos, no permisos.** Una app no puede concederse nada a sí misma; lo
único que se hace es dejar al usuario en la pantalla correcta. Que es casi todo
el problema.

Decisiones dentro de esto:

- **Para los dos roles**, no solo el Gerente. Quien atiende la caja es quien va
  a tener el teléfono en la mano cuando el sistema le corte la sincronización, y
  no puede depender de que venga alguien más a marcar una casilla.
- **Cada atajo dice si pudo abrir algo.** Ninguna de estas pantallas existe en
  todas las versiones ni en todas las marcas —hay fabricantes que se las quitan—
  y un `Intent` que nadie atiende lanza excepción. Se avisa en pantalla en vez de
  dejar la app muerta al toque.
- **Con caídas en cascada.** La batería intenta primero el diálogo directo
  (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), que es un sí o no y se acaba;
  si la ROM lo bloquea, cae a la lista del sistema. "Abrir por defecto" usa la
  pantalla dedicada desde Android 12 y antes cae a los detalles de la app.
- **Solo la batería se puede consultar**, así que solo esa lleva marca de estado.
  Un tilde que no sabe lo que dice es peor que ninguno.
- **Se dice el fabricante y la versión.** En un Huawei o un Xiaomi la exención de
  Android no basta: hay una lista propia aparte. Escribirlo en la pantalla evita
  el diagnóstico de "la sincronización no funciona" cuando lo que pasa es que la
  ROM la está matando.
- **Se relee al volver a la app.** Quien acaba de conceder la exención vuelve a
  la pantalla, y si siguiera diciendo que falta lo razonable es concluir que no
  funcionó.

En Linux y Windows la sección se muestra vacía con una línea explicándolo, en vez
de ofrecer atajos muertos.

### Los archivos propios se abren tocándolos

**Filtro por extensión, no por tipo MIME.** `.tiketdata` y `.tiketback` son
nuestras: el sistema no las conoce y las sirve como `application/octet-stream` o
sin tipo. Un filtro por MIME o no engancha nada o engancha todos los binarios del
teléfono. De ahí la receta fea pero estándar: `mimeType="*/*"` junto a
`pathPattern`, con `host="*"` —obligatorio para que el patrón se evalúe— y cada
patrón repetido con `.*` delante, porque `pathPattern` no está anclado y sin las
dos formas las rutas con subcarpetas no coinciden.

**El archivo se copia al llegar, en código nativo.** Dos razones y las dos
obligan:

1. `dart:io` no puede leer un `content://` — no es un archivo del sistema de
   archivos, es un flujo que sirve otra app por el ContentResolver.
2. El permiso de lectura dura lo que dura el intent. Guardar la URI para leerla
   al confirmar el diálogo no funcionaría: ahí ya no se puede abrir.

Se copia a la caché con nombre único, así dos archivos que se llamen igual no se
pisan y el sistema puede limpiarlo cuando le haga falta espacio.

**El nombre real se pregunta al ContentResolver.** El `content://` no lleva
extensión, y la extensión es lo único que separa un catálogo de un respaldo
completo. Confundirlos sería importar productos donde se quería restaurar la base
—o pisar la base entera donde solo se quería la carta.

**Se atiende con la sesión abierta, no en el arranque.** El archivo espera: el
lado nativo lo guarda hasta que alguien lo recoge. Y se recoge una sola vez, no
en cada arranque.

**Siempre pregunta.** Tocar un archivo es un gesto barato y fácil de dar por
error; lo que hay detrás no lo es. Un catálogo ofrece Fusionar o Reemplazar; un
respaldo dice que reemplaza todo y pide la contraseña **del archivo** —no la de la
app, que es el error probable ahí—.

También se acepta `ACTION_SEND`: un respaldo suele llegar por WhatsApp o correo,
sin pasar por el explorador.

## Consecuencias

- `MainActivity` gana `onNewIntent`: con `launchMode="singleTop"`, tocar un
  archivo con la app abierta no crea actividad nueva. Sin eso, el archivo se
  perdía y solo se traía la app al frente.
- `importarCatalogo` y `restaurar` aceptan una ruta ya elegida. No es un CRUD
  nuevo: es el mismo camino sin el selector, porque volver a preguntar por un
  archivo que el usuario acaba de tocar es pedirle que lo busque otra vez.

## Lo que queda fuera

- **No se puede saber si el segundo plano está permitido.** Android no lo expone;
  el atajo abre la pantalla y ya.
- **La lista de apps protegidas del fabricante no se puede abrir.** Cada marca la
  esconde en un sitio distinto y sin API. Se avisa por texto.
- **Sin filtro por MIME propio registrado.** Registrar un tipo MIME de verdad
  exigiría acuerdos que no aportan nada acá.
