import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import '../producto/categoria_notifier.dart';
import '../producto/producto_notifier.dart';
import 'almacen_publico.dart';
import 'carpeta_exportacion.dart';
import 'tiketdata_service.dart';

enum ResultadoTiketdata { ok, cancelado, error }

/// Fachada Riverpod-facing de TiketdataService: agrega el selector nativo
/// de archivos y, tras importar, invalida ProductoNotifier/CategoriaNotifier
/// para que la UI relea el catálogo actualizado.
class TiketdataNotifier extends Notifier<void> {
  @override
  void build() {}

  /// A la carpeta de exportación, sin selector — ver [CarpetaExportacion].
  /// Devuelve la ruta escrita para poder decir dónde quedó.
  Future<(ResultadoTiketdata, String?)> exportarCatalogo() async {
    final db = await ref.read(databaseProvider.future);
    try {
      final destino = await const CarpetaExportacion().archivoPara('catalogo.tiketdata');
      await destino.writeAsBytes(await TiketdataService(db).generarCatalogo());
      // Y a Descargas, que es donde el dueño del teléfono lo puede encontrar.
      return (ResultadoTiketdata.ok, await const AlmacenPublico().publicar(destino));
    } catch (_) {
      return (ResultadoTiketdata.error, null);
    }
  }

  /// [rutaYaElegida] cuando el archivo no lo eligió el selector.
  ///
  /// Es el caso de abrir un `.tiketdata` desde el explorador: el archivo ya está
  /// identificado y volver a preguntar por él sería pedirle al usuario que
  /// busque el que acaba de tocar.
  Future<ResultadoTiketdata> importarCatalogo(ModoImportacion modo, {String? rutaYaElegida}) async {
    final ruta =
        rutaYaElegida ??
        (await FilePicker.platform.pickFiles(
          dialogTitle: 'Elegir catálogo a importar',
        ))?.files.single.path;
    if (ruta == null) return ResultadoTiketdata.cancelado;

    final db = await ref.read(databaseProvider.future);
    try {
      await TiketdataService(db).importarCatalogo(rutaOrigen: ruta, modo: modo);
      ref.invalidate(productoNotifierProvider);
      ref.invalidate(categoriaNotifierProvider);
      return ResultadoTiketdata.ok;
    } catch (_) {
      return ResultadoTiketdata.error;
    }
  }
}

final tiketdataNotifierProvider = NotifierProvider<TiketdataNotifier, void>(TiketdataNotifier.new);
