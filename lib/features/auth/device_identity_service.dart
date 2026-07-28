import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Genera/lee el device_id persistente para sync (decision 0007). No sabe
/// nada de contrasenas ni de rol (decision 0019) — eso es
/// CredencialesService/SesionNotifier.
class DeviceIdentityService {
  DeviceIdentityService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'device_id';
  static const _uuid = Uuid();

  Future<String> obtenerOCrear() async {
    final existente = await _storage.read(key: _key);
    if (existente != null) return existente;
    final nuevo = _uuid.v4();
    await _storage.write(key: _key, value: nuevo);
    return nuevo;
  }
}
