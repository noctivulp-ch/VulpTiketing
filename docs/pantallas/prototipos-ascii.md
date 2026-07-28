# Prototipos ASCII — Fase 2

Ver también: [flujo-descripcion](flujo-descripcion.md) (Fase 1, base funcional)

Diseño bento-box (skill `design:bento-design`). Estos son bocetos para **iterar**, no un diseño final — cada bloque de código es una propuesta de layout, no una implementación literal en Flutter.

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
| Radio de esquina | 12px (celdas normales), 16px (celdas hero) |
| Acento | un solo color, reservado para la acción primaria de cada pantalla (Entrar, Finalizar venta, Completado, Guardar) |
| Acciones destructivas/irreversibles | nunca a un solo tap en la vista principal — siempre piden confirmación (Purgar, Revertir) |

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

```
┌─────────────────────────────────────────────────────┐
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

**Al tocar la pestaña "agregar producto"** — panel persistente al lado (no overlay), reduce el ancho del carrito:

```
┌───────────────────────────┬───────────────────────────────┐
│  VENTA EN CURSO            │  AGREGAR PRODUCTO             │
│  (carrito, más angosto)    │ ┌───────┐┌───────┐┌───────┐   │
│  ...líneas...               │ │ Café  ││ Jugo  ││ Gallo │   │
│                              │ └───────┘└───────┘└───────┘   │
│                              │ ┌───────┐┌───────┐┌───────┐   │
│                              │ │  ...  ││  ...  ││  ...  │   │
│                              │ └───────┘└───────┘└───────┘   │
│                              │                               │
│ [ recibí|cambio|total|Fin ] │   🔍      ✎*       📝†        │
└──────────────────────────────┴───────────────────────────────┘
  * ✎ "producto nuevo al vuelo" — solo Gerente (oculto/deshabilitado para Registradora)
  † 📝 "línea libre" — propuesta de ícono, a confirmar (ver Pendientes)
```

Tocar un producto (toque simple) → se agrega al carrito, cantidad 1. Mantener presionado → selección múltiple:

```
│ ┌───────┐┌───────┐┌───────┐   │
│ │✓ Café ││ Jugo  ││✓Gallo │   │  ← seleccionados, resaltados con acento
│ └───────┘└───────┘└───────┘   │
│   🔍      ✎*      📝†   [ + Agregar (2) ]  │  ← aparece solo en modo selección
```

---

## Ventana 3 — CRUD de Producto

```
┌───────────────────────────────────────────────────────────┐
│  PRODUCTOS                                     [ + Nuevo ]*│
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

## Ventana 4 — Reportes *(primera propuesta — no había descripción explícita, sigue la estética general; iterar si no calza)*

Jerarquía por tamaño: el total del período consultado es el bloque más grande (hero), el desglose por turno son celdas pares más chicas, el ranking va debajo.

```
┌───────────────────────────────────────────────────────────┐
│ ┌───────────────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│ │                    │ │ Mañana  │ │ Tarde   │ │ Noche   │ │
│ │   HOY: ₡45,000     │ │ ₡12,000 │ │ ₡20,000 │ │ ₡13,000 │ │
│ │      (hero)        │ │         │ │         │ │         │ │
│ └───────────────────┘ └─────────┘ └─────────┘ └─────────┘ │
│ ┌─────────────────────────────┬─────────────────────────┐ │
│ │  Más vendidos                │  Menos vendidos          │ │
│ │  1. Café          (42)       │  1. Té frío        (2)   │ │
│ │  2. Gallo pinto   (30)       │  2. Jugo naranja   (5)   │ │
│ └─────────────────────────────┴─────────────────────────┘ │
│  [ Día ]  [ Semana ]  [ Mes ]  [ Año ]   ← selector, íconos+label (uso raro, tolera texto)
└───────────────────────────────────────────────────────────┘
```
Registradora: mismo layout, selector reducido a `[ Día actual ] [ Semana actual ]` (sin Mes/Año — `Reports.feature`).

---

## Ventana 5 — Configuración *(primera propuesta — no había descripción explícita, sigue la estética general)*

Pantalla de uso raro — tolera ícono + etiqueta corta (no compite con el criterio "sin leer" de las pantallas de venta).

```
┌───────────────────────────────────────────────────────────┐
│ ┌───────────────┐ ┌───────────────┐ ┌───────────────────┐ │
│ │      🔒        │ │      💾        │ │        📥        │ │
│ │    Cambiar     │ │   Exportar     │ │     Restaurar     │ │
│ │   contraseña   │ │    backup      │ │      backup       │ │
│ └───────────────┘ └───────────────┘ └───────────────────┘ │
│ ┌───────────────┐ ┌───────────────┐                        │
│ │      📶        │ │      ℹ️        │                        │
│ │   Estado de    │ │   Acerca de    │                        │
│ │ sincronización │ │                │                        │
│ └───────────────┘ └───────────────┘                        │
└───────────────────────────────────────────────────────────┘
```

---

## Pendientes / a confirmar (no resueltos en esta pasada)

- **Ícono de "línea libre"** (Ventana 2): propuse 📝, distinto de ✎ ("producto nuevo al vuelo"). Es una elección subjetiva — confirmar o cambiar.
- **Layout de teléfono para las Ventanas 1–5**: solo se diseñó el shell del Dashboard adaptativo; el contenido interno de cada ventana en pantalla angosta (¿grid de menos columnas?, ¿el panel de "agregar producto" pasa a pantalla completa en vez de side-by-side?) no está resuelto — requiere una pasada aparte.
- **Reportes y Configuración** son primera propuesta libre, no vienen de una descripción tuya explícita como las Ventanas 1–3 — son las que más probablemente necesiten ajuste en la siguiente ronda.

## Observación (no es una pregunta bloqueante, es para que la evalúes)

Ventana 1 (Venta Rápida) y Ventana 2 (Panel de Venta) son, en el fondo, dos entradas al mismo trabajo ("registrar una venta"), una para un producto y otra para varios. Quedaron como dos tabs separadas en el Dashboard porque así se describieron en la Fase 1. Funciona tal cual está, pero si en algún momento querés simplificar aún más la navegación (menos íconos en el rail), se podría fusionar en una sola pantalla donde tocar un producto en el grid abre el overlay rápido, y agregar un segundo producto antes de completar transiciona automáticamente al modo carrito. No lo cambié porque no me lo pediste — lo dejo anotado por si te interesa explorarlo más adelante.

## Checklist

- [x] Login / Setup
- [x] Dashboard — variante panel lateral (pantalla ancha)
- [x] Dashboard — variante pestañas inferiores (pantalla angosta)
- [x] Ventana 1 — Venta Rápida (grid de productos + overlay de cobro)
- [x] Ventana 2 — Panel de Venta (carrito + panel de agregar producto)
- [x] Ventana 3 — CRUD de Producto
- [x] Ventana 4 — Reportes (primera propuesta, a validar)
- [x] Ventana 5 — Configuración (primera propuesta, a validar)
- [ ] Layout de teléfono (contenido interno de cada ventana)
