# Flujo de Pantallas — Descripción (Fase 1)

Ver también: [prototipos-ascii](prototipos-ascii.md) (Fase 2, aún vacía) · [../funciones/ventas](../funciones/ventas.md) · [../arquitectura/gestion-estado](../arquitectura/gestion-estado.md)

**Fase 1 de 2.** Este documento describe el flujo en texto — qué pantallas existen, qué se ve, qué acciones hay y a dónde navega cada una — para validar que las features estén completas antes de comprometer diseño visual. La Fase 2 (composición visual concreta) se hace con la skill de diseño bento del usuario y vive en [prototipos-ascii.md](prototipos-ascii.md); no se invoca esa skill todavía.

## Alcance de esta descripción

- Describe principalmente el rol **Registradora** en un dispositivo de pantalla grande (tablet/PC) — es el caso de uso más intensivo de UI (venta rápida repetida durante el día).
- **Gerente** reutiliza las mismas pantallas con permisos elevados, ya definidos en `Operations.feature`/`Reports.feature` (CRUD completo de Producto, reportes sin restricción de rango). No se describen diferencias visuales específicas de Gerente todavía — probablemente ninguna, más allá de qué botones/opciones aparecen habilitados.
- No se detalla aún el layout específico para pantallas pequeñas (teléfono), más allá del comportamiento adaptativo general del Dashboard (abajo).

## Login / Setup

Pantalla de configuración inicial — se ve **solo la primera vez o después de desloguear**, no en cada apertura de la app:

1. Dos íconos para elegir el tipo de dispositivo/rol: Gerente o Registradora (selección única).
2. Pide contraseña (la contraseña local del dispositivo — ver [decisión 0011](../decisiones/0011-credenciales-almacenamiento-nativo.md)).
3. Al autenticar, mantiene la sesión — no vuelve a pedir credenciales hasta que alguien cierre sesión explícitamente.

## Dashboard (shell de navegación)

Layout de dos paneles, adaptativo según ancho de pantalla:

- **Pantallas anchas** (tablet/PC): panel lateral izquierdo con las pestañas de navegación entre funciones.
- **Pantallas angostas**: panel inferior con las mismas pestañas.
- Si hay más funciones (pestañas) que espacio disponible, se navega deslizando (scroll horizontal) entre ellas.
- **Panel derecho** (o el resto de la pantalla, según variante): contenido de la función/ventana seleccionada.

Las "Ventanas" 1–5 de abajo son el contenido que se muestra en este panel derecho al seleccionar cada pestaña.

---

## Ventana 1 — Venta Rápida

Pensada para el caso común: vender uno o pocos productos sin construir un carrito completo.

- Grid grande con **todos los productos**: foto, nombre, precio.
- Tocar un producto abre un **overlay** (modal flotante) con:
  - **Cantidad** — cuántas unidades de ese producto.
  - **Precio** — precargado con el precio base (placeholder), editable — mismo comportamiento ya definido en [ventas.md](../funciones/ventas.md) y `linea_venta.precio_aplicado`.
  - **Cambio** — mismo control que el de la Ventana 2 (ver abajo): campo de texto donde se escribe el monto recibido; tras un par de segundos sin escribir, se calcula el cambio a devolver automáticamente.
  - **Completado** — botón para finalizar esta venta de un solo producto.
- Al finalizar: se muestra una **notificación no intrusiva en una esquina** (éxito o error) y el overlay se cierra.

Esto crea una Venta de una sola línea (mismo modelo de datos que la Ventana 2, solo que con una ruta de UI más corta para el caso de un producto).

## Ventana 2 — Panel de Venta (carrito completo)

Para ventas de varios productos. Layout:

```
[ rectángulo amplio: líneas de la venta en curso ]
[ barra inferior: cambio | total | finalizar ]
[ botón/pestaña: agregar producto ]
```

- **Rectángulo de líneas**: cada producto agregado se muestra como un rectángulo con dos botones integrados — **editar** (precio/cantidad/nota de esa línea) y **eliminar** (quita la línea del carrito; no confundir con "descontinuar" un Producto del catálogo — ver Ventana 3).
- **Barra inferior**, según el ejemplo dado:
  ```
  [ Text | {cambio} |                    | {total} | BTN ]
  ```
  - `Text` — campo de texto donde el cajero escribe el monto recibido del cliente.
  - `{cambio}` — resultado calculado automáticamente tras ~2-3 segundos sin escribir (no es un botón de "calcular", es un campo reactivo — nota: el mensaje original lo mencionaba como "botón cuadrado" y luego como campo de texto con debounce; asumí el campo de texto con debounce como la versión correcta porque es la que se describió con más detalle — **confirmar**).
  - `{total}` — total de la venta en curso (suma de líneas).
  - `BTN` — **finalizar venta**: al presionar, muestra una notificación no intrusiva de éxito o error.
