# Prototipos ASCII — Fase 2

Ver también: [flujo-descripcion](flujo-descripcion.md) (Fase 1, base funcional)

Diseño bento-box (skill `design:bento-design`, más `color-system`/`visual-hierarchy`/`aesthetic-usability`/`typography-scale` para la pasada de implementación). Estos son bocetos de **diseño**, no un mapeo literal widget-por-widget — la implementación real (2026-07-29, ver `lib/core/theme/bento_theme.dart` y las 6 pantallas) sigue estos principios y esta estructura, pero con las adaptaciones de detalle que pide Flutter real (ej. `_TileEstadoSync` es un tile tocable en vez de un switch+subtítulo, el ripple granulado es una implementación `InteractiveInkFeature` propia, la notificación de esquina es un `OverlayEntry`). Layout de teléfono sigue pendiente, igual que exportar PDF/CSV en Reportes.

## Principios aplicados en esta pasada

Además de los principios estándar de bento (una celda = una responsabilidad, jerarquía por tamaño, espaciado consistente), esta app pidió explícitamente:

- **No seguir la regla de los 3 clicks** — priorizar un lenguaje visual reconocible sobre minimizar la cuenta de taps. Está bien que "agregar producto" abra un panel y dentro haya que tocar un ítem — lo que importa es que cada paso sea instantáneo de reconocer, no que sean pocos.
- **Navegación no-textual**: la barra de navegación del Dashboard (Ventana 1–5) es **solo íconos**, sin etiquetas de texto por defecto. Un ícono fijo por función, siempre el mismo, en el mismo lugar — el usuario aprende el mapa visual una vez y no vuelve a leer para navegar.
- Esto **no aplica igual a todo**: identificar qué producto se está vendiendo sí necesita nombre + precio (es contenido del dominio, no navegación) — ahí se prioriza la foto grande como identificador primario y el nombre como refuerzo secundario, no lectura obligatoria. Pantallas de uso raro (Configuración) toleran más texto porque no están en el camino crítico de "vender rápido muchas veces al día".

## Sistema visual (tokens)

| Token | Valor |
|-------|-------|
| Unidad base | 8px |
| Gap entre celdas | 16px |
| Gap entre grupos | 24px |
| Padding interno de celda | 16–24px |
| Pared entre pozos | 12px |
| Radio de esquina | **4px (pozo), 20px (bandeja)** — geometría invertida, ver `DESIGN.md` regla 3 |
| Retícula | **6 columnas**; cada pieza declara su span por tamaño (decisión 0026) |
| Tamaños de pantalla | compacto <600dp · medio 600–1023 · amplio ≥1024 |
| Acento | un solo color, reservado para la acción primaria de cada pantalla (Entrar, Finalizar venta, Completado, Guardar) |
| Acciones destructivas/irreversibles | nunca a un solo tap en la vista principal — siempre piden confirmación (Purgar, Revertir) |

### Feedback táctil (universal — todo elemento tocable de la app)

- **Al presionar**: onda circular blanca semitransparente con textura granulada (símil papel rugoso, no un ripple liso), que nace en el punto exacto de la presión y crece hasta cubrir todo el elemento, luego desaparece. Duración corta — un poco más lenta que un parpadeo (≈200ms).
- Aplica a cualquier botón, celda de producto, ícono de navegación — mismo lenguaje de interacción en toda la app, no solo en ventas.
- *Nota de implementación:* el ripple estándar de Flutter (`InkWell`) es liso; esta textura granulada requiere un `splashFactory`/`CustomPainter` propio (una textura de grano/ruido enmascarada por el círculo animado) — detalle de implementación, no bloquea el diseño.

### Feedback de finalización (universal, no solo Venta)

Notificación no intrusiva en una esquina, visible 1–2 segundos, para cualquier acción de completitud: venta finalizada, producto creado/editado/descontinuado/purgado, backup exportado/restaurado, catálogo `.tiketdata` importado, etc. — mismo patrón siempre, cierra el hallazgo #4 del [mapa de flujo](mapa-de-flujo.md).

---

## Login / Setup

