import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';

import 'carpeta_exportacion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../venta/libro_ventas.dart';
import 'tiketback_service.dart';

enum ResultadoTiketback { ok, cancelado, contrasenaIncorrecta, error }

/// Fachada Riverpod-facing de TiketbackService: agrega el selector nativo
/// de archivos (file_picker) y, al restaurar, invalida databaseProvider
/// para que toda la app relea contra el archivo ya reemplazado.
class TiketbackNotifier extends Notifier<void> {
  final _service = TiketbackService();

  @override
  void build() {}

  /// Escribe en la carpeta de exportación, sin pasar por el selector.
  ///
  /// El selector no sirve para esto en Android: `saveFile` exige los bytes por
  /// adelantado y un backup de la soda puede pesar más que la memoria libre —
  /// justo lo que el escritor por trozos existe para evitar.
  ///
  /// Devuelve la ruta escrita para poder decirle al usuario dónde quedó.
  Future<(ResultadoTiketback, String?)> exportar(String contrasenaExportacion) async {
    try {
      final destino = await const CarpetaExportacion().archivoPara(
        'vulptiketing-${DateTime.now().toIso8601String().split('T').first}.tiketback',
      );
      final ruta = destino.path;
      final db = await ref.read(databaseProvider.future);
      final libros = await ref.read(libroVentasServiceProvider.future);
      await _service.exportar(
        contrasenaExportacion: contrasenaExportacion,
        directorioDatos: await _directorioDatos(),
        nombreBasePrincipal: p.basename(await AppDatabase.ruta()),
        // Todos los libros, no solo el abierto: el backup es la única copia de
        // los años anteriores (decisión 0025).
        archivosDeLibro: (await libros.todos(db)).map((l) => l.archivo).toList(),
        rutaDestino: ruta,
      );
      return (ResultadoTiketback.ok, ruta);
    } catch (_) {
      return (ResultadoTiketback.error, null);
    }
  }

  /// Restaurar es SIEMPRE reemplazo (0017); [alcance] dice qué se reemplaza.
  /// La UI que llama a esto debe confirmar con el usuario antes.
  Future<ResultadoTiketback> restaurar(
    String contrasenaExportacion, {
    AlcanceRestauracion alcance = AlcanceRestauracion.todo,
  }) async {
    final resultado = await FilePicker.platform.pickFiles(dialogTitle: 'Elegir backup a restaurar');
    final ruta = resultado?.files.single.path;
    if (ruta == null) return ResultadoTiketback.cancelado;

    try {
      await _service.restaurar(
        contrasenaExportacion: contrasenaExportacion,
        directorioDatos: await _directorioDatos(),
        nombreBasePrincipal: p.basename(await AppDatabase.ruta()),
        rutaOrigen: ruta,
        alcance: alcance,
      );
      // Reabre la base: el ATTACH del libro abierto solo ocurre al abrir, y
      // tras restaurar el libro vigente puede ser otro archivo.
      ref.invalidate(databaseProvider);
      return ResultadoTiketback.ok;
    } on SecretBoxAuthenticationError {
      return ResultadoTiketback.contrasenaIncorrecta;
    } catch (_) {
      return ResultadoTiketback.error;
    }
  }

  Future<String> _directorioDatos() async => p.dirname(await AppDatabase.ruta());
}

final tiketbackNotifierProvider = NotifierProvider<TiketbackNotifier, void>(TiketbackNotifier.new);
