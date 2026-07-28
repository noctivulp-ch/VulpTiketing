# Mapa de Flujo General

Ver también: [flujo-descripcion](flujo-descripcion.md) · [prototipos-ascii](prototipos-ascii.md)

Trazado de navegación entre pantallas + recorridos de usuario reales, para evaluar qué tan bien funciona el diseño antes de tocar código. No es un documento de decisiones — es una auditoría del flujo ya diseñado.

## Mapa de navegación

```
                    ┌───────────────┐
                    │  Login/Setup  │  (solo primera vez o tras logout)
                    └───────┬───────┘
                            │ elegir rol + contraseña
                            ▼
                    ┌───────────────────────────────────┐
                    │            Dashboard                │  (persiste mientras haya sesión)
                    │  🛒 · 🧺 · 📦 · 📊 · ⚙            │
                    └───┬─────┬─────┬─────┬─────┬────────┘
                        │     │     │     │     │
              ┌─────────┘     │     │     │     └─────────┐
              ▼               ▼     ▼     ▼               ▼
        Venta Rápida    Panel de  CRUD   Reportes   Configuración
        (🛒)            Venta(🧺) (📦)    (📊)        (⚙)
              │               │                             │
              ▼               ▼                             ▼
        overlay cobro   panel "agregar                🚪 Cerrar sesión
        (1 producto)    producto" (lateral)                 │
                                                              ▼
                                                        vuelve a Login
```

## Recorridos trazados

### 1 — Venta de un solo producto (el caso más frecuente)

Dashboard (llega a 🛒 por defecto) → tap producto → overlay (cantidad=1 y precio=base ya puestos) → escribe monto recibido → (400ms) cambio aparece solo → tap Completado → notificación esquina → vuelve al grid.

**3 acciones del usuario** (tap producto, escribir monto, tap completado). Muy alineado con el objetivo de agilidad — este es el camino que se recorre más veces al día y es el más corto de todos.

### 2 — Venta de varios productos

Dashboard → tap 🧺 → tap pestaña "agregar producto" → tap Café, tap Gallo, tap Jugo (se agregan una a una) → cerrar el panel → revisar carrito, editar una línea si hace falta (✎) → escribir monto recibido → tap Finalizar.

≈7-8 acciones para 3 productos — razonable, y consistente con "no perseguir 3 clicks a toda costa": cada paso es reconocible aunque no sea el mínimo posible.

### 3 — Línea libre (caso custom de un solo uso)

Dashboard → 🧺 → agregar producto → tap 📝 (línea libre) → escribe nombre + precio → se agrega como línea normal → sigue como venta normal.

### 4 — Gerente descontinúa y purga un producto duplicado

Dashboard → 📦 → ubicar el producto → tap ⛔ (descontinuar) → confirma → *(tiempo después, ya sincronizado)* → tap 🗑 (purgar, ahora habilitado) → confirmación aparte (irreversible) → desaparece de la lista.

### 5 — Gerente revisa reportes de la semana

Dashboard → 📊 → ve total de hoy + turnos + ranking → tap "Semana" → la vista se actualiza con el nuevo rango.

### 6 — Cerrar sesión / cambiar de quién está usando el dispositivo

Dashboard → ⚙ → tap "Cerrar sesión" → vuelve a Login → *(ver hallazgo #3 abajo — no está claro qué pide el Login en este punto)*.

---

## Qué funciona bien

- **La venta de 1 producto es genuinamente rápida** (3 acciones) — coherente con que es el uso más repetido del día.
- **Navegación siempre predecible**: mismo ícono, mismo lugar, en las 5 ventanas — cero necesidad de leer para moverse.
- **Lo irreversible no compite con la velocidad**: Purgar pide confirmación aparte, pero como es una acción rara (no parte del flujo diario), no le resta agilidad a lo demás.

## Fricciones y huecos encontrados al trazar el flujo

**1. Faltaba dónde cerrar sesión.** Ningún boceto lo incluía. Lo agrego ahora como tile en Configuración (`🚪 Cerrar sesión`) — es el lugar más natural y no rompe nada del resto del diseño.

**2. ~~Ventana 1 y Ventana 3 no tienen buscador/filtro~~ — Resuelto ([decisión 0018](../decisiones/0018-orden-y-busqueda-de-producto.md)).** Agregado un setting de orden en Configuración (Alfabético/Precio/Categoría, con agrupación visual y separadores en modo Categoría) aplicado consistentemente a Ventana 1, 2 y 3, más un buscador en cada una con ranking nombre de producto > nombre de categoría (tolerante a errores ortográficos). Ver bocetos actualizados en `prototipos-ascii.md`.

**3. ~~Roles y sync pueden estar en conflicto~~ — Resuelto.** "Cerrar sesión" no es una acción rutinaria (no se dispara al cerrar la app), es específicamente para cuando un dispositivo compartido necesita cambiar de rol — evento infrecuente pero real. Esto no entra en conflicto con la topología de sync ([decisión 0007](../decisiones/0007-topologia-sync.md)): la pertenencia a "red Gerente"/"red Registradora" ya era una propiedad derivada en vivo del rol activo (no una lista fija), así que un cambio de rol es, para el algoritmo de elección de orquestador ya diseñado, el mismo tipo de evento que un dispositivo que aparece/desaparece de un grupo — se resuelve solo, sin rediseñar nada. Ver el addendum agregado a 0007.

**4. Feedback de acciones sobre Producto no está definido.** Venta tiene su notificación no intrusiva en esquina; crear/editar/descontinuar/purgar un Producto no tienen un patrón de feedback explícito todavía — asumo que debería ser el mismo lenguaje (notificación de esquina) para mantener consistencia, pero no estaba dicho.

**5. Cierre del panel "agregar producto" (Ventana 2) sin definir.** ¿Se cierra solo tocando la misma pestaña de nuevo, o también al tocar fuera del panel? Detalle menor, no bloquea nada.

---

## Prioridad sugerida para lo que queda

1. Hallazgos #4 y #5 — de bajo riesgo, se pueden resolver sobre la marcha al implementar.