Selección de rol por ícono (sin depender del texto para reconocer cuál es cuál — en la implementación real, íconos ilustrativos distintivos, no las siluetas genéricas de este boceto), luego contraseña.

**Paso 1 — elegir rol:**
```
┌────────────────────────────────────────────────┐
│                                                  │
│                  VulpTiketing                   │
│                                                  │
│      ┌──────────────────┐  ┌──────────────────┐ │
│      │                  │  │                  │ │
│      │       (i1)       │  │       (i2)       │ │
│      │      Gerente     │  │   Registradora   │ │
│      │                  │  │                  │ │
│      └──────────────────┘  └──────────────────┘ │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Paso 2 — tras seleccionar (ej. Registradora), pide contraseña:**
```
┌────────────────────────────────────────────────┐
│                                                  │
│                  VulpTiketing                   │
│                                                  │
│        ┌────────────────────────────┐          │
│        │   (i2)   Registradora  ✓   │  ← seleccionado, resaltado con acento
│        └────────────────────────────┘          │
│                                                  │
│        ┌────────────────────────────┐          │
│        │   ● ● ● ● ● ● ● ●           │  ← contraseña
│        └────────────────────────────┘          │
│        ┌────────────────────────────┐          │
│        │          Entrar             │  ← único botón, color de acento
│        └────────────────────────────┘          │
└──────────────────────────────────────────────────┘
```

---

## Dashboard (shell — envuelve las Ventanas 1–5)

Rail de navegación **solo íconos**, mismo orden y posición siempre.

**Pantalla ancha (tablet/PC) — rail lateral:**
```
┌────┬─────────────────────────────────────────────┐
│ 🛒 │                                              │
│    │                                              │
│ 🧺 │                                              │
│    │         (contenido de la ventana             │
│ 📦 │          seleccionada — ver abajo)            │
│    │                                              │
│ 📊 │                                              │
│    │                                              │
│ ⚙  │                                              │
└────┴─────────────────────────────────────────────┘
```

**Pantalla angosta (teléfono) — pestañas inferiores, deslizables si no caben:**
```
┌───────────────────────────────────────────────────┐
│                                                     │
│              (contenido de la ventana)             │
│                                                     │
├────┬────┬────┬────┬────┬─ desliza para más ─►      │
│ 🛒 │ 🧺 │ 📦 │ 📊 │ ⚙  │                            │
└────┴────┴────┴────┴────┴────────────────────────────┘
```

Mapa de íconos (fijo, se repite en cada boceto de abajo):

| Ícono | Ventana |
|-------|---------|
| 🛒 | 1 — Venta Rápida |
| 🧺 | 2 — Panel de Venta |
| 📦 | 3 — CRUD de Producto |
| 📊 | 4 — Reportes |
| ⚙ | 5 — Configuración |

La tab activa se resalta con el color de acento (fondo o borde) — no hace falta texto para saber dónde estás.

---

## Ventana 1 — Venta Rápida

Grid uniforme (los productos son ítems pares entre sí, no hay jerarquía entre ellos — la jerarquía bento aquí es "foto grande, precio y nombre secundarios", no diferencias de tamaño entre celdas).

**Modo Alfabético o Precio** ([decisión 0018](../decisiones/0018-orden-y-busqueda-de-producto.md)) — lista plana:

```
┌─────────────────────────────────────────────────────┐
│  🔍 [ buscar producto o categoría... ]               │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐         │
│  │  [foto]   │  │  [foto]   │  │  [foto]   │         │
│  │   Café    │  │  Gallo    │  │   Jugo    │         │
│  │   ₡800    │  │  ₡1500    │  │   ₡900    │         │
│  └───────────┘  └───────────┘  └───────────┘         │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐         │
│  │  [foto]   │  │  [foto]   │  │  [foto]   │         │
│  │    ...    │  │    ...    │  │    ...    │         │
│  └───────────┘  └───────────┘  └───────────┘         │
└─────────────────────────────────────────────────────┘
```

**Modo Categoría** — mismo grid, agrupado con separador por categoría (0018):

```
┌─────────────────────────────────────────────────────┐
│  🔍 [ buscar producto o categoría... ]               │
│  ───────────────── Bebidas ─────────────────         │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐         │
│  │  [foto]   │  │  [foto]   │  │  [foto]   │         │
│  │   Café    │  │   Jugo    │  │  Té frío  │         │
│  │   ₡800    │  │   ₡900    │  │   ₡700    │         │
│  └───────────┘  └───────────┘  └───────────┘         │
│  ───────────────── Comida ──────────────────         │
│  ┌───────────┐  ┌───────────┐                         │
│  │  [foto]   │  │  [foto]   │                         │
│  │  Gallo    │  │  Tostada  │                         │
│  │  ₡1500    │  │   ₡600    │                         │
│  └───────────┘  └───────────┘                         │
│  ─────────────── Sin categoría ─────────────          │
│  ┌───────────┐                                        │
│  │  [foto]   │                                        │
│  │  Prueba   │                                        │
│  │   ₡100    │                                        │
│  └───────────┘                                        │
└─────────────────────────────────────────────────────┘
```

**Búsqueda con ranking nombre > categoría** (0018) — ejemplo escribiendo "jug":

```
┌─────────────────────────────────────────────────────┐
│  🔍 [ jug ]                                          │
│  ── Coincidencia por nombre ──                       │
│  ┌───────────┐                                        │
│  │   Jugo    │                                        │
│  │   ₡900    │                                        │
│  └───────────┘                                        │
│  ── Categoría "Bebidas" ──  (sin repetir Jugo)        │
│  ┌───────────┐  ┌───────────┐                         │
│  │   Café    │  │  Té frío  │                         │
│  └───────────┘  └───────────┘                         │
└─────────────────────────────────────────────────────┘
```

Tocar un producto → overlay (una sola responsabilidad: cobrar ese producto):

```
        ┌─────────────────────────────────┐
        │   [foto]        Café            │
        │                                  │
        │   Cantidad     [ − ]  1  [ + ]   │
        │   Precio       [ ₡800         ]  │
        │   Recibí       [              ]  │
        │   Cambio  →    ₡ —               │
        │                                  │
        │       ┌────────────────┐         │
        │       │  ✓ Completado   │  ← acento
        │       └────────────────┘         │
        └─────────────────────────────────┘
