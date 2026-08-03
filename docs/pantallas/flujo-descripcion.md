# Flujo de Pantallas — Descripción (Fase 1)

Ver también: [prototipos-ascii](prototipos-ascii.md) (Fase 2, en curso) · [../funciones/ventas](../funciones/ventas.md) · [../arquitectura/gestion-estado](../arquitectura/gestion-estado.md)

**Fase 1 de 2.** Este documento describe el flujo en texto — qué pantallas existen, qué se ve, qué acciones hay y a dónde navega cada una — para validar que las features estén completas antes de comprometer diseño visual. La Fase 2 (composición visual concreta, bento) vive en [prototipos-ascii.md](prototipos-ascii.md).

## Alcance de esta descripción

- Describe principalmente el rol **Registradora** en un dispositivo de pantalla grande (tablet/PC) — es el caso de uso más intensivo de UI (venta rápida repetida durante el día).
- **Gerente** reutiliza las mismas pantallas con permisos elevados, ya definidos en `Operations.feature`/`Reports.feature` (CRUD completo de Producto, reportes sin restricción de rango). No se describen diferencias visuales específicas de Gerente todavía — probablemente ninguna, más allá de qué botones/opciones aparecen habilitados.
- El layout específico para pantallas pequeñas (teléfono) queda **pospuesto a propósito** — se diseña recién cuando la base de escritorio/tablet esté completamente implementada y funcionando, no antes. El Dashboard ya contempla su variante adaptativa (pestañas inferiores) para ese momento.

## Login / Setup

Pantalla de configuración inicial — se ve **solo la primera vez o después de cerrar sesión explícitamente**, no en cada apertura de la app. Cerrar sesión no es una acción rutinaria: es específicamente para cuando un dispositivo compartido necesita cambiar de rol (ej. la misma tablet la usa a veces el Gerente, a veces la Registradora) — infrecuente, pero posible. Ver [decisión 0007, addendum](../decisiones/0007-topologia-sync.md) sobre por qué esto no entra en conflicto con la topología de sync.

1. Dos íconos para elegir el tipo de dispositivo/rol: Gerente o Registradora (selección única). Un botón explícito "← Volver" permite deshacer la selección y regresar a elegir rol — no basta con que la tarjeta ya elegida sea tocable de nuevo, tiene que ser una acción visible y reconocible.
2. Pide contraseña (**siempre existe una**: de fábrica por defecto, o la que se haya configurado después desde Configuración — nunca se "crea" una contraseña en este flujo, ver [decisión 0011, addendum](../decisiones/0011-credenciales-almacenamiento-nativo.md)).
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

- Grid grande con **todos los productos**: foto, nombre, precio. Orden y búsqueda: ver [decisión 0018](../decisiones/0018-orden-y-busqueda-de-producto.md) — respeta el modo Alfabético/Precio/Categoría configurado en Configuración (en modo Categoría, el grid se agrupa con separadores por categoría), y tiene su propia barra de búsqueda con ranking nombre > categoría.
- Tocar un producto abre un **overlay** (modal flotante) con:
  - **Cantidad** — cuántas unidades de ese producto, por defecto 1, editable (consistente con el `DEFAULT 1` de `linea_venta.cantidad` en el esquema).
  - **Precio** — precargado con el precio base (placeholder), editable — mismo comportamiento ya definido en [ventas.md](../funciones/ventas.md) y `linea_venta.precio_aplicado`.
  - **Cambio** — mismo control que el de la Ventana 2 (ver abajo): campo de texto donde se escribe el monto recibido; tras 400ms sin escribir, se calcula el cambio a devolver automáticamente. Sin botón adicional.
  - **SINPE** — casilla para marcar que se cobró por transferencia. Efectivo es lo normal y es lo que pasa si nadie la toca; el identificador de la transferencia **no** se pide acá, se anota después desde Reportes ([decisión 0032](../decisiones/0032-metodo-de-pago-en-la-venta.md)).
  - **Completado** — botón para finalizar esta venta de un solo producto.
- Al finalizar: se muestra una **notificación no intrusiva en una esquina** (éxito o error) y el overlay se cierra.