- **Botón "agregar producto"**: estilo pestaña, el botón mismo se comporta como un toggle flotante, pero el panel que abre **no es un overlay** — es un panel persistente que ocupa parte del lado derecho de la pantalla, con:
  - Listado de productos disponibles.
  - Botón de **buscar** (lupa).
  - Botón de **agregar producto nuevo al vuelo** (lápiz) — crea un Producto nuevo sin salir del flujo de venta. **Debe estar restringido a Gerente**, igual que el resto de Create en `Operations.feature` (Registradora no puede crear productos) — punto a confirmar al implementar, no estaba explícito en el mensaje original pero se sigue directamente de la feature existente.
  - Tocar un producto (toque simple) lo agrega a la venta como una línea nueva.
  - Mantener presionado entra en modo selección múltiple; aparece un botón **"+"** junto a los otros dos, para agregar todos los productos seleccionados de una vez.
  - **Línea libre** ([decisión 0016](../decisiones/0016-linea-libre-en-venta.md)): además de elegir un producto del catálogo, debe haber una forma de agregar una línea sin catálogo — nombre y precio escritos a mano, para casos de un solo uso (ej. un descuento puntual para un cliente específico) que nunca deberían ensuciar el inventario de Producto. Falta decidir el ícono/ubicación exacta de este botón dentro de la barra existente (buscar / agregar nuevo / línea libre) — se resuelve en la Fase 2 (prototipos visuales).

## Ventana 3 — CRUD de Producto

Listado de productos con las acciones: **agregar**, **editar**, **descontinuar**, y **purgar** (borrado físico real) — esto corresponde 1:1 con `Operations.feature` y el ciclo de vida de `ProductoNotifier` en [gestion-estado.md](../arquitectura/gestion-estado.md).

**Purgar** ([decisión 0015](../decisiones/0015-purgar-producto-borrado-fisico-condicional.md)) resuelve el punto que planteó el usuario sobre acumulación de productos duplicados/creados por error que nunca se van a usar: solo está disponible para Gerente, y solo habilitado cuando el producto ya está descontinuado, tiene cero ventas asociadas, y se confirma que todos los dispositivos conocidos están sincronizados (la UI debe deshabilitar el botón mientras esa condición no se cumpla, con un mensaje indicando por qué). Para casos custom de un solo uso (ej. un descuento puntual para un cliente específico) que nunca deberían haber sido un Producto de catálogo en primer lugar, ver la **línea libre** en la Ventana 2 — evita el problema desde la raíz en vez de crear y purgar después.

## Ventana 4 — Reportes

Sin describir en detalle — sigue la estética general ya estipulada para el resto de la app. Contenido funcional ya definido en `Reports.feature` y [reportes.md](../funciones/reportes.md).

## Ventana 5 — Configuración

Sin describir en detalle — sigue la estética general ya estipulada. Debe incluir al menos: cambio de contraseña local del dispositivo (ver [roles-y-auth.md](../funciones/roles-y-auth.md)) y, a futuro, exportar/restaurar backup (ver [backup.md](../funciones/backup.md)).

---

## Pendientes / a confirmar

- Ícono/ubicación exacta del botón de "línea libre" en la barra de agregar producto (Ventana 2) — se resuelve en Fase 2.
- Si el control de "cambio" en la barra inferior es puramente un campo de texto reactivo (asumido aquí) o combina también un botón — confirmar.
- Si "agregar producto nuevo al vuelo" desde el panel de venta debe restringirse a Gerente (asumido aquí, por consistencia con `Operations.feature`) — confirmar.
- Si al mantener presionado y seleccionar varios productos, cada uno se agrega con cantidad 1 por defecto (asumido) o pide cantidad antes de agregar.
- Layout específico para pantalla pequeña (teléfono) — no descrito todavía.
- Diferencias visuales (si las hay) entre Gerente y Registradora más allá de qué botones están habilitados — no descrito todavía.
