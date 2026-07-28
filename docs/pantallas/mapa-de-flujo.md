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

**2. Ventana 1 y Ventana 3 no tienen buscador/filtro cuando el catálogo crece.** `categoria` se diseñó explícitamente "para navegación/búsqueda al armar una venta" (ver `docs/arquitectura/datos.md`), pero el grid de Venta Rápida y la lista de CRUD Producto son planos, sin usar esa categoría para nada visual todavía. Con pocos productos no se nota; si el catálogo crece, escanear un grid plano deja de ser instantáneo. Candidato natural: chips de categoría (íconos, no texto) arriba del grid, coherente con el lenguaje no-textual ya establecido — no lo agregué al boceto porque es una decisión de diseño nueva, no una corrección de algo ya descrito.

**3. Hallazgo real, no solo de UI — roles y sync pueden estar en conflicto.** El Login describe elegir rol (Gerente/Registradora) **cada vez** que se inicia sesión tras un logout, no solo en el primer setup del dispositivo. Pero la topología de sync ([decisión 0007](../decisiones/0007-topologia-sync.md)) asume que un dispositivo pertenece de forma **estable** a "la red Gerente" o "la red Registradora". Si el rol se puede re-elegir en cada login, un mismo dispositivo podría cambiar de red de sync entre una sesión y otra — eso no estaba contemplado al diseñar 0007.

Hay que aclarar cuál de las dos es la intención real:
- **(a) El rol se fija una sola vez, en el primer setup del dispositivo.** Un logout posterior solo debería pedir contraseña, sin volver a elegir rol — el dispositivo "ya sabe" que es de Gerente o de Registradora. Esto mantiene 0007 intacto tal como está.
- **(b) El rol se puede re-elegir en cada login**, porque el dispositivo se comparte entre un Gerente y una Registradora (ej. una sola tablet en el local). En ese caso hay que revisar 0007: la pertenencia a "red Gerente"/"red Registradora" ya no puede ser una propiedad fija del dispositivo, sino de la sesión activa en ese momento.

No lo resolví unilaterally porque cambia una decisión ya aceptada (0007) según cuál sea la respuesta.

**4. Feedback de acciones sobre Producto no está definido.** Venta tiene su notificación no intrusiva en esquina; crear/editar/descontinuar/purgar un Producto no tienen un patrón de feedback explícito todavía — asumo que debería ser el mismo lenguaje (notificación de esquina) para mantener consistencia, pero no estaba dicho.

**5. Cierre del panel "agregar producto" (Ventana 2) sin definir.** ¿Se cierra solo tocando la misma pestaña de nuevo, o también al tocar fuera del panel? Detalle menor, no bloquea nada.

---

## Prioridad sugerida para resolver

1. **Hallazgo #3** (rol por dispositivo vs. por sesión) — es el único que toca una decisión de arquitectura ya aceptada, conviene cerrarlo antes de avanzar más en pantallas.
2. Hallazgo #2 (buscador/categoría) — afecta la usabilidad real si el catálogo crece, vale la pena decidir antes del scaffold aunque no sea urgente para un catálogo chico inicial.
3. Hallazgos #4 y #5 — de bajo riesgo, se pueden resolver sobre la marcha al implementar.
