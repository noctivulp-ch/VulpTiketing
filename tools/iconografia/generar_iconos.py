#!/usr/bin/env python3
"""Genera los iconos vectoriales (SVG) de VulpTiketing.

Uso:
    tools/iconografia/.venv/bin/python tools/iconografia/generar_iconos.py

Regenera todo el set en assets/icons/ del proyecto Flutter. Iconos de
linea (outline), grilla 24x24, trazo uniforme, sin color fijo (se tinta
en tiempo de ejecucion desde Flutter via flutter_svg + ColorFilter) -
ver docs/pantallas/iconografia.md para la decision de estilo completa.

Los atributos de trazo (TRAZO, abajo) se aplican directo a cada forma,
NUNCA via <style>/clases CSS: flutter_svg (vector_graphics_compiler) no
soporta <style> y lo ignora en silencio, dejando las formas sin trazo
visible. Ya se cayo en ese error una vez — no repetirlo.

Iterar: ajustar las funciones _icono_* de abajo y volver a correr.
"""

from __future__ import annotations

import math
from pathlib import Path

import svgwrite

VIEWBOX = 24
STROKE = "#1A1A1A"  # se retinta en Flutter, este es solo el valor base
STROKE_WIDTH = 1.75
OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "icons"

# Atributos de presentacion directos — no usar <style>/class (ver docstring).
TRAZO = {
    "fill": "none",
    "stroke": STROKE,
    "stroke_width": STROKE_WIDTH,
    "stroke_linecap": "round",
    "stroke_linejoin": "round",
}


class _Dibujo(svgwrite.Drawing):
    """svgwrite siempre emite un <defs/> vacio; flutter_svg no lo reconoce
    y tira un warning inofensivo pero ruidoso en cada carga. Se limpia al
    guardar para no confundirlo despues con el bug real de <style>
    (ver docstring del modulo)."""

    def save(self, **kwargs):
        super().save(**kwargs)
        path = Path(self.filename)
        path.write_text(path.read_text().replace("<defs />", ""))


def _nuevo(nombre: str) -> svgwrite.Drawing:
    return _Dibujo(
        str(OUT_DIR / f"{nombre}.svg"),
        size=(VIEWBOX, VIEWBOX),
        viewBox=f"0 0 {VIEWBOX} {VIEWBOX}",
    )


def icono_venta_rapida() -> None:
    """Rayo en circulo — Ventana 1, transmite 'rapido/instantaneo'."""
    dwg = _nuevo("venta_rapida")
    dwg.add(dwg.circle(center=(12, 12), r=9.25, **TRAZO))
    bolt = [(13, 6), (8, 13.2), (11.3, 13.2), (10, 18), (16, 10.4), (12.6, 10.4)]
    dwg.add(dwg.polygon(points=bolt, fill=STROKE, stroke="none"))
    dwg.save()


def icono_panel_venta() -> None:
    """Carrito de compras — Ventana 2, el carrito multi-linea real."""
    dwg = _nuevo("panel_venta")
    dwg.add(dwg.line(start=(3, 4), end=(5.5, 4), **TRAZO))
    dwg.add(dwg.polyline(
        points=[(5.5, 4), (7.5, 15), (19, 15), (21, 6.5), (6.3, 6.5)],
        **TRAZO,
    ))
    dwg.add(dwg.circle(center=(9.5, 20), r=1.4, fill=STROKE, stroke="none"))
    dwg.add(dwg.circle(center=(17, 20), r=1.4, fill=STROKE, stroke="none"))
    dwg.save()


def icono_producto() -> None:
    """Caja con solapa — Ventana 3, CRUD de Producto/inventario."""
    dwg = _nuevo("producto")
    dwg.add(dwg.rect(insert=(4, 8), size=(16, 12), rx=1.5, **TRAZO))
    dwg.add(dwg.polyline(points=[(4, 8), (12, 4), (20, 8)], **TRAZO))
    dwg.add(dwg.line(start=(12, 4), end=(12, 8), **TRAZO))
    dwg.save()


def icono_reportes() -> None:
    """Barras ascendentes — Ventana 4."""
    dwg = _nuevo("reportes")
    dwg.add(dwg.line(start=(3, 20.25), end=(21, 20.25), **TRAZO))
    dwg.add(dwg.rect(insert=(5, 11), size=(3, 9), rx=1, **TRAZO))
    dwg.add(dwg.rect(insert=(10.5, 7), size=(3, 13), rx=1, **TRAZO))
    dwg.add(dwg.rect(insert=(16, 3), size=(3, 17), rx=1, **TRAZO))
    dwg.save()


def icono_configuracion() -> None:
    """Engranaje — Ventana 5."""
    dwg = _nuevo("configuracion")
    dwg.add(dwg.circle(center=(12, 12), r=3, **TRAZO))
    dwg.add(dwg.circle(center=(12, 12), r=7.5, **TRAZO))
    for i in range(8):
        angulo = math.radians(i * 45)
        x1 = 12 + 7.5 * math.cos(angulo)
        y1 = 12 + 7.5 * math.sin(angulo)
        x2 = 12 + 9.5 * math.cos(angulo)
        y2 = 12 + 9.5 * math.sin(angulo)
        dwg.add(dwg.line(start=(x1, y1), end=(x2, y2), **TRAZO))
    dwg.save()


def icono_rol_gerente() -> None:
    """Escudo con check — Login, seleccion de rol Gerente."""
    dwg = _nuevo("rol_gerente")
    escudo = [(12, 3), (19, 6), (19, 13), (12, 21), (5, 13), (5, 6)]
    dwg.add(dwg.polygon(points=escudo, **TRAZO))
    dwg.add(dwg.polyline(points=[(8.5, 11), (11, 13.5), (15.5, 8.5)], **TRAZO))
    dwg.save()


def _zigzag(x_start: float, x_end: float, y_base: float, y_pico: float, dientes: int):
    paso = (x_end - x_start) / (dientes * 2)
    return [
        (x_start + i * paso, y_pico if i % 2 == 0 else y_base)
        for i in range(dientes * 2 + 1)
    ]


def icono_rol_registradora() -> None:
    """Ticket/recibo con borde perforado — Login, rol Registradora.

    Primer intento fue una caja registradora, pero renderizada se leia
    como una camara (rect + circulo = lente). Un ticket conecta mejor
    con el nombre de la app y es mas reconocible a tamano pequeno.
    """
    dwg = _nuevo("rol_registradora")
    arriba = _zigzag(4, 20, y_base=5, y_pico=3, dientes=4)
    abajo = _zigzag(4, 20, y_base=19, y_pico=21, dientes=4)
    contorno = arriba + list(reversed(abajo))
    dwg.add(dwg.polygon(points=contorno, **TRAZO))
    dwg.add(dwg.line(start=(8, 10), end=(16, 10), **TRAZO))
    dwg.add(dwg.line(start=(8, 13.5), end=(16, 13.5), **TRAZO))
    dwg.add(dwg.line(start=(8, 17), end=(13, 17), **TRAZO))
    dwg.save()


ICONOS = [
    icono_venta_rapida,
    icono_panel_venta,
    icono_producto,
    icono_reportes,
    icono_configuracion,
    icono_rol_gerente,
    icono_rol_registradora,
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for fn in ICONOS:
        fn()
        print(f"  generado: {fn.__name__}")
    print(f"Listo — {len(ICONOS)} iconos en {OUT_DIR}")


if __name__ == "__main__":
    main()
