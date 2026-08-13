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

**El punto que decide la calidad: los toques no se ven.** Las acciones sintéticas
llaman al mismo callback que el dedo, pero **no dibujan la onda de Material ni
mueven ningún puntero**. Un video así muestra pantallas que cambian solas, y para
enseñar eso es peor que inútil: no se ve dónde hay que tocar. Tres salidas:

| Salida | Qué implica |
|---|---|
| Inyectar punteros de verdad | El harness ya tiene `gesto`, que entra por `handlePointerEvent` y sí dispara la onda. Habría que apuntar por coordenada, que es lo que se quitó por frágil |
| Dibujar un puntero falso | Una capa encima que pinta un círculo donde va a tocar. Independiente del gesto, y controlable |
| Ninguna | Sirve para "mirá cómo queda", no para "hacé esto" |

**Lo demás a resolver:** la ventana de escritorio no tiene la forma de un
teléfono (habría que fijarla en 360×800 lógicos para que se parezca a lo que van a
usar), y el grabador en Wayland/Niri hay que elegirlo y probarlo.

**A decidir antes de empezar:**

- ¿Toques visibles? — mi recomendación: puntero falso dibujado, porque no ata el
  guion a coordenadas.
- ¿Con voz o mudo con subtítulos? Mudo se puede regenerar entero sin volver a
  grabar audio.
- ¿Marco de teléfono alrededor, o ventana limpia?
- ¿Qué lecciones y en qué orden? Sospecha: cobrar una venta, cobrar por SINPE,
  corte de caja, mirar el reporte del día, exportar respaldo.

---

## 2. El sistema de diseño como librería

El estilo es **suyo, no de la soda** — la app es solo donde se usó primero.
Sacarlo a una librería importable en Dart/Flutter, y adaptarlo a Python con
documentación.

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

### En Python: se puede la mitad, y hay que elegir cuál

Un sistema de diseño no se "porta" a Python como una librería de widgets. Se
parte en dos, y las dos mitades no cuestan lo mismo:

- **Los tokens y las reglas viajan enteros.** Colores, espaciado, radios,
  contraste, el orden de los botones, la retícula. Eso es un paquete pequeño y
  documentación.
- **El aspecto viaja a medias.** El relieve y la cresta están *pintados* en
  Flutter. En GTK o Qt se aproximan con CSS/QSS y bordes; en una interfaz de
  terminal no existen. Prometer "el mismo look" en cualquier toolkit sería
  mentira.

**A decidir antes de empezar:**

- **¿Qué toolkit?** GTK4/Adwaita, Qt/PySide, Textual y web dan resultados muy
  distintos. Elegir uno primero; los demás después, si hace falta.
- **¿Nombre?** Ahora todo se llama "bento", que es el nombre del *patrón*, no del
  sistema. Si es suyo, conviene que se llame como suyo.
- **¿Alcance?** Solo tokens y reglas, o también componentes.
- **¿Cómo se distribuye?** Carpeta local, git, o publicado.

### Lo que hay que cuidar

Sacar el sistema del proyecto significa que **VulpTiketing pasa a depender de
algo externo**, y desde la 1.0.0 cada cambio es una actualización sobre datos
reales. Conviene que la extracción no toque la app hasta que la librería esté
quieta, o hacerla contra una copia.

---

## 3. Bluetooth como respaldo de la red

Solo anotado, sin decidir: "si llega a dar más ventajas que desventajas". El caso
que lo motivó es que la WiFi de la soda no siempre es estable, y que alguno de los
aparatos podría ser el punto de acceso.