Esto crea una Venta de una sola línea (mismo modelo de datos que la Ventana 2, solo que con una ruta de UI más corta para el caso de un producto).

## Ventana 2 — Panel de Venta (carrito completo)

Para ventas de varios productos. Layout:

```
[ rectángulo amplio: líneas de la venta en curso ]
[ barra inferior: SINPE | recibí | cambio | total | finalizar ]
[ botón/pestaña: agregar producto ]
```

La casilla **SINPE** marca que se cobró por transferencia; efectivo es lo normal
y es lo que pasa si nadie la toca. El identificador se anota después, desde el
detalle de Reportes ([decisión 0032](../decisiones/0032-metodo-de-pago-en-la-venta.md)).
De pie ocupa su propia fila a lo ancho: es lo que hay que acordarse de marcar
**antes** de cobrar, y apretada en media celda se pasa por alto.

- **Rectángulo de líneas**: cada producto agregado se muestra como un rectángulo con dos botones integrados — **editar** (precio/cantidad/nota de esa línea) y **eliminar** (quita la línea del carrito; no confundir con "descontinuar" un Producto del catálogo — ver Ventana 3).
- **Barra inferior**, según el ejemplo dado:
  ```
  [ Text | {cambio} |                    | {total} | BTN ]
  ```
  - `Text` — campo de texto donde el cajero escribe el monto recibido del cliente.
  - `{cambio}` — resultado calculado automáticamente tras **400ms** sin escribir (debounce corto a propósito, buscando agilidad). No hay ningún botón asociado — el único botón real de esta barra es **finalizar venta** (confirmado por el usuario).
  - `{total}` — total de la venta en curso (suma de líneas).
  - `BTN` — **finalizar venta**: al presionar, muestra una notificación no intrusiva de éxito o error.
- **Botón "agregar producto"**: estilo pestaña, el botón mismo se comporta como un toggle flotante, pero el panel que abre **no es un overlay** — es un panel persistente que ocupa parte del lado derecho de la pantalla, con:
  - **Lista vertical** de productos disponibles (no cuadrícula como la Ventana 1 — el panel es más angosto y el contexto ya es "agregar al carrito", una lista escanea más rápido ahí), mismo orden/agrupación que el resto de la app ([decisión 0018](../decisiones/0018-orden-y-busqueda-de-producto.md)).
  - Botón de **buscar** (lupa) — ranking nombre > categoría, tolerante a errores ortográficos (0018).
  - Botón de **agregar producto nuevo al vuelo** (lápiz) — crea un Producto nuevo sin salir del flujo de venta. **Restringido a Gerente** (confirmado), igual que el resto de Create en `Operations.feature` — en la UI de Registradora este botón no debe aparecer (o debe verse deshabilitado).
  - Tocar un producto (toque simple) lo agrega a la venta como una línea nueva, con **cantidad 1 por defecto** (editable después desde el carrito).
  - Mantener presionado entra en modo selección múltiple; aparece un botón **"+"** junto a los otros dos, para agregar todos los productos seleccionados de una vez — **cada uno con cantidad 1 por defecto** (confirmado; editable después desde el carrito igual que cualquier línea).
  - **Línea libre** ([decisión 0016](../decisiones/0016-linea-libre-en-venta.md)): además de elegir un producto del catálogo, debe haber una forma de agregar una línea sin catálogo — nombre y precio escritos a mano, para casos de un solo uso (ej. un descuento puntual para un cliente específico) que nunca deberían ensuciar el inventario de Producto. Falta decidir el ícono/ubicación exacta de este botón dentro de la barra existente (buscar / agregar nuevo / línea libre) — se resuelve en la Fase 2 (prototipos visuales).

## Ventana 3 — CRUD de Producto

La imagen del producto se elige de un **banco de imágenes**
([decisión 0033](../decisiones/0033-banco-de-imagenes.md)): doce figuras
abstractas de fábrica —que no pesan y están siempre— más las fotos que se sumen
desde la galería o la cámara. Una foto agregada sirve para todos los productos
que la quieran.