```

Al completar, overlay se cierra y aparece (esquina, no intrusivo, se auto-oculta):
```
                                       ┌────────────┐
                                       │ ✓ Venta OK │
                                       └────────────┘
```

---

## Ventana 2 — Panel de Venta

**Estado base** (carrito + barra inferior):

```
┌───────────────────────────────────────────────────────────┐
│ ┌───────────────────────────────────────────────────────┐ │
│ │ [foto] Café              x1        ₡800     [✎] [🗑]  │ │
│ ├─────────────────────────────────────────────────────── │ │
│ │ [foto] Gallo pinto       x2       ₡3000     [✎] [🗑]  │ │
│ ├─────────────────────────────────────────────────────── │ │
│ │ [foto] Jugo natural      x1        ₡900     [✎] [🗑]  │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌───────────────┬─────────────────────┬────────┬──────────┐ │
│ │ Recibí [ ___ ]│ Cambio: ₡ —         │ ₡4,700 │ Finalizar│ │ ← único botón real de la barra
│ └───────────────┴─────────────────────┴────────┴──────────┘ │
│                                                      ┌─────┐│
│                                                      │ 🧺+ ││ ← pestaña "agregar producto"
└──────────────────────────────────────────────────────┴─────┘
```
`[✎]` edita precio/cantidad/nota de esa línea. `[🗑]` la quita del carrito (no es "descontinuar" — eso es en la Ventana 3, sobre el catálogo).

**Al tocar la pestaña "agregar producto"** — panel persistente al lado (no overlay), reduce el ancho del carrito. El botón mismo que abrió el panel **se arrastra con él**: queda anclado al borde de contacto entre los dos paneles, y tocarlo ahí lo vuelve a cerrar (es el mismo control, no uno de abrir y otro de cerrar).

Antes (cerrado):
```
┌─────────────────────────────────────────────────────┐
│  VENTA EN CURSO (ancho completo)                     │
│  ...líneas...                                        │
│                                              [ 🧺+ ] │ ← pestaña en el borde derecho
└─────────────────────────────────────────────────────┘
```

Después (abierto) — el mismo botón ahora vive en la costura entre los dos paneles:

```
┌───────────────────────────┬──┬───────────────────────────┐
│  VENTA EN CURSO            │🧺│  AGREGAR PRODUCTO          │
│  (carrito, más angosto)    │− │ 🔍 [ buscar... ]           │
│  ...líneas...               │  │ ─────────────────────────  │
│                              │  │ [foto] Café       ₡800    │
│                              │  │ ─────────────────────────  │
│                              │  │ [foto] Jugo       ₡900    │
│                              │  │ ─────────────────────────  │
│                              │  │ [foto] Gallo pinto ₡1500  │
│                              │  │ ─────────────────────────  │
│                              │  │           ...              │
│                              │  │                            │
│ [ recibí|cambio|total|Fin ] │  │        ✎*       📝†        │
└──────────────────────────────┴──┴───────────────────────────┘
  Lista vertical, NO cuadrícula — a diferencia de la Ventana 1, aquí el
  contexto ya es "estoy agregando al carrito que veo al lado", una lista
  angosta escanea más rápido que una cuadrícula comprimida en ese ancho.
  * ✎ "producto nuevo al vuelo" — solo Gerente (oculto/deshabilitado para Registradora)
  † 📝 "línea libre" — propuesta de ícono, a confirmar (ver Pendientes)
  🔍 sigue el mismo ranking nombre > categoría de la Ventana 1 ([0018](../decisiones/0018-orden-y-busqueda-de-producto.md));
     la lista respeta el orden Alfabético/Precio/Categoría configurado en Configuración.
