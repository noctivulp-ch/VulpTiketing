import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import 'tiketback_service.dart';

enum ResultadoTiketback { ok, cancelado, contrasenaIncorrecta, error }

/// Fachada Riverpod-facing de TiketbackService: agrega el selector nativo
/// de archivos (file_picker) y, al restaurar, invalida databaseProvider
/// para que toda la app relea contra el archivo ya reemplazado.
class TiketbackNotifier extends Notifier<void> {
  final _service = TiketbackService();

  @override
  void build() {}

  Future<ResultadoTiketback> exportar(String contrasenaExportacion) async {
    final ruta = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar backup',
      fileName: 'vulptiketing.tiketback',
    );
    if (ruta == null) return ResultadoTiketback.cancelado;

    try {
      await _service.exportar(
        contrasenaExportacion: contrasenaExportacion,
        rutaBaseDeDatos: await AppDatabase.ruta(),
        rutaDestino: ruta,
      );
      return ResultadoTiketback.ok;
    } catch (_) {
      return ResultadoTiketback.error;
    }
  }

  /// Restaurar es SIEMPRE reemplazo total (0017) — la UI que llama a esto
  /// debe confirmar con el usuario antes, es irreversible.
  Future<ResultadoTiketback> restaurar(String contrasenaExportacion) async {
    final resultado = await FilePicker.platform.pickFiles(
      dialogTitle: 'Elegir backup a restaurar',
    );
    final ruta = resultado?.files.single.path;
    if (ruta == null) return ResultadoTiketback.cancelado;

    try {
      await _service.restaurar(
        contrasenaExportacion: contrasenaExportacion,
        rutaBaseDeDatos: await AppDatabase.ruta(),
        rutaOrigen: ruta,
      );
      ref.invalidate(databaseProvider);
      return ResultadoTiketback.ok;
    } on SecretBoxAuthenticationError {
      return ResultadoTiketback.contrasenaIncorrecta;
    } catch (_) {
      return ResultadoTiketback.error;
    }
  }
}

final tiketbackNotifierProvider = NotifierProvider<TiketbackNotifier, void>(TiketbackNotifier.new);
