# 0024 — Harness de `flutter_driver` + MCP para control remoto de la app

## Estado

Aceptada.

## Contexto

Las sesiones anteriores probaban cambios de UI simulando teclado/mouse a
ciegas contra la ventana real (`wtype`/`ydotool` + `grim` para ver el
resultado). Es frágil: no hay confirmación de que el evento llegó al widget
correcto, `ydotool` con coordenadas absolutas dio resultados no deseados
varias veces, y no hay forma de leer el estado interno de la app (¿se
actualizó el provider?, ¿qué texto tiene este campo ahora?) — solo se puede
mirar la pantalla.

Se evaluaron dos opciones:

1. Un MCP básico que hablara directo con SQLite (leer/escribir filas sin
   pasar por la app).
2. Un harness sobre `flutter_driver`, que controla la app real a través del
   protocolo del VM Service de Dart — tocar botones, escribir texto, leer
   texto, esperar por widgets — igual que un usuario, pero sin ambigüedad
   de coordenadas de pantalla.

## Decisión

Opción 2. Verbatim del usuario: *"el mcp debe permitir el uso completo de
la app"* — un MCP que solo lee/escribe SQLite no ejercita la UI ni la
lógica de Notifiers/Services real, y hubiera sido un segundo camino de
lógica de negocio corriendo en paralelo a la app (justo lo que 0009
descarta para los CRUDs).

Arquitectura de tres piezas:

- **`test_driver/app.dart`** — entrypoint de desarrollo (fuera de `lib/`
  para que no se cuele en un build de release) que corre la misma
  `VulpTiketingApp` con `enableFlutterDriverExtension`. Además define un
  `DataHandler` de comandos "directos" (`import_tiketdata`,
  `export_tiketback`, `seed_producto`, etc.) que llaman a los mismos
  Notifier/Service que usaría la UI real, para lo que un test de UI no
  puede tocar — selectores de archivo nativos (`file_picker`) que viven
  fuera del árbol de widgets de Flutter. Comparte el mismo
  `ProviderContainer` que la UI vía `UncontrolledProviderScope`.
- **`test_driver/bridge.dart`** — mantiene una conexión `flutter_driver`
  persistente y la expone como HTTP simple (`/tap`, `/enter_text`,
  `/get_text`, `/wait_for`, `/wait_for_absent`, `/direct`). Cada acción va
  envuelta en `driver.runUnsynchronized()`: por defecto `flutter_driver`
  espera a que no haya frames pendientes antes de actuar, y un campo de
  texto con foco (cursor parpadeante) nunca llega a ese estado — sin el
  wrapper, la primera acción sobre un campo enfocado cuelga *todas* las
  acciones siguientes para siempre (bug real encontrado y corregido en esta
  misma sesión).
- **`scripts/mcp-driver/`** — servidor MCP (Node) que expone el bridge como
  herramientas de Claude Code (`vulp_tap`, `vulp_enter_text`, `vulp_direct`,
  `vulp_screenshot`, etc.), registrado en `.mcp.json`. Es una capa delgada:
  solo traduce llamadas MCP a `fetch()` contra el bridge, no conoce
  `flutter_driver` ni Riverpod.

`vulp_screenshot` resuelve un problema de entorno específico: niri
representa el espacio de todos los monitores como un lienzo lógico grande,
así que la ventana de la app puede estar en cualquier monitor. La
herramienta usa `niri msg -j windows` + `niri msg -j workspaces` para
encontrar el monitor real antes de llamar `grim -o <output>`, en vez de
asumir un monitor fijo.

## Alternativas descartadas

- **MCP solo-SQLite**: más simple, pero no ejercita la app real ni comparte
  lógica de negocio con la UI — descartado por la instrucción explícita del
  usuario de que el MCP debe permitir el uso completo de la app.
- **Appium o similar**: agrega una dependencia externa pesada (servidor
  Appium, drivers por plataforma) para un caso de uso que `flutter_driver`
  (ya incluido en el SDK de Flutter) cubre completo en este proyecto
  (una sola plataforma target: Linux desktop, sin necesidad de moverse a
  otros frameworks de testing).

## Validación

Probado end-to-end contra la app real: login completo (tap usuario → tap
contraseña → enter_text → tap Entrar) navega correctamente al Dashboard;
`vulp_direct import_tiketdata` contra un catálogo de prueba
importa los 39 productos/8 categorías y el grid de Venta Rápida se
actualiza en vivo sin reiniciar la app — el mismo flujo que antes
crasheaba por la UI con el bug de [gestión de estado](../arquitectura/gestion-estado.md#gotcha-real--late-final-en-un-campo-asignado-dentro-de-build) (`LateInitializationError`).

## Gotcha encontrado en uso (2026-07-29)

El harness, tal como quedó la primera versión, **hacía imposible usar la app
con el teclado físico**. `enableFlutterDriverExtension()` trae
`enableTextEntryEmulation: true` por defecto, que registra un
`TestTextInput` reemplazando la entrada de texto del sistema por un mock: los
eventos de tecla seguían llegando (Tab movía el foco, el cursor parpadeaba)
pero los caracteres se descartaban.

Lo insidioso es que la automatización quedaba **verde**: `driver.enterText()`
escribe directo en el mock, así que el login por el bridge funcionaba
perfecto mientras un humano no podía escribir una sola letra. Se descubrió
solo porque el usuario intentó auditar la app a mano.

Corregido invirtiendo la prioridad: la app pasa
`enableTextEntryEmulation: false` (el teclado humano manda siempre) y el
bridge enciende la emulación solo durante el instante en que escribe,
apagándola en un `finally`. Verificado que ambas coexisten en la misma
instancia: login completo por el bridge, y después escritura real con teclado
que filtra el grid.

Lección de método, más allá de este bug: un harness de automatización puede
degradar el uso manual de la app sin que ninguna prueba lo note, porque las
pruebas usan justamente el camino que el harness sustituye. Cualquier cosa que
el harness intercepte hay que verificarla también por la ruta humana.

## Consecuencias

- Requiere levantar 2 procesos externos a mano antes de que las
  herramientas MCP funcionen (`flutter run -t test_driver/app.dart` +
  `dart run test_driver/bridge.dart`) — documentado en
  `scripts/mcp-driver/README.md`. No hay arranque automático porque
  `flutter run` necesita quedar en foreground para hot-reload y logs.
- `flutter_driver` es dependencia de desarrollo únicamente
  (`dev_dependencies` en `pubspec.yaml`), cero impacto en el binario de
  producción.