```

Tocar un producto (toque simple) → se agrega al carrito, cantidad 1. Mantener presionado → selección múltiple:

```
│ ─────────────────────────  │
│ ✓ [foto] Café       ₡800   │  ← seleccionado, resaltado con acento
│ ─────────────────────────  │
│   [foto] Jugo       ₡900   │
│ ─────────────────────────  │
│ ✓ [foto] Gallo pinto ₡1500 │  ← seleccionado
│ ─────────────────────────  │
│   🔍   ✎*   📝†  [ + Agregar (2) ]  │  ← aparece solo en modo selección
```

---

## Ventana 3 — CRUD de Producto

```
┌───────────────────────────────────────────────────────────┐
│  🔍 [ buscar producto o categoría... ]         [ + Nuevo ]*│
│  PRODUCTOS  (agrupados por categoría si ese es el orden activo — 0018)
│ ┌─────────────────────────────────────────────────────┐   │
│ │ [foto]  Café                ₡800      [✎]  [⛔]      │   │
│ ├─────────────────────────────────────────────────────┤   │
│ │ [foto]  Gallo pinto         ₡1500     [✎]  [⛔]      │   │
│ ├─────────────────────────────────────────────────────┤   │
│ │ [foto]  Café viejo (descont.) ₡800    [✎]  [🗑 gris] │   │
│ ├─────────────────────────────────────────────────────┤   │
│ │ [foto]  Prueba x2 (descont.)  ₡100    [✎]  [🗑]*     │   │
│ └─────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────┘
  [+ Nuevo] — solo Gerente.
  [⛔] descontinuar — Gerente. En Registradora no aparece (solo ✎).
  [🗑] purgar — solo Gerente, y solo habilitado (color, no gris) cuando:
       descontinuado + 0 ventas asociadas + todos los dispositivos sincronizados.
       Al tocarlo SIEMPRE pide confirmación aparte (acción irreversible, 0015) —
       nunca borra al primer tap, ni siquiera para Gerente.
