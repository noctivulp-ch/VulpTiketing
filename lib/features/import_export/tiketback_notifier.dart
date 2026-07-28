import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exportar/restaurar el backup completo cifrado (decisiones 0006/0017).
/// Restaurar es SIEMPRE reemplazo total — nunca ofrece modo "fusionar"
/// (0017: fusionar dos historiales de venta no tiene sentido contable).
///
/// TODO: implementar con package:cryptography (Argon2id + AES-256-GCM),
/// reusando el mismo mecanismo de derivacion de clave que
/// CredencialesService una vez que esa quede implementada.
class TiketbackNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> exportar({required String contrasenaExportacion}) {
    throw UnimplementedError('TODO(0006): Argon2id + AES-256-GCM');
  }

  Future<void> restaurar({
    required String rutaArchivo,
    required String contrasenaExportacion,
  }) {
    throw UnimplementedError('TODO(0006): Argon2id + AES-256-GCM');
  }
}

final tiketbackNotifierProvider =
    NotifierProvider<TiketbackNotifier, void>(TiketbackNotifier.new);
