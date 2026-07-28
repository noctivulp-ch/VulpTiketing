import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ModoImportacion { reemplazar, fusionar }

/// Exportar/importar el paquete de catalogo .tiketdata (decision 0017):
/// solo Producto y Categoria, JSON sin cifrar, preservando UUID originales.
///
/// TODO: implementar usando RowSyncEngine (lib/features/sync/row_sync_engine.dart)
/// para el merge en ambos modos:
///   - Reemplazar: descontinuar (soft-delete) todo Producto/Categoria local
///     no presente en el archivo, luego RowSyncEngine.fusionar() con lo que
///     si viene.
///   - Fusionar: solo RowSyncEngine.fusionar(), sin tocar el resto.
/// No se implementa todavia en el scaffold porque falta el I/O de archivo
/// (file picker) y las pruebas de round-trip — el mecanismo de merge en si
/// ya existe y no debe duplicarse aqui.
class TiketdataNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> exportarCatalogo() {
    throw UnimplementedError('TODO(0017): JSON de Producto+Categoria');
  }

  Future<void> importarCatalogo({
    required String rutaArchivo,
    required ModoImportacion modo,
  }) {
    throw UnimplementedError(
      'TODO(0017): usar RowSyncEngine.fusionar(), ver comentario de clase',
    );
  }
}

final tiketdataNotifierProvider =
    NotifierProvider<TiketdataNotifier, void>(TiketdataNotifier.new);