```

---

## Ventana 4 — Reportes *(revisada — confirmada como reporte unificado, interactivo y exportable)*

Jerarquía por tamaño: el total del período consultado es el bloque más grande (hero), el desglose por turno son celdas pares más chicas, el ranking va debajo.

**Nivel 1 (vista por defecto para el rango seleccionado, ej. Día = hoy):**

```
┌───────────────────────────────────────────────────────────┐
│ ┌───────────────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│ │                    │ │ Mañana  │ │ Tarde   │ │ Noche   │ │  ← tocar cualquiera
│ │   HOY: ₡45,000     │ │ ₡12,000 │ │ ₡20,000 │ │ ₡13,000 │ │     hace drill-down
│ │      (hero)        │ │         │ │         │ │         │ │     (nivel 2, abajo)
│ └───────────────────┘ └─────────┘ └─────────┘ └─────────┘ │
│ ┌─────────────────────────────┬─────────────────────────┐ │
│ │  Más vendidos    ◄ desliza ►│  Menos vendidos ◄desliza► │ │  ← listas deslizantes,
│ │  1. Café          (42)      │  1. Té frío        (2)    │ │     sin exportar por ahora
│ │  2. Gallo pinto   (30)      │  2. Jugo naranja   (5)    │ │
│ └─────────────────────────────┴─────────────────────────┘ │
│  [ Día ] [ Semana ] [ Mes ] [ Año ]           [ 📤 Exportar ]│
└───────────────────────────────────────────────────────────┘
```

**Nivel 2 (tras tocar "Tarde", por ejemplo) — desglose de ese turno:**

```
┌───────────────────────────────────────────────────────────┐
│ ← Volver a Hoy                                             │
│ ┌─────────────────────────────────────────────────────┐   │
│ │        TARDE (12:00–17:59): ₡20,000      (hero)      │   │
│ └─────────────────────────────────────────────────────┘   │
│ ┌─────────────────────────────────────────────────────┐   │
│ │ 14:03   Café + Gallo pinto              ₡2,300       │   │ ← mantener presionado
│ ├─────────────────────────────────────────────────────┤   │    = exportar esta
│ │ 15:47   Jugo natural                    ₡900         │   │    fila a PDF, directo
│ ├─────────────────────────────────────────────────────┤   │
│ │            ...                                        │   │
│ └─────────────────────────────────────────────────────┘   │
│                                               [ 📤 Exportar ]│
└───────────────────────────────────────────────────────────┘
```

**Exportar (botón `📤`, no oculto tras long-press)** — abre una elección corta de formato, sin más pasos:

```
      ┌───────────────────┐
      │   📄  PDF         │
      │   📊  CSV         │
      └───────────────────┘
