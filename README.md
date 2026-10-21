<div align="center">

# VulpTiketing

**Caja, inventario y reportes para un negocio de comidas pequeño.**

![Licencia](https://img.shields.io/badge/licencia-GPL--3.0--or--later-FF6B00?style=flat-square&labelColor=1A1A1A)
![Plataformas](https://img.shields.io/badge/plataformas-Android%20%C2%B7%20Linux%20%C2%B7%20Windows-3A3A3A?style=flat-square&labelColor=1A1A1A)
![Flutter](https://img.shields.io/badge/Flutter-3.x-3A3A3A?style=flat-square&logo=flutter&labelColor=1A1A1A)
![Versión](https://img.shields.io/badge/versi%C3%B3n-1.1.0-3A3A3A?style=flat-square&labelColor=1A1A1A)

</div>

---

## Qué es

VulpTiketing lleva la contabilidad diaria de una soda o cafetería: el catálogo de productos, el
registro de cada venta y los reportes por período. Está pensada para el mostrador: pantallas
grandes y claras, cobro en pocos toques y funcionamiento sin conexión a internet. Varios
dispositivos del mismo local se sincronizan entre sí por la red local, sin servidor externo.

## Funciones principales

- **Ventas**: venta rápida y compuesta, líneas libres, cobro en efectivo o SINPE, reversión.
- **Inventario**: categorías y productos, con altas, cambios y descontinuados.
- **Reportes**: ventas por período y cierre de caja, exportables a PDF.
- **Dos roles**: Gerente y Registradora, cada uno con sus permisos.
- **Sincronización local** entre teléfonos y PC por la misma red, sin nube.
- **Respaldo cifrado** y restauración.
- **Costeo de recetas** (solo Gerente): calcula el costo de cada producto y sugiere precios.

## Tecnologías

| Capa | Tecnología |
|---|---|
| Interfaz | Flutter, con diseño propio tipo *bento* e iconografía vectorial propia |
| Estado | Riverpod |
| Datos | SQLite (`sqflite`, `sqflite_common_ffi` en escritorio) |
| Red local | descubrimiento mDNS (`bonsoir`) y servidor HTTP embebido (`shelf`) |
| Seguridad | `cryptography` (AES-GCM), `flutter_secure_storage` |
| Documentos | `pdf`, con la fuente Noto Sans recortada |
| Especificación | escenarios Gherkin en [`features/`](features/) |

## Puesta en marcha

```bash
flutter pub get
flutter run -d linux        # o un dispositivo Android
flutter test
```

Los datos de ejemplo para probar la app están en [`seed/`](seed/README.md).

## Documentación

La arquitectura, las pantallas, las funciones y las decisiones (ADR) están en
[`docs/`](docs/index.md). La dirección visual, en [`DESIGN.md`](DESIGN.md).

## Licencia

Código bajo **GPL-3.0-or-later** ([`LICENSE`](LICENSE)). Los componentes de terceros y sus licencias
están en [`NOTICE`](NOTICE). El nombre y la identidad visual no forman parte de la licencia: ver
[`TRADEMARKS.md`](TRADEMARKS.md). Para aportar, [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Apoyo

Este proyecto forma parte del trabajo de **NoctiVulp**: herramientas para Linux y Android,
publicadas como software libre. Las compilaciones oficiales y las novedades salen en Patreon.

<p align="center">
  <a href="https://www.patreon.com/cw/NoctiVulp"><img src="https://img.shields.io/badge/Patreon-NoctiVulp-FF6B00?style=for-the-badge&logo=patreon&logoColor=white&labelColor=1A1A1A" alt="NoctiVulp en Patreon"></a>
</p>

---

<p align="center"><sub>© 2026 NoctiVulp · <b>Powered by AI</b> — desarrollado con la asistencia de Claude, de Anthropic.</sub></p>
