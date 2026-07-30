# DESIGN.md — VulpTiketing

Decisiones visuales durables. Los tokens exactos viven en
`lib/core/theme/bento_theme.dart`; este archivo manda sobre *por qué* y las
reglas que no se negocian por conveniencia de implementación.

Modo de superficie: **Operate** — la registradora está haciendo una tarea
(cobrar). La expresión nunca puede tapar la tarea, el estado ni una
affordance conocida. La marca vive en los detalles precisos, no en el
protagonismo.

Escena de uso (confirmada con el usuario, 2026-07-29): el dispositivo se
mueve entre mostrador con luz de día fuerte e interior con luz artificial, y
corre tanto en tablet táctil como en laptop. Las dos consecuencias duras
están abajo.

---

## Contrato de dirección

**THESIS.** La pantalla es **una bandeja de una sola pieza** con el contenido
hundido en pozos tallados — no una página de tarjetas flotando sobre un
fondo. Rechaza explícitamente el modelo de Material 3 donde importancia =
elevación = superficie más clara.

**OWN-WORLD.** Laca oscura saturada como marco continuo: borde exterior
grueso (24), paredes interiores compartidas (12), radio exterior 20 contra
radio de pozo 4. Cada pozo lleva una cresta de pared iluminada de 1px y una
sombra de contacto en su borde superior. Un solo acento (oro de laca) para
acción primaria y selección. Cero `BoxShadow` en celdas.

**STORY.** La registradora distingue de un golpe qué pozo es qué por su
tamaño y su hueco; el marco nunca compite con los datos.

**FIRST VIEWPORT.** Rail izquierdo como banda de bandeja (no un
`NavigationRail` stock); grid de productos como pozos iguales; el total en un
pozo grande y propio.

**FORM.** Mundo fijado por el usuario (bento). No se corrió tirada de
concepto porque el mundo no se reemplaza — se re-renderiza desde su rango
material completo. La falla anterior fue de ejecución, no de selección.

---

## Reglas que no se negocian

### 1. La profundidad la carga la cresta, no la sombra

Verificado numéricamente: **en modo oscuro es imposible** lograr 3:1 entre
dos superficies oscuras (el rango de luminancia está comprimido) — la
bandeja contra el pozo da 1.43:1. Por eso el tallado **no** puede depender
del escalón de valor bandeja↔pozo.

La señal primaria es la **cresta de pared**: una línea de 1px más clara en el
borde superior/izquierdo de cada pozo, verificada ≥3:1 contra la bandeja en
ambos modos (claro 3.20:1, oscuro 3.48:1). Es lo mismo que hace legible una
caja de laca negra real: los compartimentos se ven porque las crestas atrapan
la luz, no porque los fondos difieran de tono.

Corolario de la escena de uso: **prohibido usar sombras suaves de baja
opacidad como señal de profundidad.** Bajo sol directo desaparecen. Bordes
duros de 1px y saltos de valor reales, o nada.

### 2. La bandeja es continua; el hueco entre pozos es material, no fondo

El espacio entre dos pozos **es la pared de la bandeja**, con el ancho del
sistema (12). Nunca es "el fondo de la página asomándose". Dos pozos
adyacentes comparten una sola pared — nunca dos bordes enfrentados.

Consecuencia: una pantalla es *un* contenedor de bandeja con pozos recortados
dentro, no N tarjetas con `margin`.

### 3. Geometría invertida respecto a lo anterior

| Elemento | Radio |
|---|---|
| Bandeja (exterior) | 20 |
| Pozo (interior) | 4 |

Lo anterior tenía todo en 12 uniforme (cards, inputs, botones, list tiles,
diálogos), que es el rectángulo redondeado genérico. En una bandeja real el
exterior es suave y los compartimentos son rectilíneos.

### 4. Un solo acento, y es material

El acento es el oro de la laca. Se usa **solo** para acción primaria,
selección actual e indicador de estado — nunca decoración, nunca en estados
inactivos.

Los 3 tintes configurables (decisión 0020) dejan de ser tres grises
desaturados —causa directa del aspecto genérico— y pasan a ser tres acabados
de laca reales. Se conserva la intención de 0020 (pocos, hardcodeados,
coherentes); se corrige que no había color en ninguna parte.

### 5. Nada de `ColorScheme.fromSeed`

La paleta es de autoría propia, no generada por el algoritmo tonal de Google.
`fromSeed` + `DynamicSchemeVariant.neutral` fue la causa raíz del aspecto por
defecto: codifica elevación-como-claridad, que es lo contrario de un pozo.

### 6. Táctil de verdad

Corre en tablet: todo objetivo interactivo tiene **mínimo 48dp**. Vale para
pozos tocables, botones y filas de lista.

### 7. Sin componentes stock dentro del mundo comprometido

`NavigationRail`, `Card` y `VerticalDivider` de Material dentro de una
bandeja comprometida son fugas. La navegación es una banda de bandeja; las
celdas son pozos.

---

## Contraste verificado

Fórmula WCAG sobre los pares realmente usados (script en scratchpad de la
sesión; texto ≥4.5:1, bordes de superficie ≥3:1 por WCAG 1.4.11).

| Par | Claro | Oscuro |
|---|---|---|
| Texto principal en pozo | 14.56:1 | 10.52:1 |
| Texto secundario en pozo | 5.12:1 | 4.99:1 |
| Texto sobre bandeja | 11.69:1 | 15.02:1 |
| Texto sobre acento | 5.53:1 | 7.84:1 |
| Cresta vs bandeja (borde) | 3.20:1 | 3.48:1 |

---

## Herencia

Sigue vigente de [decisión 0023](docs/decisiones/0023-refinamiento-bento-post-implementacion.md):
evitar overlays y diálogos donde un panel persistente resuelva; cascada
invertida en buscadores; `IntrinsicHeight` + `stretch` para altura compartida
entre celdas hermanas. Esa pasada acertó en topología y falló en material —
este documento corrige el material sin deshacer la topología.

Lo que **se corrige** de 0023: "figuras conectadas con separadores" quedó
implementado como celdas adyacentes sin señal de profundidad, así que se leía
como botones pegados. La unión ahora se lee como tallado por la cresta y la
sombra de contacto.

Notas de herramienta: el detector mecánico de impeccable es solo web
(HTML/CSS/URL), no analiza Dart — no aplica a este proyecto y no se corre.
