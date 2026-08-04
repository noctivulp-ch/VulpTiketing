import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sesion_notifier.dart';

/// Hashea/verifica la contrasena local del dispositivo (Argon2id, decision
/// 0011). No sabe nada de sesion ni de UI (decision 0019).
///
/// La contrasena SIEMPRE existe: cada rol arranca con una contrasena de
/// fabrica hardcodeada (nunca se "crea" una en el Login — eso no estaba
/// contemplado, ver 0002/0011). Solo se puede cambiar despues, ya
/// logueado, desde Configuracion.
class CredencialesService {
  CredencialesService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // Parametros interactivos recomendados por OWASP para Argon2id (~19 MiB,
  // 2 iteraciones) — suficiente para una contrasena de dispositivo local,
  // no una API expuesta a internet.
  static final _algoritmo = Argon2id(parallelism: 1, memory: 19456, iterations: 2, hashLength: 32);

  /// Las de fabrica, **distintas por rol**.
  ///
  /// Son conocidas a proposito y estan a la vista en este archivo: el modelo es
  /// el de un router, donde la clave de la etiqueta sirve para entrar la primera
  /// vez y se espera que se cambie en uso. No son un secreto, son un arranque.
  ///
  /// La de Gerente es mas larga porque es la que abre lo que no se puede
  /// deshacer: purgar productos, restaurar un backup encima de la base, y ver el
  /// token que deja manejar la app desde fuera. La de Registradora se queda
  /// corta a proposito — se teclea decenas de veces al dia en un mostrador con
  /// gente esperando, y ahi una clave larga se acaba anotando en un papel
  /// pegado a la caja, que es peor que una corta.
  static const _contrasenasDeFabrica = {Rol.gerente: 'Gen@1359#', Rol.registradora: '1359'};

  String _keyHash(Rol rol) => 'contrasena_hash_${rol.name}';
  String _keySalt(Rol rol) => 'contrasena_salt_${rol.name}';

  Future<bool> verificar(Rol rol, String contrasena) async {
    final saltGuardado = await _storage.read(key: _keySalt(rol));
    final hashGuardado = await _storage.read(key: _keyHash(rol));

    if (saltGuardado == null || hashGuardado == null) {
      // Este rol nunca cambio su contrasena en este dispositivo todavia —
      // compara contra la de fabrica. No es un flujo de "primer uso",
      // simplemente el estado por defecto hasta que alguien la cambie.
      //
      // Es por ROL: cambiar la de Gerente no le toca la suya a Registradora, y
      // al reves. Cada una vive en su propia entrada del almacen.
      return contrasena == _contrasenasDeFabrica[rol];
    }

    final hash = await _derivar(contrasena, base64Decode(saltGuardado));
    return base64Encode(hash) == hashGuardado;
  }

  /// Requiere la contrasena actual antes de cambiarla — se invoca ya
  /// logueado, desde Configuracion (no existe en el Login).
  Future<void> cambiarContrasena(Rol rol, String nuevaContrasena) async {
    final salt = _generarSalt();
    final hash = await _derivar(nuevaContrasena, salt);
    await _storage.write(key: _keySalt(rol), value: base64Encode(salt));
    await _storage.write(key: _keyHash(rol), value: base64Encode(hash));
  }

  Future<List<int>> _derivar(String contrasena, List<int> salt) async {
    final secretKey = await _algoritmo.deriveKeyFromPassword(password: contrasena, nonce: salt);
    return secretKey.extractBytes();
  }

  List<int> _generarSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }
}
