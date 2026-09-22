# Ideas abiertas

Cosas planteadas y **todavía sin decidir**. No hay código escrito para ninguna.
Cada una lleva lo que ya existe a favor, lo que costaría de verdad, y lo que hay
que decidir antes de empezar.

---

## 1. Tutoriales grabados — **hecho**

La base está en [`scripts/grabacion/`](../scripts/grabacion/README.md), con su
propio README. Resumen de lo que se decidió al construirla:

- **Se graba en el teléfono**, no en la PC: es el aparato de verdad.
- **La resolución tiene techo y no es el que se quería.** El codificador del
  teléfono rechaza el tamaño nativo (1080×2312) y acepta hasta ~1088 en el lado
  largo → **508×1088**. Por la PC tampoco se llega: la pantalla es de 1080 de
  alto y una ventana de 2312 no cabe.
- Los guiones tocan por etiqueta, así que sobreviven a que un botón se mueva.
- Cada toma rehace los datos, comprueba el rol al entrar y para en el primer
  fallo — las tres salieron de tomas que salieron mal.

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

---

## 4. Costeo de recetas: módulo dentro, no app aparte ni tiketing genérico — **hecho** (ADR 0040, 2026-09-21)

Existe una hoja de cálculo de costos y precios en `AppCreator/Tablas/`
(`CalculoCostoRecetas.ods`, con siete notas en `docs/CalculoCostoRecetas/`,
incluido `06-modelo-para-app.md` con entidades y fórmulas ya listas para
código). El dueño quiere ese concepto en una app, y hay dos caminos.

### Lo que ya estaba decidido

La [decisión 0004](decisiones/0004-alcance-base-vs-futuro.md) previó el
inventario de insumos como feature próxima y pidió que Producto y Venta no lo
complicaran. Integrar fue el plan desde el diseño.

### Por qué integrar gana

El dato más sensible del modelo es `UnidadesEstimadasMes`, una estimación a
mano que hay que revisar cada mes. VulpTiketing tiene **las ventas reales por
producto y mes**: con ellas debajo, el margen real se calcula contra lo que de
verdad se vendió y se cobró. Una app aparte solo llega ahí con un puente de
importación que alguien tiene que mantener y acordarse de correr.

Además: catálogo único (en dos apps diverge a la primera semana), mix real
efectivo/SINPE en vez de una comisión única, y respaldo/sync/roles/tema ya
pagados.

### Lo que cuesta

- Es un update sobre datos de producción: cada tabla es una migración, y si
  los costos se sincronizan hay que subir `esquemaSync` con todos los aparatos
  a la vez.
- Cuatro pantallas nuevas (insumos, recetas, costos fijos, resultado) más
  configuración, solo para el Gerente.
- 26 columnas por producto no caben en un teléfono: tarjetas bento, no tabla.
  Esto lo paga cualquiera de los dos caminos.

### La trampa: "hacer tiketing genérico"

Añadir el módulo y generalizar la app son dos proyectos distintos. El modelo
de costos ya es genérico. Generalizar VulpTiketing significaría desmontar lo
que lo hace bueno —colones enteros, dos turnos con un corte, la casilla SINPE,
efectivo como normal, iconos de la carta— y hoy no hay un segundo cliente que
lo pida. **No se generaliza.**

### Planteo

1. Cálculo como paquete Dart puro (`costeo/`, sin Flutter):
   `calcularCatalogo(config, costosFijos, insumos, productos, recetas)`.
   Determinista, con la hoja como oráculo de las pruebas. Si algún día
   conviene la app aparte, ese paquete se levanta entero.
2. Tablas propias sin tocar `producto`: `insumo`, `linea_receta`,
   `costo_fijo`, `config_costeo`, y `producto_costeo` 1:1 con lo que la hoja
   añade (unidades por lote, minutos, margen, ajuste).
3. Solo Gerente, un bloque del dashboard.
4. Volumen = ventas reales del mes elegido; la estimación manual queda de
   reserva para productos sin historial.
5. "Aplicar precio" explícito y por producto. Nunca automático ni en bloque:
   cambiar el volumen de uno mueve el precio de todos.

   **Precisado por el dueño (2026-09-21):** llevar el precio de venta según
   el cálculo es **estrictamente opcional**. Hay quien maneja los precios
   aparte por sus razones, y para esa persona el módulo es **soporte e
   información**: muestra costo, margen real contra lo que cobra y alertas,
   y no toca `precio_base` jamás. Quien quiera que sea la herramienta
   principal usa "aplicar precio". *"Tiketing al final es una libreta de
   apuntes con esteroides."* Esto va como regla del ADR cuando se escriba.

### Por decidir antes de empezar

- **¿Los costos se sincronizan?** Sí ⇒ `esquemaSync` 5 y todos los aparatos a
  la vez. No ⇒ solo `.tiketback` y se editan en un aparato. Recomendado: sí.
- Qué mes usa como volumen por defecto (el anterior completo, o un promedio).
- Si las sub-recetas (una masa base en cinco productos) entran en la primera
  versión o después. Requieren detectar ciclos.

---

## 5. Versátil sin desprestigiar la base (2026-09-21)

El dueño quiere que la app sirva también para su negocio —apps open source
vendidas por Patreon— y para un trabajo de desarrollo empresarial de la U
(costos, punto de equilibrio). Criterio: *"hacer más versátil la app sin
desprestigiar su funcionalidad base"*. Lo de la soda no se toca; lo nuevo es
apagable.

La investigación y la lista completa están en
[investigacion/costeo-tributacion-y-versatilidad.md](investigacion/costeo-tributacion-y-versatilidad.md).
Hallazgo que cambia el diseño: en el régimen simplificado el impuesto se
calcula **sobre las compras** del trimestre, así que el libro de compras de
insumos es también la base imponible de una soda.

Orden acordado (que exista → mejorar → optimizar → pulir):

1. **Libro de compras de insumos** con promedio ponderado móvil (el insumo se
   registra una vez; cada compra es una entrada; el costo sale de las
   entradas). Un insumo sin compras puede llevar un precio de arranque a mano
   que deja de contar con la primera compra real.
2. **Impuestos flexibles**: tasa por producto, comisión por medio de pago,
   régimen en Ajustes (simplificado con factores sobre compras / general).
3. **Moneda opcional** (símbolo y decimales).
4. **Food cost %**, equilibrio en colones, escenarios.
5. **Elegir ventanas de venta** en Configuración: las dos, solo Venta Rápida,
   solo Panel.
6. Perfil de negocio de servicios (sin receta sin alerta, amortización).
7. Importar ventas desde CSV (Patreon) — después, si vale la pena.
