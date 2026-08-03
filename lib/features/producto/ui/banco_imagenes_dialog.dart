import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../banco_imagenes.dart';
import 'imagen_del_banco_vista.dart';

/// Elegir la imagen de un producto del banco.
///
/// Arriba las **figuras de fábrica** —siempre están, no pesan y no hay que
/// agregar nada para tener de dónde elegir— y debajo las **fotos** que se hayan
/// sumado desde la galería o la cámara. Una foto agregada sirve para todos los
/// productos que la quieran: es un banco, no un adjunto por producto.
///
/// Devuelve la referencia elegida, `''` para quitar la imagen, o `null` si se
/// cancela. Se distinguen los tres porque "sin imagen" es una elección
/// —vuelve a la figura propia del producto— y cancelar no cambia nada.
Future<String?> elegirDelBanco(BuildContext context, {required String semillaProducto}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _BancoDeImagenesDialog(semillaProducto: semillaProducto),
  );
}

class _BancoDeImagenesDialog extends ConsumerStatefulWidget {
  const _BancoDeImagenesDialog({required this.semillaProducto});

  final String semillaProducto;

  @override
  ConsumerState<_BancoDeImagenesDialog> createState() => _BancoDeImagenesDialogState();
}

class _BancoDeImagenesDialogState extends ConsumerState<_BancoDeImagenesDialog> {
  bool _ocupado = false;

  Future<void> _agregar(ImageSource origen) async {
    setState(() => _ocupado = true);
    try {
      final foto = await ref.read(bancoDeImagenesProvider).agregar(origen);
      if (!mounted) return;
      if (foto == null) return; // Cancelado en el selector del sistema.
      ref.invalidate(fotosDelBancoProvider);
      // Se elige sola: quien acaba de sacar la foto la quiere en el producto,
      // no buscarla otra vez en la cuadrícula.
      Navigator.pop(context, foto.referencia);
    } catch (_) {
      if (mounted) mostrarAviso(context, '✗ No se pudo agregar la imagen');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _borrar(FotoDelBanco foto) async {
    await ref.read(bancoDeImagenesProvider).borrar(foto);
    ref.invalidate(fotosDelBancoProvider);
  }

  @override
  Widget build(BuildContext context) {
    final banco = ref.read(bancoDeImagenesProvider);
    final fotos = ref.watch(fotosDelBancoProvider).valueOrNull ?? const [];
    final textos = Theme.of(context).textTheme;

    return BentoDialogo(
      titulo: const Text('Banco de imágenes'),
      contenido: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fotos.isNotEmpty) ...[
              Text('Tus fotos', style: textos.labelLarge),
              const SizedBox(height: BentoSpacing.unidad / 2),
              _Cuadricula(
                children: [
                  for (final foto in fotos)
                    _Celda(
                      referencia: foto.referencia,
                      semilla: widget.semillaProducto,
                      onTap: () => Navigator.pop(context, foto.referencia),
                      // Mantener presionado la saca del banco. No pregunta por
                      // los productos que la usaran: el que la tenga se ve con
                      // su figura, y recorrer el catálogo para avisar sería
                      // contestar algo que el usuario ya decidió.
                      onLongPress: () => _borrar(foto),
                    ),
                ],
              ),
              const SizedBox(height: BentoSpacing.gapCelda),
            ],
            Text('Figuras', style: textos.labelLarge),
            const SizedBox(height: BentoSpacing.unidad / 2),
            _Cuadricula(
              children: [
                for (final figura in banco.figuras())
                  _Celda(
                    referencia: figura.referencia,
                    semilla: widget.semillaProducto,
                    onTap: () => Navigator.pop(context, figura.referencia),
                  ),
              ],
            ),
          ],
        ),
      ),
      acciones: BentoAcciones(
        izquierda: [
          TextButton.icon(
            onPressed: _ocupado ? null : () => _agregar(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Cámara'),
          ),
          TextButton.icon(
            onPressed: _ocupado ? null : () => _agregar(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Galería'),
          ),
        ],
        derecha: [
          // Vaciar la imagen es una elección, no un cancelar: devuelve al
          // producto su figura propia.
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Sin imagen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}

class _Cuadricula extends StatelessWidget {
  const _Cuadricula({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return BentoCuadricula(
      // Una celda por columna de la retícula: seis por fila en cualquier ancho.
      // Son cuadros pequeños que se comparan de un vistazo, no piezas de
      // contenido que necesiten sitio propio.
      hijos: [for (final hijo in children) BentoCelda.fija(1, hijo: hijo)],
      separacion: BentoSpacing.unidad,
    );
  }
}

class _Celda extends StatelessWidget {
  const _Celda({
    required this.referencia,
    required this.semilla,
    required this.onTap,
    this.onLongPress,
  });

  final String referencia;
  final String semilla;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: BentoPozo(
        onTap: onTap,
        onLongPress: onLongPress,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BentoRadius.pozo),
          child: ImagenDelBancoVista(referencia: referencia, semillaPorDefecto: semilla),
        ),
      ),
    );
  }
}
