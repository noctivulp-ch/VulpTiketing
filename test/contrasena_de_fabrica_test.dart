import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/auth/credenciales_service.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';

/// Las contraseñas de fábrica son **distintas por rol**.
///
/// El modelo es el de un router: la clave viene puesta, sirve para entrar la
/// primera vez y se espera que se cambie en uso. No son un secreto —están a la
/// vista en el código—, son un arranque.
///
/// Lo que sí importa comprobar es que **no se pisan entre sí**: la de Gerente
/// abre lo que no se puede deshacer (purgar, restaurar un backup encima de la
/// base, ver el token del harness), así que aceptar ahí la de Registradora
/// borraría de un plumazo la separación de permisos entera.
void main() {
  CredencialesService servicio() => CredencialesService(storage: _AlmacenFalso());

  test('cada rol entra con la suya', () async {
    final s = servicio();

    expect(await s.verificar(Rol.gerente, 'Gen@1359#'), isTrue);
    expect(await s.verificar(Rol.registradora, '1359'), isTrue);
  });

  test('la de Registradora NO abre Gerente', () async {
    // El caso que da sentido a todo: si la corta valiera para las dos, quien
    // atiende la caja podría purgar el catálogo o restaurar un backup encima.
    final s = servicio();

    expect(await s.verificar(Rol.gerente, '1359'), isFalse);
  });

  test('la de Gerente tampoco vale como la de Registradora', () async {
    // La otra dirección importa menos, pero una clave que abre las dos puertas
    // deja de identificar quién está delante.
    final s = servicio();

    expect(await s.verificar(Rol.registradora, 'Gen@1359#'), isFalse);
  });

  test('nada más entra', () async {
    final s = servicio();

    for (final intento in ['', ' ', '0000', 'gen@1359#', 'Gen@1359', '13590']) {
      expect(await s.verificar(Rol.gerente, intento), isFalse, reason: '"$intento"');
      expect(await s.verificar(Rol.registradora, intento), isFalse, reason: '"$intento"');
    }
  });

  test('la de Gerente no es solo dígitos', () async {
    // Es la única defensa real que tiene de fábrica: contra alguien mirando por
    // encima del hombro, cuatro dígitos se memorizan de una.
    final s = servicio();

    expect(await s.verificar(Rol.gerente, 'Gen@1359#'), isTrue);
    expect(RegExp(r'^\d+$').hasMatch('Gen@1359#'), isFalse);
  });

  test('cambiar la de un rol no toca la del otro', () async {
    // Viven en entradas separadas del almacén. Si compartieran una, cambiar la
    // del Gerente dejaría a la Registradora fuera sin avisar.
    final s = servicio();

    await s.cambiarContrasena(Rol.gerente, 'otra-cosa');

    expect(await s.verificar(Rol.gerente, 'otra-cosa'), isTrue);
    expect(await s.verificar(Rol.gerente, 'Gen@1359#'), isFalse, reason: 'la de fábrica caducó');
    expect(await s.verificar(Rol.registradora, '1359'), isTrue, reason: 'la otra sigue igual');
  });
}

/// Un llavero en memoria. El de verdad no se puede usar en pruebas: su canal
/// nativo no es interceptable.
class _AlmacenFalso implements FlutterSecureStorage {
  final datos = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async => datos[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (value == null) {
      datos.remove(key);
    } else {
      datos[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
