#!/usr/bin/env bash
# Regenera las tres capturas del README (docs/capturas/*.png): venta rápida en
# oscuro con oro, la misma en claro con peltre, y Reportes con un corte
# diagonal entre los dos temas.
#
#   tools/capturas/capturas.sh
#
# Corre la app instrumentada (test_driver/app.dart) dentro de Xvfb, con un HOME
# temporal: no abre ventanas en el escritorio, no lee ni escribe la base de
# quien la ejecuta, y en las capturas no aparece ninguna ruta personal.
# Necesita flutter, xvfb-run, las dependencias de compilación de Linux y
# Python con Pillow y NumPy.
set -euo pipefail
cd "$(dirname "$0")/../.."

cache_pub="${PUB_CACHE:-$HOME/.pub-cache}"
aislado="$(mktemp -d)"
trap 'rm -rf "$aislado"' EXIT
mkdir -p docs/capturas "$aislado/crudas"

# Formato de teléfono (360 lógicos dispara la composición compacta, ADR 0026),
# al doble de densidad para que se lea bien en GitHub.
HOME="$aislado" XDG_DATA_HOME="$aislado/share" XDG_CONFIG_HOME="$aislado/config" \
PUB_CACHE="$cache_pub" \
VULP_PERFIL=capturas VULP_VENTANA="${VULP_VENTANA:-390x844}" GDK_SCALE=2 GDK_BACKEND=x11 \
CAPTURAS_OUT="$aislado/crudas" \
  xvfb-run -a -s "-screen 0 2000x2000x24" \
  flutter drive --driver=tools/capturas/capturas_driver.dart --target=test_driver/app.dart -d linux

cp "$aislado"/crudas/venta-*.png docs/capturas/
python3 tools/capturas/corte_diagonal.py \
  "$aislado/crudas/_reportes-claro.png" "$aislado/crudas/_reportes-oscuro.png" \
  docs/capturas/reportes-claro-oscuro.png
ls -1 docs/capturas
