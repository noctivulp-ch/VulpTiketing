# Ideas abiertas

Cosas planteadas y **todavía sin decidir**. No hay código escrito para ninguna.
Cada una lleva lo que ya existe a favor, lo que costaría de verdad, y lo que hay
que decidir antes de empezar.

---

## 1. Tutoriales grabados desde la PC

Grabar tomas de la app para enseñar al personal, con toques automatizados para
que sean de calidad, repetibles y ampliables.

**Ya está casi todo lo difícil.** El harness maneja la app por el árbol de
semántica y es agnóstico al aparato: un tutorial es un guion de toques, igual que
una prueba. Y la app corre en la PC, así que se puede grabar una ventana en vez
de un teléfono.

**Decidido:** las indicaciones y el texto los pone el dueño a mano en DaVinci
Resolve. Así que **no hace falta puntero sintético ni onda de toque** — la toma
solo tiene que mostrar la app haciendo lo suyo, limpia y a buena resolución.

### El tamaño: los números

Los tres teléfonos miden lo mismo, medido por `adb shell wm size` y `wm density`:

| | |
|---|---|
| Físico | **1080 × 2312** px |
| Densidad | **480 dpi** → DPR **3** |
| Lógico | **360 × 770,67** dp |

Los 360 dp de ancho son los que disparan el diseño compacto (decisión 0026), así
que una ventana de 360 lógicos en la PC se ve **exactamente** como el teléfono.

Para que además grabe a 1080 de ancho hacen falta las dos cosas a la vez:

```
GDK_SCALE=3   +   ventana de 360×770 lógicos   =   1080×2312 físicos
```

Sin `GDK_SCALE`, en Linux el DPR es 1 y 360 lógicos son 360 píxeles: un video de
360 px de ancho no sirve para nada.

**Lo que hay que tocar:** `linux/runner/my_application.cc` fija la ventana en
1280×720 a pelo (línea 70) y no lee ninguna variable. Que lea `VULP_VENTANA=360x770`
es un cambio de tres líneas.

**Y no toca la app publicada**, al contrario de lo que se dijo antes: ese archivo
es el arranque del **runner de Linux**, que no entra en el APK de Android — la
versión publicada no lo compila siquiera. Linux no está lanzado y probablemente no
salga; Windows queda para compilar en máquina virtual más adelante. O sea que es
de los cambios más baratos que hay acá.

**Sigue por decidir:**

- ¿Ventana sin barra de título, o la recorta él en DaVinci?
- **Los datos de la toma.** Con la app vacía los videos muestran pantallas vacías.
  Hace falta un juego de demostración creíble y **estable entre tomas**: si cada
  regrabación tiene números distintos, el texto que él superponga deja de calzar.
- **El reloj.** El turno y el corte de caja dependen de la hora real: grabando de
  madrugada sale "Segundo turno" y "Toca: Apertura". ¿Se graba en horario
  coherente o se fija la hora?
- **La sincronización apagada** durante la grabación, o cualquier aparato de la red
  puede meter datos a mitad de toma.
- ¿Qué lecciones y en qué orden? Sospecha: cobrar una venta, cobrar por SINPE,
  corte de caja, mirar el reporte del día, exportar respaldo.
- Los guiones caducan cuando cambia la interfaz: conviene que vivan en el repo y
  anoten contra qué versión se grabaron.

### Sobre si quedan medidas fijas en la app

Duda planteada por el dueño: la app debería ser agnóstica al tamaño de pantalla,
así que ¿por qué hay números sueltos? Revisado, salen tres clases y solo una es
sospechosa:

| Clase | Ejemplos | Veredicto |
|---|---|---|
| Constantes físicas | 48 dp de objetivo táctil, 12 dp de pared | Correctas. No dependen de la pantalla; cambiarlas con ella sería el error |
| Umbrales deliberados | Cortes en 600 y 1024, `_altoAcostado = 520` | Correctas. Un umbral es un número o no es nada |
| **Mínimos con crecimiento** | `_altoMinimoRol`, `_altoMinimoRanking`, `_altoMinimoLista` | Correctas, y son exactamente el patrón que el dueño pide |

Lo que **sí** conviene mirar: los anchos fijos de algunos diálogos
(`SizedBox(width: 320)` en el calendario, 280 y 420 en otros). Funcionan porque un
`SizedBox` se recorta a las restricciones del padre, así que en un teléfono se
comportan como "todo lo ancho que se pueda, hasta N" — pero **esa intención no está
escrita en ningún lado y nada la prueba**.

Y el hueco de verdad: `test/layout_responsive_test.dart` cubre las cinco pantallas
en tres tamaños, **pero ningún diálogo**. Si una medida fija va a romper algo, va a
ser ahí y nadie se va a enterar.

---

## 2. Una librería de diseño para las apps QUE VIENEN

**Decidido: no es retroactivo.** No se saca el diseño de esta app ni se toca
DurdrawGUI. La idea es no empezar de cero en cada proyecto nuevo, teniendo ya dos
hechos con buena calidad de los que aprender.

Lo que el dueño señala como reutilizable: los acentos metálicos, los cuadrados,
las formas de botón, y **todo el sistema de construcción de layouts**.

### Lo que ya existe en los dos proyectos, y encaja

