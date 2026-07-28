# Iconografía

Ver también: [decisión 0020](../decisiones/0020-iconografia-vectorial-propia.md) · [prototipos-ascii](prototipos-ascii.md) · [../arquitectura/gestion-estado](../arquitectura/gestion-estado.md)

Reemplaza los emojis placeholder de los bocetos (Fase 2) por íconos vectoriales propios. Detalle de la decisión (por qué Python+SVG, el gotcha de `<style>` en `flutter_svg`) en [decisión 0020](../decisiones/0020-iconografia-vectorial-propia.md) — este archivo es la referencia de estilo y el catálogo de íconos.

## Regla de estilo

- Grilla `24×24`, trazo `1.75`, `stroke-linecap`/`stroke-linejoin: round`, `fill: none` (outline) salvo detalles pequeños rellenos a propósito para legibilidad a tamaño chico.
- **Un solo color base por archivo** (`#1A1A1A`) — nunca el color final. Se retiñe en runtime (`BentoIcon`, `lib/core/theme/bento_icon.dart`) según jerarquía:
  - Inactivo → `colorScheme.onSurfaceVariant` (gris neutro).
  - Activo/seleccionado → `colorScheme.primary` (acento desaturado, configurable).
- **Nunca usar `<style>`/clases CSS** dentro del SVG — `flutter_svg` no las soporta y las ignora en silencio. Atributos de presentación directos en cada elemento (`fill`, `stroke`, `stroke-width`, ...).

## Herramienta

`scripts/iconografia/generar_iconos.py` (Python + `svgwrite`, `.venv` propio — gitignored). Para regenerar o iterar un ícono:

```bash
scripts/iconografia/.venv/bin/python scripts/iconografia/generar_iconos.py
```

Cada ícono es una función `icono_*()` — ajustar coordenadas ahí y volver a correr. El script no se importa desde la app ni corre en CI, solo se ejecuta a mano cuando se agrega o cambia un ícono (misma convención que el resto de `scripts/` del workspace).

## Catálogo actual (7 íconos)

| Archivo | Uso | Motivo del diseño |
|---------|-----|--------------------|
| `venta_rapida.svg` | Nav Dashboard — Ventana 1 | Rayo en círculo — "rápido/instantáneo" |
| `panel_venta.svg` | Nav Dashboard — Ventana 2 | Carrito de compras — el carrito multi-línea real |
| `producto.svg` | Nav Dashboard — Ventana 3 | Caja con solapa — inventario |
| `reportes.svg` | Nav Dashboard — Ventana 4 | Barras ascendentes |
| `configuracion.svg` | Nav Dashboard — Ventana 5 | Engranaje |
| `rol_gerente.svg` | Login — selección de rol | Escudo con check — autoridad/verificado |
| `rol_registradora.svg` | Login — selección de rol | Ticket/recibo con borde perforado — conecta con "Tiketing"; el primer intento (caja registradora) se leía como cámara al renderizarlo, se descartó |

**Pendiente** (se generan cuando se implemente cada pantalla, no de una vez): buscar, editar, descontinuar, purgar, línea libre, agregar (+), completado/check de selección, cambiar contraseña, exportar/restaurar backup, estado de sync, acerca de, cerrar sesión, exportar PDF/CSV.

## Acento configurable

`AcentoTinte` (`lib/core/theme/bento_theme.dart`): `grisAzulado` (default), `grisVerdoso`, `grisCafe` — tres semillas de color ya desaturadas, combinadas con `DynamicSchemeVariant.neutral` de Material 3 para que el esquema completo se mantenga cerca del gris. Seleccionable en Configuración (Ventana 5), persistido vía `PreferenciasNotifier`.
