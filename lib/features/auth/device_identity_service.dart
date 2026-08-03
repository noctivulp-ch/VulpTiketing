import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Genera/lee el device_id persistente para sync (decision 0007). No sabe
/// nada de contrasenas ni de rol (decision 0019) — eso es
/// CredencialesService/SesionNotifier.
class DeviceIdentityService {
  DeviceIdentityService({FlutterSecureStorage? storage, String? perfil})
    : _storage = storage ?? const FlutterSecureStorage(),
      _perfil = perfil ?? perfilDelEntorno();

  final FlutterSecureStorage _storage;

  /// Sufijo de la clave, para poder tener **varias identidades en la misma
  /// máquina**. Vacío en un aparato de verdad.
  final String _perfil;

  static const _key = 'device_id';
  static const _uuid = Uuid();

  /// La variable de entorno que separa identidades al probar la sincronización
  /// en una sola computadora.
  ///
  /// Hace falta porque el resto del estado sí se aísla con `HOME` y
  /// `XDG_DATA_HOME` —la base y las preferencias caen bajo ellos— pero el
  /// llavero **no**: en Linux `flutter_secure_storage` guarda bajo la clave
  /// `<APPLICATION_ID>.secureStorage` y habla con el demonio por DBus, así que
  /// dos procesos de la misma app leen la misma entrada por muy separados que
  /// tengan los directorios. Sin esto, dos instancias comparten device_id y la
  /// red de sincronización las ve como un solo aparato.
  static const variableDePerfil = 'VULP_PERFIL';

  /// Solo en escritorio: en un teléfono no hay forma de definir la variable, y
  /// ahí la identidad tiene que ser una y sin excepciones.
  static String perfilDelEntorno() {
    if (Platform.isAndroid || Platform.isIOS) return '';
    return Platform.environment[variableDePerfil] ?? '';
  }

  /// La clave donde vive la identidad de ESTE perfil.
  ///
  /// Sin perfil es exactamente la de siempre, así que un aparato ya instalado
  /// conserva su device_id: cambiarlo lo sacaría de su grupo de sincronización.
  String get clave => _perfil.isEmpty ? _key : '${_key}_$_perfil';

  Future<String> obtenerOCrear() async {
    final existente = await _storage.read(key: clave);
    if (existente != null) return existente;
    final nuevo = _uuid.v4();
    await _storage.write(key: clave, value: nuevo);
    return nuevo;
  }
}
