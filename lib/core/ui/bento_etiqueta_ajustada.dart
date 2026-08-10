import 'package:flutter/material.dart';

/// Una etiqueta corta que **encoge la tipografía antes que partirse**.
///
/// El caso que la trajo: "Optimización" en la rejilla de Configuración. El tile
/// deja ~69 dp de texto a 360 dp de ancho, la palabra no entra, y Flutter la
/// cortaba a mitad —"Optimizaci / ón"— porque partir por carácter es lo que hace
/// cuando una palabra sola es más ancha que la línea. Lo decidió el dueño:
/// "dejar que se encoja la tipografía está bien".
///
/// Una línea siempre, encogida lo justo para entrar. Lo que ya entra no se toca:
/// `BoxFit.scaleDown` solo reduce, nunca agranda.
///
/// **Sin `LayoutBuilder`.** Fue el primer intento —medir el ancho disponible y
/// bajar el tamaño de medio en medio punto— y no sirve acá: la rejilla comparte
/// el alto de cada fila con `IntrinsicHeight`, y un `LayoutBuilder` no sabe dar
/// dimensiones intrínsecas ("LayoutBuilder does not support returning intrinsic
/// dimensions"). Reventaba la pantalla de Configuración entera. `FittedBox` sí
/// las calcula, y hace lo mismo con menos código.
class BentoEtiquetaAjustada extends StatelessWidget {
  const BentoEtiquetaAjustada(
    this.texto, {
    super.key,
    this.estilo,
    this.textAlign = TextAlign.center,
  });

  final String texto;
  final TextStyle? estilo;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        texto,
        textAlign: textAlign,
        // Una línea y sin ceder: es lo que obliga a `FittedBox` a resolverlo
        // encogiendo. Con `softWrap` puesto, el texto se partiría antes de que
        // hubiera nada que escalar.
        maxLines: 1,
        softWrap: false,
        style: estilo,
      ),
    );
  }
}
