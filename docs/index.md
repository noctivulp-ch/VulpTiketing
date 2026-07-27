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
- [Prototipos ASCII (Fase 2, vacío — requiere skill de diseño bento)](pantallas/prototipos-ascii.md)

## Funciones

- [Ventas y cobro](funciones/ventas.md)
- [Reportes](funciones/reportes.md)
- [Roles y autenticación](funciones/roles-y-auth.md)
- [Backup](funciones/backup.md)

## Decisiones

- [Índice de decisiones (ADRs)](decisiones/index.md)

## Estado general (2026-07-26)

Fase de diseño — features base, esquema de datos y gestión de estado cerrados (14 ADRs aceptados). Siguiente paso: scaffold de Flutter (`flutter create`) y versión mínima de Dart/Flutter. Ver [decisiones](decisiones/index.md).