```

Dos mecanismos de exportación, deliberadamente distintos:

- **Mantener presionado un ítem específico** (una fila del desglose, un turno, un día en una lista) → exporta **directo a PDF**, sin preguntar formato — es la acción rápida de "esto puntual, ya".
- **Botón `📤 Exportar`** (visible siempre, no escondido) → exporta el **período completo actualmente visible** (el día/semana/mes/año seleccionado en el selector), preguntando el formato (PDF o CSV) porque es una acción más deliberada.

Los "tops" (más/menos vendidos) son solo deslizantes por ahora — exportarlos queda fuera de alcance hasta que se pida explícitamente.

Registradora: mismo layout e interactividad, selector reducido a `[ Día actual ] [ Semana actual ]` (sin Mes/Año — `Reports.feature`).

*Nota de implementación (no bloquea el diseño):* generar PDF necesita un paquete como `pdf` + `printing`; CSV es texto plano, no necesita librería especial. Ninguno se agregó todavía a `pubspec.yaml` — Reportes sigue siendo un placeholder en el scaffold.

---

## Ventana 5 — Configuración *(confirmada: grid de tiles, deslizante para crecer a futuro)*

Pantalla de uso raro — tolera ícono + etiqueta corta (no compite con el criterio "sin leer" de las pantallas de venta). **Confirmado por el usuario**: la cuadrícula de tiles es un buen formato porque agregar una opción nueva a futuro es trivial (una celda más) — con la condición de que el grid sea **deslizante** (scroll vertical), no de tamaño fijo, mismo principio que "si hay más funciones que espacio, se navega deslizando" ya usado en el rail del Dashboard. Así la pantalla nunca se satura por más que se agreguen opciones con el tiempo.

```
┌───────────────────────────────────────────────────────────┐
│ ┌───────────────┐ ┌───────────────┐ ┌───────────────────┐ │
│ │      🔒        │ │      💾        │ │        📥        │ │
│ │    Cambiar     │ │   Exportar     │ │     Restaurar     │ │
│ │   contraseña   │ │    backup      │ │      backup       │ │
│ └───────────────┘ └───────────────┘ └───────────────────┘ │
│ ┌───────────────┐ ┌───────────────┐ ┌───────────────────┐ │
│ │      📶        │ │      ℹ️        │ │        🚪        │ │
│ │   Estado de    │ │   Acerca de    │ │   Cerrar sesión   │ │
│ │ sincronización │ │                │ │                    │ │
│ └───────────────┘ └───────────────┘ └───────────────────┘ │
│ ┌─────────────────────────────────────────────────────┐   │
│ │  Orden de productos                                  │   │
│ │  ( ) Alfabético    ( ) Precio    (●) Categoría        │   │
│ └─────────────────────────────────────────────────────┘   │
│ ┌─────────────────────────────────────────────────────┐   │
│ │  Venta unificada (Ventana 1 + 2 en una sola)         │   │
│ │  ( ) Desactivada (por defecto)   ( ) Activada        │   │
│ └─────────────────────────────────────────────────────┘   │
│                    ▼ desliza para más opciones ▼           │
└───────────────────────────────────────────────────────────┘
```
`🚪 Cerrar sesión` — encontrado como hueco al trazar el flujo completo (ver [mapa-de-flujo.md](mapa-de-flujo.md)), ningún boceto anterior tenía dónde cerrar sesión.
`Orden de productos` — [decisión 0018](../decisiones/0018-orden-y-busqueda-de-producto.md), afecta Ventana 1, el panel de agregar producto de la Ventana 2, y Ventana 3.
`Venta unificada` — toggle opcional, desactivado por defecto. Ver discusión completa más abajo en "Observación" — fusionar Ventana 1 y 2 podría ser útil para quien quiera menos pantallas, pero por defecto se deja el flujo separado (más simple de entender para alguien sin experiencia en tecnología). Como ambas ya comparten `VentaEnCursoNotifier`, implementar este toggle más adelante no requiere cambios de arquitectura — es una decisión de navegación, no de datos.

---

## Pendientes / a confirmar (no resueltos en esta pasada)

- **Ícono de "línea libre"** (Ventana 2): propuse 📝, distinto de ✎ ("producto nuevo al vuelo"). Es una elección subjetiva — confirmar o cambiar.
- **Layout de teléfono para las Ventanas 1–5**: pospuesto a propósito hasta que la base de escritorio/tablet esté completa e implementada — no es una omisión, es orden de trabajo decidido.
- **Reportes y Configuración** son primera propuesta libre, no vienen de una descripción tuya explícita como las Ventanas 1–3 — son las que más probablemente necesiten ajuste en la siguiente ronda.

## Ventana 1 + 2 — resuelto: separadas por defecto, unificación como toggle opcional

Tu razonamiento es acertado y coincido con él: fusionar de entrada obligaría a todos a lidiar con una pantalla más "inteligente" (y potencialmente más verbosa, ej. si por categorías) para ahorrar un paso — un costo real de carga cognitiva para alguien sin experiencia en tecnología, a cambio de un beneficio que solo algunos usuarios van a valorar. Dejarlo como **toggle opcional en Configuración, desactivado por defecto** (agregado arriba en el boceto de Ventana 5) resuelve esto sin cerrar la puerta: quien quiera menos pantallas lo activa, quien no, ni se entera de que la opción existe.

Ventaja técnica adicional que confirma que esto es seguro de posponer: Ventana 1 y Ventana 2 **ya comparten `VentaEnCursoNotifier`** en el scaffold — el toggle es una decisión de navegación/presentación, no de datos. Implementarlo más adelante no requiere tocar el modelo de Venta ni sus DAOs.

Un matiz honesto para cuando se implemente: el flujo unificado en sí (tocar un producto abre el overlay rápido; agregar un segundo producto antes de completar escala a modo carrito) todavía no tiene un diseño detallado — es una idea, no una especificación. Esa pantalla necesitará su propia pasada de diseño cuando llegue el momento, el toggle no resuelve eso por sí solo.

## Estado de implementación en Flutter (2026-07-29)

Las 6 fases de la pasada de refinamiento visual, cada una verificada con `flutter analyze`/`flutter test`/`flutter build linux --debug` + navegación real por teclado con captura de pantalla:

- **Fase 0** — fundación: `lib/core/theme/bento_theme.dart` (tokens `BentoSpacing`/`BentoRadius`, escala tipográfica, theming de componentes compartidos), `bento_ink.dart` (ripple granulado, `BentoGrainSplash`), `bento_corner_notice.dart` (notificación de esquina).
- **Fase 1** — Login con los tokens aplicados.
- **Fase 2** — Ventana 1 (grid + overlay de cobro) con tokens y notificación de esquina.
- **Fase 3** — Ventana 2: fila de carrito (`_FilaLineaVenta`) con el mismo lenguaje visual que la tarjeta de producto.
- **Fase 4** — Ventana 3: fila de producto (`_FilaProducto`), misma pieza reutilizada por tercera vez; crear/editar/descontinuar/purgar ahora sí notifican.
- **Fase 5** — Ventana 4: jerarquía de tamaño real entre el hero y los tiles de turno (`displaySmall`, 40px, contra `bodyLarge`/`titleMedium` de los tiles).
- **Fase 6** — Ventana 5: grid de tiles deslizante (`_TileConfiguracion`), reemplaza el `ListView` de `ListTile`s.

No cubierto por esta pasada (fuera de alcance, no un olvido): layout de teléfono, exportar PDF/CSV en Reportes, ranking de búsqueda con tolerancia a errores ortográficos (0018), ícono vectorial propio para "línea libre".

### Segunda pasada — feedback puntual post-implementación (2026-07-29)

Tras probar la primera pasada, el usuario dio 8 puntos de feedback concretos, resueltos en fases A–F (ver commits) más un fix independiente de foco de teclado. Decisiones y convenciones nuevas documentadas en [0023](../decisiones/0023-refinamiento-bento-post-implementacion.md):

- **Fase A** — `DashboardShell` usa `IndexedStack` (evita el parpadeo de reconstruir cada pantalla al cambiar de tab) + `ExcludeFocus` (evita que el teclado se fugue a pantallas ocultas).
- **Fase B** — Tema Claro/Oscuro/Sistema (`ModoTema`, `buildBentoTheme(..., brightness:)`, `MaterialApp.darkTheme`/`themeMode`).
- **Fase C** — Ventana 2: separador real entre carrito y panel de agregar producto, botón de toggle reubicado al fondo (no centrado), buscador movido a una barra inferior unificada con cascada invertida (`ListView(reverse: true)`).
- **Fase D** — Ventana 3: buscador + botón "Nuevo" unificados en una barra inferior (reemplaza `AppBar`+`FloatingActionButton`), misma cascada invertida.
- **Fase E** — Ventana 4: las 3 tarjetas de turno vuelven a ser celdas individuales (no fusionadas — ver matiz en 0023), ahora con `IntrinsicHeight`+`stretch` para llenar la misma altura que el hero.
- **Fase F** — Ventana 5: rediseño completo a grid de 9 tiles (incluye Orden/Acento/Modo de tema) + panel de detalle fijo debajo, sin ningún `showDialog` en la pantalla (`cambiar_contrasena_panel.dart`, `tiketback_panels.dart`, `tiketdata_panel.dart`).

**Pendiente explícito para después de cerrar el resto del feedback puntual**: auditoría de diseño responsive (adaptación correcta a distintos tamaños de pantalla) — mencionado por el usuario, todavía no iniciado.

## Checklist

- [x] Login / Setup
- [x] Dashboard — variante panel lateral (pantalla ancha)
- [x] Dashboard — variante pestañas inferiores (pantalla angosta)
- [x] Ventana 1 — Venta Rápida (grid de productos + overlay de cobro)
- [x] Ventana 2 — Panel de Venta (carrito + panel de agregar producto)
- [x] Ventana 3 — CRUD de Producto
- [x] Ventana 4 — Reportes (primera propuesta, a validar)
- [x] Ventana 5 — Configuración (primera propuesta, a validar)
- [x] Layout de teléfono (contenido interno de cada ventana) — decisión 0026
