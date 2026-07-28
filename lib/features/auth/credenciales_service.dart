import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Hashea/verifica la contrasena local del dispositivo (Argon2id — decision
/// 0011). No sabe nada de sesion ni de UI (decision 0019).
///
/// TODO: implementar con package:cryptography (clase Argon2id) + salt
/// aleatorio generado una vez y persistido junto al hash (nunca un salt
/// fijo). Se deja sin implementar a proposito en el scaffold para no dejar
/// una pieza de seguridad a medias que parezca terminada.
class CredencialesService {
  CredencialesService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // ignore: unused_field
  final FlutterSecureStorage _storage;
  static const keyHash = 'contrasena_hash';
  static const keySalt = 'contrasena_salt';

  Future<void> establecerContrasena(String contrasena) {
    throw UnimplementedError(
      'TODO(0011): Argon2id + salt aleatorio, ver package:cryptography',
    );
  }

  Future<bool> verificar(String contrasena) {
    throw UnimplementedError(
      'TODO(0011): Argon2id + salt aleatorio, ver package:cryptography',
    );
  }
}
