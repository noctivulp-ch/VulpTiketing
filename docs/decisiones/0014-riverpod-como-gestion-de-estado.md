# 0014 — Riverpod como gestión de estado

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

`Architecture.feature` exige que la gestión de estado esté "estrictamente desacoplada de la UI", mencionando Riverpod o BLoC como ejemplos, sin cerrar cuál. Había que elegir uno antes del scaffold de Flutter.

## Opciones consideradas

**Riverpod** — providers legibles sin `BuildContext`, seguridad de tipos en compilación, integración directa con `Stream`/`Future` (`StreamProvider`, `FutureProvider`), menor ceremonia por interacción (no exige declarar clases de Evento/Estado para cada acción).

**BLoC** (`flutter_bloc`) — patrón explícito Evento → Estado; su convención de "un Bloc por capacidad de negocio" refuerza por sí sola la separación de CRUDs de la [decisión 0009](0009-cruds-independientes-por-entidad.md); tooling de testing muy maduro (`bloc_test`); pero más boilerplate por cada interacción (clases de Evento + Estado + el Bloc).

## Decisión

Riverpod. Motivo principal: el desarrollo de esta app es de una sola persona iterando activamente la arquitectura (como se vio en toda la sesión de diseño del esquema) — la menor ceremonia de Riverpod permite iterar la UI más rápido, y su integración nativa con `Stream` calza directo con el servicio de sync en segundo plano (0007).

## Riesgo identificado y mitigación

A diferencia de BLoC, Riverpod **no impone** por convención la separación de CRUDs por entidad que ya se decidió en 0009 — es flexible por diseño, lo cual facilita construir sin querer una abstracción genérica compartida (`CrudNotifier<T>`) entre Producto, Venta, Categoria, etc.

Mitigación (no técnica, sino de proceso): la regla "un Notifier por entidad, sin clases base genéricas de CRUD" queda fijada como instrucción dura en `VulpTiketing/CLAUDE.md` (se carga en cada sesión) y detallada con la lista concreta de Notifiers previstos en `docs/arquitectura/gestion-estado.md`. El objetivo es que ninguna sesión futura — con o sin memoria de esta conversación — termine reintroduciendo el problema que 0009 ya resolvió.

## Alternativas descartadas

- BLoC — habría reforzado 0009 por convención propia del framework, pero a costa de más boilerplate por cada interacción de UI, un costo real para un solo desarrollador iterando rápido.

## Consecuencias

- Cada entidad (Producto, Categoria, Venta, y a futuro Insumo) tiene su propio Notifier, escrito a mano con solo sus operaciones reales.
- El servicio de sync y el estado de rol/dispositivo se exponen como providers de solo-lectura/Stream, no como entidades CRUD.
- Ver `docs/arquitectura/gestion-estado.md` para el detalle completo.
