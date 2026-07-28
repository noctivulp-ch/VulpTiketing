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

## Pantallas

- [Flujo de pantallas — descripción (Fase 1)](pantallas/flujo-descripcion.md)
- [Prototipos ASCII (Fase 2, bento)](pantallas/prototipos-ascii.md)
- [Mapa de flujo general](pantallas/mapa-de-flujo.md) (auditoría de navegación — hallazgo abierto sobre rol por dispositivo vs. por sesión)

## Funciones

- [Ventas y cobro](funciones/ventas.md)
- [Reportes](funciones/reportes.md)
- [Roles y autenticación](funciones/roles-y-auth.md)
- [Backup](funciones/backup.md)

## Decisiones

- [Índice de decisiones (ADRs)](decisiones/index.md)

## Estado general (2026-07-28)

Diseño cerrado (19 ADRs aceptados) y **scaffold de Flutter creado**: proyecto compilando en Linux desktop, modelos/DAOs/Notifiers de Producto/Categoria/Venta funcionando de verdad contra SQLite, shell de navegación bento con las 5 ventanas. Pendiente: implementar UI completa de Ventas/Reportes, sync (falta elegir paquete mDNS), cifrado de backup, y completar el Android SDK de este entorno. Ver [decisiones](decisiones/index.md) y [stack técnico](arquitectura/stack.md) para el detalle del scaffold.