`DurdrawGUI/core/theme.py` (PySide6, 639 líneas) y `bento_theme.dart` llegaron
por separado **a la misma forma**: un diccionario de tokens **por rol**, con
variante clara y oscura y un solo acento.

| DurdrawGUI | VulpTiketing |
|---|---|
| `bg_base`, `bg_panel`, `bg_widget` | bandeja, pozo |
| `border` | cresta |
| `fg_base`, `fg_dim` | texto en bandeja, texto atenuado |
| `fg_accent` ámbar `#c09050` | metal oro `#D9A54A` |
| claro / oscuro / sistema | claro / oscuro / sistema |

Esa coincidencia es la prueba de que hay algo que extraer, y también dice **qué**:
la capa de tokens por rol, no los widgets.

### En Flutter: se puede, y el trabajo es sobre todo desacoplar

Lo que ya está escrito y es reutilizable tal cual:

| Pieza | Qué es |
|---|---|
| `bento_theme` | Tokens: espaciado, radios, las tres lacas, los metales, el `ColorScheme` completo |
| `bento_bandeja` | Bandeja y pozo — la geometría invertida, la cresta de 1 px |
| `bento_cuadricula` | La retícula de 6 columnas y los tres tamaños |
| `bento_tallado` | El relieve del texto |
| `bento_dialogo`, `bento_enlace`, `bento_aviso`, `bento_falla`, `bento_etiqueta_ajustada` | Los componentes con las reglas dentro |
| `DESIGN.md` | Las 11 reglas, que es lo que de verdad hace que se vea así |
| Pruebas de contraste | Ya blindan los números en los 3 tintes × 2 luminosidades |

Lo que **no** se va: `bento_icono_producto` y `bento_fotos` saben de categorías y
productos — son de la app, no del sistema.

Coste real: mover archivos, cortar lo que mira al dominio, montar un proyecto de
ejemplo y escribir la guía. No es rehacer nada.

### En Python: PySide6, y viaja la mitad

El toolkit ya está elegido de hecho — es el que usa. En Qt, un sistema de diseño
se aplica por `QPalette` y `QSS`, que es justo lo que `core/theme.py` ya hace.

- **Los tokens y las reglas viajan enteros.** Colores, espaciado, radios, el piso
  de contraste, el orden de los botones. Generar `QPalette` y `QSS` desde los
  tokens es mecánico.
- **El aspecto viaja a medias.** El relieve y la cresta están *pintados* en
  Flutter; en Qt eso son widgets con `paintEvent`. Prometer "el mismo look" sin
  escribir esos widgets sería mentira.

**A decidir antes de empezar:**

- **¿Un vocabulario común de roles**, o cada app con sus nombres y la librería
  solo aporta la maquinaria? Hoy son los mismos conceptos con nombres distintos.
- **¿Una fuente y dos salidas?** Si los tokens viven en un solo archivo y de ahí
  se generan el tema Dart y el Python, no hay dos paletas que mantener a mano —
  pero se añade un paso de generación.
- **¿La retícula viaja?** En Flutter son 6 columnas y tres tamaños pensados para
  teléfono/tablet/escritorio. En una app de escritorio que se redimensiona libre,
  las proporciones y el hueco sirven; los cortes por tamaño, probablemente no.
- **¿Las reglas se comprueban solas?** Lo que hace que el diseño de esta app se
  sostenga no son los colores: son las pruebas de contraste y de orden de botones.
  En Python eso sería un ayudante de test, y es la parte que más rinde.
- **¿Nombre?** Ahora todo se llama "bento", que es el nombre del *patrón*, no del
  sistema. Y el patrón **no aplica** a una app de dibujo como DurdrawGUI, así que
  el nombre del sistema no puede ser ese.
- **¿Cómo se distribuye?** Carpeta local, git, o publicado.

### Los widgets base entran, y el ejemplo ya está escrito

**Decidido:** la librería no se queda en tokens y un ayudante. Dejar los widgets
base hechos es parte de no empezar de cero.

Y el ejemplo de uso ya existe: `test_driver/sandbox.dart`, el banco de pruebas de
estilo — 1 288 líneas donde cada color del sistema se edita en vivo, se ve el
relieve con distintas intensidades sobre elementos de varios tamaños, y la
configuración resultante se **exporta a un archivo** para que quede como
especificación exacta en vez de interpretada de una captura.

Sirve para dos cosas a la vez, que es lo que lo hace buen ejemplo:

- **Validar la librería.** Si el banco se puede escribir usando solo la librería,
  la librería está completa. Si hay que salirse de ella, falta algo.
- **Enseñarla.** Quien la use tiene una app pequeña y funcional que toca todos los
  tokens, en vez de una lista de nombres de constantes.

### Lo que hay que cuidar

VulpTiketing **no se toca**: la librería nace mirando lo que ya funciona, no
extrayéndolo. Desde la 1.0.0 cada cambio en la app es una actualización sobre
datos reales, y una refactorización estética no justifica ese riesgo.

---

## 3. Bluetooth como respaldo de la red

Solo anotado, sin decidir: "si llega a dar más ventajas que desventajas". El caso
que lo motivó es que la WiFi de la soda no siempre es estable, y que alguno de los
aparatos podría ser el punto de acceso.
