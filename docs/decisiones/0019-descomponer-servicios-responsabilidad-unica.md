# 0019 — Descomponer servicios grandes en clases de responsabilidad única

**Fecha:** 2026-07-28
**Estado:** Aceptada

## Contexto

Antes de iniciar el scaffold de código se revisó `docs/arquitectura/gestion-estado.md` para confirmar que la arquitectura sea genuinamente desacoplada y escalable — no solo "un Notifier por entidad de negocio, sin genéricos" ([0009](0009-cruds-independientes-por-entidad.md)), sino que **dentro** de cada Notifier/servicio la responsabilidad también sea estrecha. Se encontraron tres componentes que mezclaban tareas que conviene separar antes de escribir código, no después.

## Decisión

### 1. Sync se descompone en 4 piezas, no una

Lo que estaba descrito como un solo `SyncNotifier`/`SyncService` mezclaba: descubrimiento de red, elección de orquestador, resolución de conflictos fila-por-fila, y exposición de estado a la UI. Se separa en:

- **`DeviceDiscoveryService`** — solo mDNS: anuncia el rol activo de este dispositivo, descubre pares visibles. No sabe nada de LWW ni de qué se sincroniza.
- **`SyncGroupCoordinator`** — dado el conjunto de pares visibles y el rol propio, calcula el orquestador del grupo ([0007](0007-topologia-sync.md): UUID más bajo visible) y si el grupo tiene tareas pendientes. No sabe cómo se mezclan filas, solo coordina "quién y cuándo".
- **`RowSyncEngine`** — aplica LWW fila por fila entre dos conjuntos de datos, sin saber nada de red ni de topología: pura lógica de "dadas dos filas con el mismo `id`, cuál gana según `updated_at`". **Esta es la clase que [0017](0017-importar-datos-tiketdata-vs-tiketback.md) reutiliza** para importar `.tiketdata` — separarla es lo que hace ese reuso posible sin duplicar lógica de merge.
- **`SyncNotifier`** — la fachada Riverpod-facing: compone las tres anteriores y expone el estado (`idle`/`syncing`/`error`, y si todos los dispositivos están sincronizados, para [0015](0015-purgar-producto-borrado-fisico-condicional.md)) a la UI.

### 2. Listado/búsqueda de Producto se separa de su CRUD

`ProductoNotifier` mezclaba las operaciones de escritura con la lógica de presentación de listas (orden, búsqueda, ranking — [0018](0018-orden-y-busqueda-de-producto.md)). Se separa en:

- **`ProductoNotifier`** — solo escritura (crear, actualizar, descontinuar, purgar) + lectura base (lista completa filtrando `deleted_at`).
- **`ProductoQueryProvider`** — provider derivado, no un Notifier con estado propio: combina la lista base de `ProductoNotifier`, la preferencia de orden de `PreferenciasNotifier`, y un término de búsqueda local de pantalla, para producir la lista final ordenada/filtrada/rankeada. Nunca muta datos.

### 3. Identidad de dispositivo se separa de sesión/credenciales

`AuthNotifier`/`DeviceConfigNotifier` mezclaba sesión activa, verificación de contraseña, y generación de `device_id`. Se separa en:

- **`SesionNotifier`** — rol activo, login/logout (lo que la UI consulta para renderizar condicionalmente).
- **`CredencialesService`** — hashear/verificar la contraseña local (Argon2id, [0011](0011-credenciales-almacenamiento-nativo.md)). No sabe nada de sesión ni de UI.
- **`DeviceIdentityService`** — generar/leer el `device_id` persistente (detalle pendiente de [0007](0007-topologia-sync.md)). No sabe nada de contraseñas ni de rol.

### 4. Importación de datos se separa por tipo de archivo

`ImportExportNotifier` mezclaba dos formatos con mecanismos internos distintos (bundle cifrado vs. JSON + merge LWW). Se separa en:

- **`TiketbackService`/`TiketbackNotifier`** — exportar/restaurar el backup completo cifrado.
- **`TiketdataService`/`TiketdataNotifier`** — exportar/importar el paquete de catálogo, reutilizando **`RowSyncEngine`** (mismo componente del punto 1) para el merge — no una copia de esa lógica.

## Alternativas descartadas

- Dejarlo como un Notifier grande por concern — funciona para un prototipo pequeño, pero sync es la parte más compleja del proyecto y mezclar sus responsabilidades dificulta testear cada pieza por separado.
- Fragmentar aún más (una clase por método) — sobre-ingeniería para el tamaño de este proyecto. "Una o pocas tareas" no significa una tarea por clase a cualquier costo.

## Consecuencias

- `docs/arquitectura/gestion-estado.md` se reescribe reflejando esta descomposición.
- El scaffold de Flutter organiza `lib/` respetando estos límites desde el inicio, no como refactor posterior.