Un producto **sin imagen elegida** no se ve con un icono genérico: se ve con una
figura derivada de su propio id, distinta para cada uno. En una lista larga, esa
figura se reconoce antes de leer el nombre.

El banco es local y **no viaja** en el backup ni en la sincronización: un
producto cuya foto no está en este aparato se ve con su figura, igual que uno que
nunca eligió imagen.

Listado de productos con las acciones: **agregar**, **editar**, **descontinuar**, y **purgar** (borrado físico real) — esto corresponde 1:1 con `Operations.feature` y el ciclo de vida de `ProductoNotifier` en [gestion-estado.md](../arquitectura/gestion-estado.md). Mismo orden/agrupación y búsqueda que el resto de la app ([decisión 0018](../decisiones/0018-orden-y-busqueda-de-producto.md)).

**Purgar** ([decisión 0015](../decisiones/0015-purgar-producto-borrado-fisico-condicional.md)) resuelve el punto que planteó el usuario sobre acumulación de productos duplicados/creados por error que nunca se van a usar: solo está disponible para Gerente, y solo habilitado cuando el producto ya está descontinuado, tiene cero ventas asociadas, y se confirma que todos los dispositivos conocidos están sincronizados (la UI debe deshabilitar el botón mientras esa condición no se cumpla, con un mensaje indicando por qué). Para casos custom de un solo uso (ej. un descuento puntual para un cliente específico) que nunca deberían haber sido un Producto de catálogo en primer lugar, ver la **línea libre** en la Ventana 2 — evita el problema desde la raíz en vez de crear y purgar después.

## Ventana 4 — Reportes

Reporte unificado (una sola pantalla, no una por rango), con dos propiedades confirmadas — ver bocetos en [prototipos-ascii.md](prototipos-ascii.md):

- **Interactivo**: tocar un bloque de turno (ej. "Tarde") hace drill-down al desglose de ese turno (ventas individuales); hay un "← Volver" para subir de nivel. Los "tops" (más/menos vendidos) son solo deslizantes, sin exportar por ahora.
- **Imprimible/exportable**: mantener presionado un ítem específico exporta directo a PDF (sin preguntar formato — acción rápida). Un botón `📤 Exportar` siempre visible exporta el período completo actualmente visible (día/semana/mes/año), preguntando PDF o CSV.

Contenido funcional (qué datos, permisos por rol) ya definido en `Reports.feature` y [reportes.md](../funciones/reportes.md).

## Ventana 5 — Configuración

Grid de tiles (una celda = una opción), confirmado como buen formato porque agregar una opción nueva a futuro es trivial — con la condición de que el grid sea **deslizante** (scroll vertical), no de tamaño fijo, para que nunca se sature. Debe incluir al menos: cambio de contraseña local del dispositivo (ver [roles-y-auth.md](../funciones/roles-y-auth.md)), exportar/restaurar `.tiketback` e importar/exportar `.tiketdata` (ver [backup.md](../funciones/backup.md)), cerrar sesión, el **orden de productos** (Alfabético/Precio/Categoría — [decisión 0018](../decisiones/0018-orden-y-busqueda-de-producto.md)), y el toggle opcional de **Venta unificada** (Ventana 1+2 en una sola pantalla — desactivado por defecto, ver [prototipos-ascii.md](prototipos-ascii.md) para la discusión completa).

---

## Pendientes / a confirmar

- Ícono/ubicación exacta del botón de "línea libre" en la barra de agregar producto (Ventana 2) — se resuelve en Fase 2.
- Layout específico para pantalla pequeña (teléfono) — no descrito todavía.
- Diferencias visuales (si las hay) entre Gerente y Registradora más allá de qué botones están habilitados — no descrito todavía.

## Resueltos en esta ronda

- **Cantidad por defecto**: 1 en todos los casos (venta rápida, agregar producto individual, selección múltiple).
- **Agregar producto nuevo al vuelo**: restringido a Gerente.
- **Control de "cambio"**: exclusivamente un campo de texto reactivo, debounce de 400ms (agilidad ante todo), sin botón adicional. El único botón real de la barra inferior es "finalizar venta".
