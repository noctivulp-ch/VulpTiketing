import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_imagen_abstracta.dart';
import '../banco_imagenes.dart';

/// Pinta una imagen del banco, sea figura o foto.
///
/// Un solo widget para las dos porque quien lo usa —la miniatura del catálogo,
/// la vista previa del formulario, la cuadrícula del banco— no tiene por qué
/// saber de cuál se trata: pide "la imagen de este producto" y se pinta.
///
/// Cuando la referencia no resuelve —una foto borrada del banco, o una base
/// traída de otro aparato— cae a la figura de [semillaPorDefecto]. No es un
/// error: es lo mismo que ve un producto que nunca eligió imagen, y un hueco en
/// blanco se leería como que algo se rompió.
class ImagenDelBancoVista extends ConsumerWidget {
  const ImagenDelBancoVista({
    super.key,
    required this.referencia,
    required this.semillaPorDefecto,
    this.apagada = false,
  });

  /// Lo guardado en `producto.imagen`.
  final String? referencia;

  /// Con qué dibujar si no hay imagen o no resuelve. El id del producto: así
  /// cada uno tiene su cara aunque nadie le haya elegido ninguna.
  final String semillaPorDefecto;

  final bool apagada;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagen = ImagenDelBanco.de(referencia);

    if (imagen is FiguraAbstracta) {
      return BentoImagenAbstracta(semilla: imagen.semilla, apagada: apagada);
    }
    if (imagen is! FotoDelBanco) {
      return BentoImagenAbstracta(semilla: semillaPorDefecto, apagada: apagada);
    }

    return FutureBuilder<File?>(
      future: ref.read(bancoDeImagenesProvider).archivoDe(imagen),
      builder: (context, snapshot) {
        final archivo = snapshot.data;
        // Mientras resuelve también va la figura: un parpadeo en blanco entre
        // el hueco y la foto se ve como un fallo de carga.
        if (archivo == null) {
          return BentoImagenAbstracta(semilla: semillaPorDefecto, apagada: apagada);
        }
        return Opacity(
          opacity: apagada ? 0.35 : 1,
          child: Image.file(archivo, fit: BoxFit.cover),
        );
      },
    );
  }
}
