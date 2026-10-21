# 0020 — Iconografía vectorial propia: Python + SVG + tinte en runtime

**Fecha:** 2026-07-28
**Estado:** Aceptada

## Contexto

Los bocetos de pantallas usaban emojis como placeholder de íconos (🛒🧺📦📊⚙️, etc.). El usuario pidió reemplazarlos por íconos vectoriales propios generados con una librería de Python, con una estética concreta: interfaz sencilla e intuitiva, escala de grises para la jerarquía visual, y un matiz desaturado de algún color como acento — idealmente configurable en Configuración.

## Decisión

- **Generación**: Python + [`svgwrite`](https://pypi.org/project/svgwrite/) (dependencia liviana, sin bindings nativos) en un `.venv` propio bajo `tools/iconografia/` — Arch gestiona Python como entorno externo, no se instala nada globalmente ([convención ya establecida](../../CLAUDE.md) de `scripts/` para herramientas puntuales del workspace).
- **Formato**: SVG, grilla `24×24`, trazo (`stroke`) uniforme de `1.75`, `stroke-linecap`/`stroke-linejoin: round`, `fill: none` (estilo *outline*, no relleno) — salvo un par de detalles pequeños rellenos a propósito (el rayo de "Venta Rápida", las ruedas del carrito) para que se lean bien a tamaño chico.
- **Monocromo a propósito**: cada SVG usa un solo color base (`#1A1A1A`) sin ninguna intención de ser el color final — se **retiñe en tiempo de ejecución** en Flutter vía `flutter_svg` + `ColorFilter.mode(color, BlendMode.srcIn)`. Esto es lo que permite que un mismo ícono sirva para el estado inactivo (gris neutro) y activo (acento) sin mantener dos archivos.
- **Jerarquía por escala de grises + acento desaturado, configurable**: el tema (`buildBentoTheme`) usa `ColorScheme.fromSeed(seedColor: ..., dynamicSchemeVariant: DynamicSchemeVariant.neutral)` — la variante `neutral` de Material 3 mantiene el esquema cerca del gris con solo un matiz del color semilla, en vez del esquema vivo/saturado por defecto. Tres semillas desaturadas disponibles (`AcentoTinte`: azulado, verdoso, café), elegibles desde Configuración vía `PreferenciasNotifier` — ninguna es un color vivo protagonico.
- Íconos activos (`BentoIcon(activo: true)`) usan `colorScheme.primary` (el acento); inactivos usan `colorScheme.onSurfaceVariant` (gris neutro de Material 3).

## Gotcha encontrado — nunca usar `<style>`/clases CSS en los SVG

El primer intento definía el trazo con un bloque `<style>` + `class="t"` por elemento (más corto de escribir). `flutter_svg` (vía `vector_graphics_compiler`) **no soporta `<style>`** y lo ignora en silencio — las formas quedaban sin ningún trazo aplicado (`fill`/`stroke` caían al default SVG: relleno negro sólido, sin trazo), un error que solo se notó al correr `flutter test` (`unhandled element <style/>`), no en la previsualización con `cairosvg` (que sí soporta `<style>` y por eso mostraba los íconos bien). Se corrigió aplicando `fill`/`stroke`/`stroke-width`/etc. como **atributos de presentación directos en cada elemento**, no vía clase. El script (`tools/iconografia/generar_iconos.py`) lo deja documentado en su docstring para no repetirlo.

## Alternativas descartadas

- **Iconos de Material (`Icons.*`)**: no cumplen "interfaz propia/intuitiva a medida" pedido — son genéricos, no pensados para este set específico de conceptos (Venta Rápida vs. Panel de Venta necesitan distinguirse visualmente, por ejemplo).
- **Font de íconos (TTF vía IcoMoon/fantasticon)**: un paso extra de build sobre los SVG sin beneficio real para un set de ~10-20 íconos; `flutter_svg` renderiza SVG directo sin ese paso.
- **PyCairo/CairoSVG para generar**: más pesado (depende de la librería Cairo del sistema) sin necesitarlo — `svgwrite` alcanza para formas simples (círculos, rects, líneas, polígonos), que es todo lo que este set de íconos necesita.

## Consecuencias

- Nuevo directorio `tools/iconografia/` (script + `.venv` gitignored) y `assets/icons/*.svg` (sí versionado — es el artefacto final, no el entorno de generación).
- `flutter_svg` agregado a `pubspec.yaml`; `assets/icons/` registrado en la sección `assets:`.
- `PreferenciasNotifier` pasa de manejar un solo valor (`OrdenProducto`) a un objeto `Preferencias` con `ordenProducto` + `acento` — ver `docs/arquitectura/gestion-estado.md`.
- Set inicial (7 íconos): `venta_rapida`, `panel_venta`, `producto`, `reportes`, `configuracion` (nav del Dashboard) + `rol_gerente`, `rol_registradora` (Login). El resto de íconos de acción (buscar, editar, purgar, línea libre, etc.) se generan bajo el mismo sistema conforme se implementen esas pantallas — no se hicieron todos de una vez.
- Detalle completo del estilo y el set en [`docs/pantallas/iconografia.md`](../pantallas/iconografia.md).
