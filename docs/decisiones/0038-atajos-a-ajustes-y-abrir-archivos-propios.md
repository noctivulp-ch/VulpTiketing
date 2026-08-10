# 0038 — Atajos a los ajustes de Android, abrir los archivos propios, y Acerca de

**Estado:** Aceptada
**Fecha:** 2026-08-10

## Contexto

Tres cosas que aparecen al poner la app en manos de alguien, no al programarla.

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

**No había forma de saber qué versión corre un teléfono.** Con tres aparatos y
reinstalaciones a mano, "los dos tienen la misma app" era una suposición. Y la
app no llevaba firma de autoría: es a medida para un familiar, pero conviene
dejar la marca.

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
`pathPattern`, y cada patrón repetido con `.*` delante, porque `pathPattern` no
está anclado y sin las dos formas las rutas con subcarpetas no coinciden.

**Y en dos `intent-filter`, no en uno con los dos esquemas.** El `content://`
necesita `host="*"` para que el patrón se evalúe; un `file:///` tiene el host
**vacío**, y `host="*"` no casa con un host vacío. Medido en el aparato con
`cmd package query-activities`: con los dos esquemas juntos, el `content://`
enganchaba y el `file://` no. Separados, los dos sí — y un `.jpg` sigue sin
enganchar, que es la otra mitad de la comprobación.

El `content://` es el que manda un explorador de verdad; el `file://` lo usan
gestores viejos y el `am start` de adb.

**El archivo se copia al llegar, en código nativo.** Dos razones y las dos
obligan:

1. `dart:io` no puede leer un `content://` — no es un archivo del sistema de
   archivos, es un flujo que sirve otra app por el ContentResolver.
2. El permiso de lectura dura lo que dura el intent. Guardar la URI para leerla
   al confirmar el diálogo no funcionaría: ahí ya no se puede abrir.

Se copia a la caché con nombre único, así dos archivos que se llamen igual no se
pisan y el sistema puede limpiarlo cuando le haga falta espacio. Y **se borra al
terminar**, incluso si se canceló: es una copia, el original sigue donde estaba, y
un respaldo del negocio olvidado en la caché es una copia de los datos que nadie
sabe que existe.

**Una copia de cero bytes es un fallo, no un archivo vacío.** Pasa con un
`file:///sdcard` en Android 10 o superior: la app no puede leer el almacenamiento
compartido sin permiso, y `openInputStream` no lanza nada — la copia sale vacía y
la app se ofrecía a importar la nada. Medido en el aparato.

**El nombre real se pregunta al ContentResolver.** El `content://` no lleva
extensión, y la extensión es lo único que separa un catálogo de un respaldo
completo. Confundirlos sería importar productos donde se quería restaurar la base
—o pisar la base entera donde solo se quería la carta.

**Se atiende con la sesión abierta, no en el arranque.** El archivo espera: el
lado nativo lo guarda hasta que alguien lo recoge. Y se recoge una sola vez, no
en cada arranque.

**El lado nativo avisa; el ciclo de vida no basta.** Esperar el paso a `resumed`
funciona cuando la app venía de atrás, pero tocar un archivo con la app **ya en
primer plano** no produce ningún cambio de estado: el archivo quedaba esperando y
no pasaba nada. Medido en el aparato. `onNewIntent` manda un aviso por el mismo
canal en cuanto tiene algo.

**Siempre pregunta.** Tocar un archivo es un gesto barato y fácil de dar por
error; lo que hay detrás no lo es. Un catálogo ofrece Fusionar o Reemplazar; un
respaldo dice que reemplaza todo y pide la contraseña **del archivo** —no la de la
app, que es el error probable ahí—.

También se acepta `ACTION_SEND`: un respaldo suele llegar por WhatsApp o correo,
sin pasar por el explorador.

### Y una sección "Acerca de", con la firma del autor embebida

Nombre visible, versión y número de compilación, y al final "Hecho por NoctiVulp"
con el enlace del autor **embebido y sin decoración**.

- **El nombre visible no es el del paquete.** `pubspec.yaml` dice
  `vulp_tiketing` porque un nombre de paquete Dart no admite mayúsculas; lo que
  se muestra es `VulpTiketing`. Ya lo había pedido el dueño: "vulp_tiketing eso
  queda muy debug".
- **El número de compilación no es adorno.** Cuando algo no cuadra en un
  teléfono, lo primero que hay que saber es si corre el mismo código que los
  demás; dos aparatos con la misma versión y distinto build no lo hacen.
- **La versión se escribe a mano y una prueba la vigila.**
  `test/version_test.dart` lee `pubspec.yaml` y falla si no coinciden. Es el
  precio de no traer una dependencia nativa solo para leer un número, y es
  barato: una constante duplicada se queda vieja sin que nadie lo note, y una
  pantalla que miente sobre la versión es peor que no tenerla.
- **El enlace no se ve.** La app es a medida para un familiar y no cobra nada: el
  enlace es una marca de autoría —por si algún día alguien se la apropia—, no una
  invitación a pagar. Se conserva tal cual lo dio el dueño, con sus parámetros de
  seguimiento: recortarlos sería reescribir lo que pidió, y son los que le dicen
  de dónde llegó la visita.
- **Pero sí se anuncia a quien no ve la pantalla.** La etiqueta de accesibilidad
  dice que abre la página del autor. Un enlace invisible es una decisión de
  diseño para quien mira; con un lector de pantalla sería un elemento que hace
  algo inesperado al tocarlo, y eso no es discreción, es una trampa.
- **Si no hay navegador, el enlace se copia** al portapapeles. El toque tiene que
  servir para algo; un "no se pudo" a secas deja al usuario sin nada.
- **Dice con qué se escribió.** El dueño lo pidió con estas palabras: *"no quiero
  esconder ni mentir, mi fuerte es Java, de Dart y Flutter sé poco y el
  desarrollo completo fue un powered by en toda regla, ya que la idea y forma de
  la app fue guiada por mí y escrita / traducida de lenguaje natural a código"*.

  Así que la pantalla dice **las dos mitades**: "Producto, diseño y decisiones:
  NoctiVulp. Código escrito por Claude Code a partir de sus indicaciones." Un
  "powered by" a secas se leería como una herramienta de las que usa cualquiera;
  omitirlo sería atribuirse un trabajo a medias. La nota va **fuera** del área
  tocable: la firma lleva el enlace, esto es una nota al pie, y si entrara en el
  mismo toque abriría la página del autor — que no es lo que la nota dice que
  hace.
- **Sin `url_launcher`.** Abrir una dirección es un `Intent` de una línea por el
  canal que ya existía, y en Linux/Windows/macOS un `xdg-open`/`start`/`open` —
  que es lo que haría el plugin. Cada plugin nuevo arrastra avisos de Gradle y
  riesgo de compilación en tres plataformas.

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
