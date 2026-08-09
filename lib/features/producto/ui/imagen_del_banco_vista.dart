import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_fotos.dart';
import '../../../core/theme/bento_icono_producto.dart';
import '../../configuracion/preferencias_notifier.dart';
import '../banco_imagenes.dart';

/// Pinta la cara de un producto, sea icono de la casa o foto.
///
/// Un solo widget para las dos porque quien lo usa —la miniatura del catálogo,
/// la celda de Venta Rápida, la cuadrícula del banco— no tiene por qué saber de
/// cuál se trata: pide "la imagen de este producto" y se pinta.
///
/// **Siempre hay algo que pintar.** Sin imagen elegida va el icono que le toca
/// a la [categoria]; si la categoría tampoco dice nada reconocible, el neutro.
/// Un hueco en blanco se leería como que algo se rompió, y una cuadrícula donde
/// unas celdas tienen cara y otras no se lee peor que una donde todas la tienen.
///
/// Las fotos se pueden apagar **por ventana** desde Configuración →
/// Optimización. Apagadas, el hueco no queda vacío: se dibuja el icono de la
/// categoría. Lo que se ahorra es decodificar un JPEG por celda, no el sitio.
class ImagenDelBancoVista extends ConsumerWidget {
  const ImagenDelBancoVista({
    super.key,
    required this.referencia,
    required this.ventana,
    this.iconoDeSuCategoria,
    this.apagada = false,
  });

  /// Lo guardado en `producto.imagen`.
  final String? referencia;

  /// Dónde se está pintando. Decide si las fotos de este aparato se dibujan.
  /// Nulo para los sitios que no son ninguna de las tres ventanas —el diálogo
  /// del banco, donde apagar la foto que se está eligiendo no tendría sentido.
  final VentanaConFotos? ventana;

  /// La **clave del icono** que le toca al producto por su categoría, ya
  /// resuelta (ver `iconosDeCategoriaProvider`). Antes acá llegaba el nombre de
  /// la categoría y la regla de nombres se aplicaba en cada celda; ahora la
  /// categoría puede llevar un icono elegido a mano, y quien pinta no tiene por
  /// qué saber cuál de las dos cosas ganó.
  final String? iconoDeSuCategoria;

  final bool apagada;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagen = ImagenDelBanco.de(referencia);

    if (imagen is IconoDelBanco) {
      return BentoIconoProducto(clave: imagen.clave, apagada: apagada);
    }
    if (imagen is! FotoDelBanco) return _iconoDeLaCategoria();

    final sinFotos =
        ventana != null &&
        (ref.watch(preferenciasNotifierProvider).valueOrNull?.fotosApagadasEn.contains(ventana) ??
            false);
    if (sinFotos) return _iconoDeLaCategoria();

    return FutureBuilder<File?>(
      future: ref.read(bancoDeImagenesProvider).archivoDe(imagen),
      builder: (context, snapshot) {
        final archivo = snapshot.data;
        // Mientras resuelve también va el icono: un parpadeo en blanco entre el
        // hueco y la foto se ve como un fallo de carga. Y si el archivo no está
        // —una base traída de otro aparato, o una foto borrada del banco— se
        // queda el icono, que es lo mismo que ve un producto sin foto.
        if (archivo == null) return _iconoDeLaCategoria();
        return Opacity(
          opacity: apagada ? 0.35 : 1,
          child: Image.file(archivo, fit: BoxFit.cover),
        );
      },
    );
  }

  Widget _iconoDeLaCategoria() => BentoIconoProducto(
    clave: iconoDeSuCategoria ?? iconoDeProductoPorDefecto.clave,
    apagada: apagada,
  );
}
