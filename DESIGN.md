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

**OWN-WORLD.** Dos lacas completas, una por modo, tomadas de la construcción
real de las cajas de las referencias — **negras por fuera, rojas por dentro**:

| | Marco (bandeja) | Interior (pozos) | Acento |
|---|---|---|---|
| Oscuro | negro `#14100E` | rojo `#3A1E1B` | metal |
| Claro | blanco `#F8F7F2` | verde `#D7E1D3` | metal |

Marco continuo con borde exterior grueso (24), paredes interiores compartidas
(12), radio exterior 20 contra radio de pozo 4. Cada pozo lleva un borde de
1px y una sombra de contacto en su borde superior. El metal
(oro / jade / peltre) es el único acento y solo marca acción primaria y
selección. Cero `BoxShadow` en celdas.

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

### 4. El modo define la laca; el metal es ortogonal

**El modo (claro/oscuro) determina la paleta completa**, no un ajuste del
usuario. Una caja bento física no cambia de color, pero una app sí — y
sostener lo contrario (bandeja oscura en los dos modos) tuvo dos costos
reales: los modos se veían casi iguales (parecía un "modo contraste", no un
modo claro) y todo lo que caía sobre la bandeja heredaba color de texto de
pozo, quedando ilegible.

Con una laca por modo, bandeja y pozo tienen **la misma polaridad** dentro de
cada modo, así que un texto mal asignado sigue siendo legible. Eso elimina
toda una clase de bug por construcción, en vez de tener que parchear pantalla
por pantalla.

El ajuste configurable de la [decisión 0020](docs/decisiones/0020-iconografia-vectorial-propia.md)
pasa a elegir el **acento** (oro / jade / peltre) — el pan de metal sobre laca,
que es tradicionalmente oro pero también peltre, más el jade de las
incrustaciones de piedra. Se
conserva la intención de 0020 (pocos, hardcodeados, coherentes) y se le da un
trabajo que no choca con el modo.

**El metal tiene dos fuerzas, no una:**

| Fuerza | Dónde | Por qué |
|---|---|---|
| **Ribete** (apagado, mezclado hacia el pozo) | borde de todos los pozos, campo en reposo | en laca real el pan de metal ribetea los cantos de la pieza |
| **Pleno** | acción primaria, selección actual, campo enfocado, indicador de estado | el acento marca acción, y sigue destacando porque el ribete está apagado |

El ribete se **deriva** del metal en código, no se hardcodea: con un tono fijo,
elegir peltre dejaba el elemento seleccionado en plata y todos los demás bordes
leyéndose dorados — el ajuste cambiaba una pieza y desafinaba el resto.
Verificado ≥3:1 contra la bandeja en los 3 metales × 2 modos, y hay una prueba
que exige que **cada metal dé un ribete distinto**.

El acento nunca es decoración y nunca aparece en estados inactivos.

### 5. Nada de `ColorScheme.fromSeed`

La paleta es de autoría propia, no generada por el algoritmo tonal de Google.
`fromSeed` + `DynamicSchemeVariant.neutral` fue la causa raíz del aspecto por
defecto: codifica elevación-como-claridad, que es lo contrario de un pozo.

### 6. Tallado: contraste gastado a propósito, y con techo

El texto se lee **grabado en su superficie**, no apoyado encima
(`lib/core/theme/bento_tallado.dart`). Calibrado por el usuario en el banco de
pruebas: profundidad 1.25, luz 0.70, sombra 0.65 — incisión poco profunda con
el canto brillante.

El efecto se consigue acercando el glifo al color de su fondo, así que **es
literalmente contraste gastado en estética**. Por eso tiene dos niveles y un
techo medido:

| Nivel | Dónde | Piso |
|---|---|---|
| `sutil` | texto de lectura, precios | 4.5:1 (AA) |
| `marcado` | ≥24px e iconos | 3:1 (WCAG 1.4.3 / 1.4.11) |

