# 0023 — Refinamiento del sistema visual bento: convenciones de interacción y tema

**Fecha:** 2026-07-29
**Estado:** Aceptada

## Contexto

Tras la primera pasada de implementación del diseño bento (decisiones informales documentadas como "Fases 0–6" en los commits del repo, ver `docs/pantallas/prototipos-ascii.md`), el usuario probó la app real y dio 8 puntos de feedback concretos. Varios de esos puntos son correcciones puntuales (ver commits de las Fases A–F de esta ronda), pero algunos establecen **convenciones nuevas que aplican de acá en adelante**, no solo a las pantallas tocadas en esta pasada — se documentan acá para que futuras sesiones no las tengan que redescubrir.

## Decisiones

### 1. Evitar overlays/diálogos en la medida de lo posible

En una app bento, la información y las acciones deben vivir en el layout persistente de la pantalla (paneles, tiles seleccionables) en vez de en `AlertDialog`/`SimpleDialog` emergentes — un overlay rompe el modelo mental de "todo tiene su celda fija". Ejemplo aplicado: Configuración pasó de "tocar un tile abre un diálogo" a "tocar un tile selecciona una opción, un panel fijo debajo muestra su contenido" (ver `lib/features/configuracion/ui/configuracion_screen.dart`).

**No es una prohibición absoluta.** Diálogos siguen siendo aceptables cuando la acción es genuinamente modal/aislada del resto de la pantalla y no tiene un "lugar natural" en el layout — ej. el overlay de cobro rápido de Ventana 1 (`_OverlayCobroRapido`, decisión ya tomada: "una sola responsabilidad, cobrar este producto") o el formulario de alta/edición de Producto. La confirmación de acciones irreversibles (purgar, restaurar backup, reemplazar catálogo) tampoco desaparece — se resuelve como un paso adicional *dentro* del panel/diálogo existente, no se elimina el paso de confirmación en sí.

### 2. Figuras conectadas con separadores, no paneles redondeados sueltos — con matices

Cuando varios elementos son conceptualmente **un solo bloque** (ej. un panel de lista + su barra de búsqueda, un grid de opciones + su panel de detalle), deben compartir un contenedor visual con separadores internos en vez de ser `Card`s individuales con gaps entre sí. El separador no tiene que ser una línea negra — puede ser un cambio de tono de fondo, espaciado asimétrico, un ícono, etc.

**Matiz importante, descubierto iterando con el usuario sobre Reportes**: esto NO aplica a elementos que son unidades individuales comparables entre sí (tarjetas de producto en un grid, tiles de Configuración, tarjetas de rol en Login, o incluso las 3 tarjetas de turno de Reportes) — esas siguen siendo celdas bento propias, cada una con su `Card`/radio de esquina individual. El primer intento en Reportes fusionó el hero y los 3 turnos en un único `Card` con líneas divisorias internas; el usuario probó el resultado y prefirió el look de tarjetas individuales de antes — el problema real nunca fue la separación entre celdas comparables, sino que cada tarjeta de turno no llenaba la altura disponible (ver decisión 4).

Regla práctica: **"separar con un contenedor compartido" aplica a piezas de roles distintos que funcionan como una sola unidad** (buscador+lista, grid+panel); **piezas del mismo rol repetidas** (ítems de una colección) siguen siendo celdas bento individuales con gap consistente entre ellas, no fusionadas.

### 3. Buscador abajo + "cascada invertida"

En paneles de búsqueda con resultados en lista (panel lateral de Ventana 2, listado de Ventana 3), el campo de búsqueda vive en una barra inferior (junto a las acciones relacionadas, ej. agregar producto), y la lista de resultados usa `ListView(reverse: true)`: el primer resultado (mejor match, mismo orden que ya calculaba el provider correspondiente) queda pegado al buscador, y el resto crece hacia arriba. No hace falta reordenar los datos a mano — alcanza con `reverse: true` sobre el orden que el provider ya entrega.

### 4. `IntrinsicHeight` + `stretch` para que celdas hermanas compartan altura

Patrón reutilizable para "N elementos lado a lado deben tener exactamente la misma altura, determinada por el contenido más alto": envolver el `Row` en `IntrinsicHeight` y usar `crossAxisAlignment: CrossAxisAlignment.stretch`. Sin `IntrinsicHeight`, un `Row` no-Expanded dentro de un `Column` recibe altura no acotada de su padre, y `stretch` fuerza una excepción de "altura infinita" (bug real encontrado y corregido dos veces en `reportes_screen.dart` durante esta pasada — ver commits de la Fase 5 original y la Fase E de esta ronda).

### 5. Tema claro/oscuro/sistema

`ThemeMode` completo (Claro/Oscuro/Sistema, con Sistema por defecto) sobre los mismos acentos desaturados hardcodeados de la decisión 0020 — `ColorScheme.fromSeed(..., brightness: ...)` genera la variante oscura desde la misma semilla, sin necesitar una paleta aparte. Preferencia persistida junto a orden/acento (`Preferencias.modoTema`, `lib/features/configuracion/preferencias_notifier.dart`). Ver `lib/core/theme/bento_theme.dart` (`buildBentoTheme` con parámetro `brightness`) y `lib/app.dart` (`darkTheme`/`themeMode`).

## Nota de proceso — verificación visual de cambios de layout

Dos bugs reales de esta pasada (altura infinita en Reportes, fuga de foco entre pestañas de `IndexedStack`) no los detectó ni `flutter analyze` ni `flutter test` — solo se encontraron navegando la app real. Se confirma la disciplina ya establecida: todo cambio de layout se verifica lanzando la app y navegando de verdad (teclado: `wtype`/`ydotool` + captura `grim`; los clicks de mouse con coordenadas absolutas dieron resultados inesperados en este entorno de doble monitor y se evitan). Cuando un control específico es difícil de alcanzar por teclado, forzar temporalmente su estado por defecto en el código (revertido antes de comitear) es una técnica válida para no bloquear la verificación.

## Consecuencias

- `docs/pantallas/prototipos-ascii.md` actualizado con el estado de implementación de esta ronda.
- Futuras pantallas nuevas deben seguir las convenciones 1–4 desde el diseño, no como corrección posterior.
- Pendiente explícito, mencionado por el usuario pero fuera de esta pasada: una auditoría de diseño responsive (que la app se adapte correctamente a distintos tamaños de pantalla) — se hará después de cerrar el resto del feedback puntual.
