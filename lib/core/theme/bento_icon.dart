import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icono vectorial propio — ver docs/pantallas/iconografia.md.
/// SVG monocromo (generado con Python, scripts/iconografia/) sin color
/// horneado; se retinta en tiempo de ejecucion segun jerarquia:
/// `activo=false` usa el tono neutro de la escala de grises
/// (`colorScheme.onSurfaceVariant`), `activo=true` usa el acento
/// desaturado y configurable (`colorScheme.primary`, ver bento_theme.dart).
class BentoIcon extends StatelessWidget {
  const BentoIcon(this.nombre, {super.key, this.activo = false, this.size = 24});

  final String nombre;
  final bool activo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = activo ? scheme.primary : scheme.onSurfaceVariant;
    return SvgPicture.asset(
      'assets/icons/$nombre.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