La fusión es **por modo**, no global: la calibración se hizo en oscuro, donde
0.50 queda al borde (4.30:1), pero en claro la misma fusión cae a 2.83:1 porque
la paleta clara tiene menos margen de luminancia. Techos medidos: 0.48 / 0.62 en
oscuro, 0.32 / 0.47 en claro.

Consecuencia aceptada: **en modo claro el tallado es más sutil** y no hay forma
de igualarlo sin romper AA.

`marcado` no se usa en un dato que deba dominar aunque su tamaño lo permita: el
precio de un producto con `marcado` quedaba más apagado que el nombre, o sea el
tallado se comía justo la jerarquía que había que sostener. La jerarquía la dan
tamaño y peso; el tallado no es una herramienta de jerarquía.

### 7. Táctil de verdad

Corre en tablet: todo objetivo interactivo tiene **mínimo 48dp**. Vale para
pozos tocables, botones y filas de lista.

### 8. Sin componentes stock dentro del mundo comprometido

`NavigationRail`, `Card` y `VerticalDivider` de Material dentro de una
bandeja comprometida son fugas. La navegación es una banda de bandeja; las
celdas son pozos.

---

## Contraste verificado

Fórmula WCAG sobre los pares realmente usados (script en scratchpad de la
sesión; texto ≥4.5:1, bordes de superficie ≥3:1 por WCAG 1.4.11).

| Par | Claro | Oscuro |
|---|---|---|
| Texto principal en pozo | 11.12:1 | 12.85:1 |
| Texto secundario en pozo | 5.70:1 | 7.02:1 |
| Texto sobre bandeja | 14.40:1 | 15.07:1 |
| Texto atenuado sobre bandeja | 6.76:1 | 7.08:1 |
| Borde del pozo vs bandeja | 5.14:1 | 3.82:1 |
| Borde del pozo vs su fondo | 4.10:1 | 3.07:1 |

Los 3 metales, cada uno como texto sobre bandeja, como texto sobre pozo y
como relleno con su propio color encima: **18 pares, 0 fallas**. El peor caso
es 4.65:1 (oro como texto sobre pozo verde), por encima del mínimo AA.

---

## Banco de pruebas de estilo

`test_driver/sandbox.dart` es una ventana **sin función**, solo para decidir
estilo mirándolo en vez de imaginándolo. Fuera de `lib/`, no entra en
producción ni en la navegación.

```fish
export PATH="$HOME/fvm/default/bin:$PATH"
VULP_WINDOW_TITLE="vulpedebug — sandbox" flutter run -t test_driver/sandbox.dart -d linux
```

Trae controles en vivo (modo, metal, profundidad del tallado, cuánto se funde
el glifo con el fondo) y muestra el **contraste medido de cada muestra**,
porque el tallado se logra acercando el glifo al color de su superficie y eso
baja el contraste por definición: la decisión estética conviene tomarla
sabiendo el costo. Probar un look acá antes de tocar las pantallas reales es
más barato y más honesto que deducirlo del código.

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

## Gestos: un dedo navega, dos o tres actúan

Deslizar de lado con **un** dedo cambia de ventana — a la izquierda la
siguiente, como pasar la hoja de un cuaderno. En los extremos no da la vuelta.

**Dos y tres dedos son para acciones.** La primera: dos dedos hacia abajo abren
el panel de productos de Ventana 2, hacia arriba lo cierran. Disparan al cruzar
el umbral —48 dp, un objetivo táctil—, no al soltar: la app prioriza velocidad. El gesto de navegación se
aparta en cuanto aparece un segundo dedo, incluso a mitad del arrastre: no basta
con un `HorizontalDragGestureRecognizer`, que sigue atendiendo al primer dedo y
navegaría igual.

Nada de esto se anima. El orden de prioridades de la app es **velocidad y
usabilidad primero, después ser intuitiva, y la estética al final**; una
transición cuesta frames en un teléfono de gama baja para no agregar
información.

La regla es previa a cada gesto nuevo: **antes de escribirlo hay que decir
cuántos dedos usa**. Uno es territorio de la navegación.

Ver [decisión 0030](docs/decisiones/0030-gestos-un-dedo-navega-varios-actuan.md).

