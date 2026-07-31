# VulpTiketing — Documentación

App de gestión enfocada en llevar **contabilidad** de una soda pequeña: inventario de productos, registro de ventas, reportes por período, dos roles (Gerente/Registradora), sincronización local entre dispositivos.

Fuente de verdad funcional cerrada: [`features/*.feature`](../features/) (Gherkin). Esta carpeta documenta el razonamiento, la arquitectura y los detalles que el Gherkin no captura.

## Arquitectura

- [Stack técnico](arquitectura/stack.md)
- [Datos](arquitectura/datos.md)
- [Esquema de base de datos](arquitectura/esquema-db.md) (mayormente cerrado — quedan `device_id` e índices)
- [Gestión de estado](arquitectura/gestion-estado.md) (Riverpod — regla dura contra abstracciones genéricas de CRUD)
- [Sincronización](arquitectura/sincronizacion.md)
- [Seguridad](arquitectura/seguridad.md)
- [Rendimiento](arquitectura/rendimiento.md) (medido en el teléfono, en profile — cuellos, opciones probadas y cómo medir)

## Pantallas

- [Flujo de pantallas — descripción (Fase 1)](pantallas/flujo-descripcion.md)
- [Prototipos ASCII (Fase 2, bento)](pantallas/prototipos-ascii.md)
- [Mapa de flujo general](pantallas/mapa-de-flujo.md) (auditoría de navegación — 5 hallazgos, todos resueltos)
- [Iconografía](pantallas/iconografia.md) (íconos vectoriales propios, Python + SVG)
- [Referencias visuales — cajas bento reales](pantallas/referencias-visuales/README.md) (por qué la UI se veía como botones y no como compartimentos "hundidos")
- [**DESIGN.md**](../DESIGN.md) (raíz del repo) — contrato de dirección visual y las reglas de material que no se negocian: bandeja/pozo, la cresta como señal de tallado, prohibición de `ColorScheme.fromSeed`

## Funciones

- [Ventas y cobro](funciones/ventas.md)
- [Reportes](funciones/reportes.md)
- [Roles y autenticación](funciones/roles-y-auth.md)
- [Backup](funciones/backup.md)

## Datos de prueba

- [seed/](../seed/README.md) — el menú real y la base de pruebas única (500 ventas repartidas por semanas, días y turnos)

## Decisiones

- [Índice de decisiones (ADRs)](decisiones/index.md)

## Informes

- [**Informe de pruebas de estrés — 30/07/2026**](INFORME-ESTRES-2026-07-30.md) — la app se volvía inusable con un año de uso real; qué se corrigió, qué se midió y qué queda pendiente de decisión

## Datos reales

- [Menú — la soda](menu-de-ejemplo.md) (transcripción del menú físico, fuente del catálogo inicial en `seed/catalogo-inicial.tiketdata`)

## Estado general (2026-07-28)

Diseño cerrado (19 ADRs aceptados) y **scaffold de Flutter creado**: proyecto compilando en Linux desktop, modelos/DAOs/Notifiers de Producto/Categoria/Venta funcionando de verdad contra SQLite, shell de navegación bento con las 5 ventanas. Pendiente: implementar UI completa de Ventas/Reportes, sync (falta elegir paquete mDNS), cifrado de backup, y completar el Android SDK de este entorno. Ver [decisiones](decisiones/index.md) y [stack técnico](arquitectura/stack.md) para el detalle del scaffold.
