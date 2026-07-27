# VulpTiketing — Documentación

App de gestión enfocada en llevar **contabilidad** de una soda pequeña: inventario de productos, registro de ventas, reportes por período, dos roles (Gerente/Registradora), sincronización local entre dispositivos.

Fuente de verdad funcional cerrada: [`features/*.feature`](../features/) (Gherkin). Esta carpeta documenta el razonamiento, la arquitectura y los detalles que el Gherkin no captura.

## Arquitectura

- [Stack técnico](arquitectura/stack.md)
- [Datos](arquitectura/datos.md)
- [Esquema de base de datos (prototipo, en discusión)](arquitectura/esquema-db.md)
- [Sincronización](arquitectura/sincronizacion.md)
- [Seguridad](arquitectura/seguridad.md)

## Funciones

- [Ventas y cobro](funciones/ventas.md)
- [Reportes](funciones/reportes.md)
- [Roles y autenticación](funciones/roles-y-auth.md)
- [Backup](funciones/backup.md)

## Decisiones

- [Índice de decisiones (ADRs)](decisiones/index.md)

## Estado general (2026-07-26)

Fase de diseño — features base definidas, arquitectura en refinamiento. Ver [decisiones pendientes](decisiones/index.md) para lo que falta cerrar antes del scaffold de código.
