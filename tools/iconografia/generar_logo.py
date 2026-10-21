#!/usr/bin/env python3
"""Genera el logo de VulpTiketing y los iconos de lanzador de Android.

Uso:
    tools/iconografia/.venv/bin/python tools/iconografia/generar_logo.py

Escribe:
    assets/logo/vulptiketing.svg          — el original vectorial
    android/app/src/main/res/mipmap-*/ic_launcher.png

El logo es la RETICULA BENTO, que es la identidad real de la app: una caja de
laca oscura con sus compartimentos ribeteados en oro, con el reparto asimetrico
que usan todas las pantallas (una celda grande, dos chicas, una barra). No lleva
letra ni simbolo de dinero — un "V" o un signo de colon lo volverian generico, y
lo que distingue a esta app de cualquier otra caja registradora es justamente
como reparte el espacio.

Los colores salen del tema, no de una paleta aparte (lib/core/theme/
bento_theme.dart): si algun dia cambia la laca, esto se regenera y sigue
casando.

Es un logo provisional y suficiente, no uno profesional: sirve para reconocer la
app entre las demas del cajon hasta que haya uno de verdad.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]

# De lib/core/theme/bento_theme.dart, modo oscuro.
BANDEJA = "#14100E"  # el marco
POZO = "#3A1E1B"  # el rebaje de cada compartimento
ORO = "#D9A54A"  # el pan de metal que ribetea los cantos

# Lienzo de 108: es la unidad del icono adaptativo de Android, donde los 18 de
# cada borde son zona de recorte que el sistema puede comerse segun la forma
# (circulo, cuadrado redondeado, gota). Todo lo que importa vive dentro de los
# 72 centrales.
LADO = 108
SEGURO = 18


def _celda(x, y, ancho, alto, radio=3.5, relleno=POZO):
    """Un compartimento: rebaje relleno + canto de oro, como en la app."""
    return (
        f'<rect x="{x}" y="{y}" width="{ancho}" height="{alto}" '
        f'rx="{radio}" ry="{radio}" fill="{relleno}" '
        f'stroke="{ORO}" stroke-width="1.6"/>'
    )


def svg() -> str:
    # El reparto es el de la retícula de 6 columnas de la app: una pieza que
    # ocupa media caja y manda, dos que se reparten la otra mitad, y una barra
    # ancha abajo. Asimetrico a proposito — una cuadricula 2x2 uniforme se lee
    # como una tabla, no como una caja bento.
    m = SEGURO + 6  # margen interior util
    ancho = LADO - 2 * m
    gap = 4.5

    grande_ancho = ancho * 0.56
    chica_ancho = ancho - grande_ancho - gap
    fila_alta = 34
    barra_alta = 16
    chica_alta = (fila_alta - gap) / 2

    piezas = [
        # La grande, a la izquierda.
        _celda(m, m, grande_ancho, fila_alta),
        # Las dos chicas, apiladas a la derecha.
        _celda(m + grande_ancho + gap, m, chica_ancho, chica_alta),
        _celda(m + grande_ancho + gap, m + chica_alta + gap, chica_ancho, chica_alta),
        # La barra de abajo, a lo ancho: es el buscador/la barra de cobro, que
        # en todas las pantallas cruza el borde inferior entero.
        _celda(m, m + fila_alta + gap, ancho, barra_alta, relleno=ORO),
    ]

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{LADO}" height="{LADO}" '
        f'viewBox="0 0 {LADO} {LADO}">'
        # El fondo llega hasta el borde del lienzo: si el sistema recorta en
        # circulo, no puede aparecer una esquina transparente.
        f'<rect width="{LADO}" height="{LADO}" fill="{BANDEJA}"/>'
        + "".join(piezas)
        + "</svg>"
    )


# Los tamanos de lanzador de Android. `xxxhdpi` es el que usan las tiendas y los
# lanzadores grandes; `mdpi` el minimo que sigue existiendo.
MIPMAPS = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def main() -> None:
    origen = RAIZ / "assets" / "logo"
    origen.mkdir(parents=True, exist_ok=True)
    ruta_svg = origen / "vulptiketing.svg"
    ruta_svg.write_text(svg())
    print(f"escrito {ruta_svg.relative_to(RAIZ)}")

    for sufijo, lado in MIPMAPS.items():
        destino = RAIZ / "android" / "app" / "src" / "main" / "res" / f"mipmap-{sufijo}"
        destino.mkdir(parents=True, exist_ok=True)
        salida = destino / "ic_launcher.png"
        subprocess.run(
            ["rsvg-convert", "-w", str(lado), "-h", str(lado), str(ruta_svg), "-o", str(salida)],
            check=True,
        )
        print(f"escrito {salida.relative_to(RAIZ)} ({lado}px)")

    # Una copia grande para lo que no es Android: la ficha del repo, el vault,
    # o para abrirlo y mirarlo sin lupa.
    subprocess.run(
        ["rsvg-convert", "-w", "512", "-h", "512", str(ruta_svg), "-o", str(origen / "vulptiketing-512.png")],
        check=True,
    )
    print("escrito assets/logo/vulptiketing-512.png (512px)")


if __name__ == "__main__":
    main()
