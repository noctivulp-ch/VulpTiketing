import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Los límites de las imágenes de producto.
///
/// Vive aparte del banco porque lo consultan dos: el banco al agregar una foto y
/// el propio selector del sistema, al que se le pide la imagen ya reducida.
class ImagenProductoService {
  const ImagenProductoService();

  /// A cuánto se limita el lado mayor de una foto.
  ///
  /// 512 px porque el destino real es una miniatura de 44 dp y una vista previa
  /// de formulario. Guardar el original de doce megapíxeles multiplicaría por
  /// cien el peso del banco para pintar algo que nunca se ve a ese tamaño.
  static const ladoMaximo = 512;
}

final imagenProductoServiceProvider = Provider<ImagenProductoService>(
  (ref) => const ImagenProductoService(),
);
