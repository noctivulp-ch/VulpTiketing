# 0035 — Token aleatorio para el harness del MCP

**Estado:** Aceptada
**Fecha:** 2026-08-03

Cierra el hueco que dejó abierto la [0024](0024-harness-flutter-driver-mcp.md),
que construyó el harness sin ninguna autenticación.

## Contexto

El dueño preguntó si el MCP estaba abierto y propuso protegerlo con un token
derivado de la contraseña de la app.

**Lo primero: no estaba abierto donde importa.** Se comprobó antes de decidir
nada, y sobre el APK instalado en el aparato, no sobre el código:

- `flutter_driver` está en `dev_dependencies`.
- `enableFlutterDriverExtension` vive en `test_driver/app.dart`, un entrypoint
  aparte; el APK usa `lib/main.dart`.
- Se buscaron las cadenas de los comandos del harness (`seed_producto`,
  `vulp_directo`, `seed_venta`) dentro del APK: **no aparece ninguna**.
- El bridge escucha en `InternetAddress.loopbackIPv4`, no en la red.

**Pero la intuición apuntaba a dos cosas reales:**

1. El bridge del 8765 no pedía nada. Cualquier proceso de la misma computadora
   podía manejar la caja con un `curl`.
2. Un APK **debug** expone el Dart VM Service por su cuenta, sin flutter_driver
   de por medio. El aparato tiene uno instalado ahora mismo.

## Decisión

### El token es aleatorio, no derivado de la contraseña

Es el punto en el que la propuesta original se descartó, y conviene dejar por
qué escrito: la contraseña de la app son **cuatro dígitos** —diez mil
posibilidades, y el algoritmo estaría a la vista en este repo—, así que un token
derivado se rompe probándolas todas. Y en la otra dirección es peor: un token
filtrado permitiría recuperar la contraseña por fuerza bruta. Se acabaría
debilitando la contraseña para proteger el harness.

32 bytes de `Random.secure()`, en base64 URL-safe porque el token viaja como
argumento de línea de comandos y como cabecera HTTP.

### La contraseña protege, pero en otro sitio

Hace falta para **ver** el token, no para calcularlo. Así cubre lo que de verdad
tiene que cubrir —que no quede a la vista de quien agarre el teléfono
desbloqueado— sin quedar codificada dentro de él.

Y como no lo determina, **rotarlo es gratis**: si se le dio a una herramienta y
hay que cortarle el acceso, se genera otro sin tocar la contraseña. Revocar deja
el aparato como estaba de fábrica: sin token, nada de fuera entra.

### Empieza sin token

El estado inicial es cerrado. Mientras nadie pida la llave no hay llave que
robar, y el harness no puede conectarse de ninguna manera.

### Se comprueba en cada comando, no una vez al arrancar

Leer el llavero es asíncrono y `enableFlutterDriverExtension` tiene que ser la
primera llamada de `main()` —instala su propio binding y cualquier cosa antes se
lo impide—, así que no hay dónde esperar. Comprobar por mensaje sale más barato
de razonar y además hace que **revocar corte el acceso en el acto**, con la app
abierta y sin reiniciar nada.

### El bridge no arranca sin token

Lo recibe por `--token`, lo confirma contra la app con un comando `ping` **antes
de abrir el puerto** —así un token equivocado falla ahí, con un mensaje claro, y
no más tarde disfrazado de "el comando no hizo nada"— y exige la cabecera
`X-Vulp-Token` en cada petición.

## Hasta dónde llega, y hasta dónde no

Conviene decirlo sin adornos, porque un lector futuro podría confiar de más:

- **Cerrado:** los comandos directos, que son los que tocan datos —sembrar,
  exportar, borrar—. Los valida la app contra su propio token; no hay forma de
  saltárselo.
- **Cerrado:** el acceso desde otro proceso de la misma computadora, por la
  cabecera del bridge.
- **Cerrado:** el acceso desde la red, por el bind a loopback.
- **Abierto todavía:** alguien con acceso al VM service del aparato puede
  saltarse el bridge y hablar con la extensión estándar de flutter_driver —
  tocar la pantalla, leer texto—. No puede tocar la base, pero puede mover la
  app. Llegar ahí exige acceso físico con depuración habilitada y un build
  debug, que es el mismo nivel de acceso que ya permite instalar otro APK.

## Addendum (2026-08-09) — token fijo en los builds de desarrollo

El token aleatorio resolvió la seguridad y creó una fricción real: la app se
reinstala decenas de veces al día mientras se desarrolla, y **cada instalación
empieza sin token**. O sea que cada vuelta pedía abrir Configuración, escribir
la contraseña, generar, copiar y pasárselo al bridge.

Los builds de **debug y profile** aceptan además un token fijo,
`vulp-dev-no-usar-en-produccion`, escrito en el repositorio. No es un secreto y
no pretende serlo: toda su seguridad está en que la rama viva detrás de
`kReleaseMode`, que es una constante de compilación — en release el `if` se
elimina entero y **la cadena ni siquiera llega al binario**. Comprobado sobre el
APK real con `scripts/verificar-release.sh`.

Dos cosas lo acompañan, y son la parte que importa:

- **El panel lo grita.** Si el build acepta el token fijo, Configuración →
  Acceso muestra un aviso en rojo, imposible de cerrar, diciendo que hay que
  reinstalar con `flutter build apk --release` antes de dejar el aparato en la
  soda. Un build de pruebas no puede parecerse a uno normal.
- **`scripts/verificar-release.sh`** revisa un APK terminado y falla si
  encuentra el token, la extensión de driver o los comandos del harness. Se
  corre antes de entregar un aparato. Está probado en las dos direcciones: pasa
  con el release y falla con el debug — un verificador que solo se ha visto
  aprobar no sirve de nada.

## La otra mitad: que la puerta no exista

El token protege si alguien llega a la puerta. Más barato y más efectivo es que
la puerta no se construya, y eso hoy se cumple **por convención** — la clase de
cosa que se rompe el día que alguien agregue un import "solo para probar algo".

`test/harness_fuera_de_produccion_test.dart` lo fija: `flutter_driver` en
`dev_dependencies`, `lib/` sin un solo import del harness, `main.dart` sin la
extensión, los comandos verificando el token, y el bridge atado a loopback.

## Alternativas descartadas

**Derivar el token de la contraseña**, la propuesta original. Descartada por lo
razonado arriba: rompible por fuerza bruta y, filtrado, delata la contraseña.

**Pedir el token una sola vez al arrancar la app instrumentada.** Más simple,
pero imposible de hacer bien: la lectura del llavero es asíncrona y la extensión
tiene que registrarse antes de cualquier `await`. Y revocar no surtiría efecto
hasta reiniciar.

**No poner nada, dado que en release no hay superficie.** Es cierto que el APK
de la soda no lo expone, pero deja el bridge de desarrollo abierto a cualquier
proceso local, y depende de que nadie compile nunca el entrypoint instrumentado
para el aparato. Dos supuestos que no cuesta nada dejar de necesitar.
