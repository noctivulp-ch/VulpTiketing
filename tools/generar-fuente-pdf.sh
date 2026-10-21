#!/usr/bin/env bash
# Regenera las fuentes que se incrustan en los PDF de Reportes.
#
# Origen: Noto Sans (SIL Open Font License 1.1, libre para incrustar).
# Las de fábrica del generador de PDF no tienen el símbolo del colón (₡), así
# que los montos salían sin moneda.
#
# Recortadas a lo que el reporte escribe: latín básico, acentos del español,
# comillas tipográficas y ₡. Las dos variantes completas pesan 1,2 MB; así
# quedan en 42 KB, que es lo que corresponde en una app que corre en un
# teléfono de gama baja.
#
# Requiere fonttools (pip install fonttools).
set -euo pipefail
cd "$(dirname "$0")/.."

ORIGEN="${1:-/usr/share/fonts/noto}"
UNICODES="U+0020-007E,U+00A0-00FF,U+0100-017F,U+20A1,U+2018-201D,U+2026,U+00B7"

mkdir -p assets/fonts
for variante in Regular Bold; do
  pyftsubset "$ORIGEN/NotoSans-$variante.ttf" \
    --unicodes="$UNICODES" \
    --layout-features='' \
    --no-hinting \
    --output-file="assets/fonts/NotoSans-$variante.ttf"
done

ls -la assets/fonts/
