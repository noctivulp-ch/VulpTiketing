import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/auth/device_identity_service.dart';

/// Varias identidades en la misma computadora, para poder probar la red de
/// sincronización sin tener un teléfono por nodo.
///
/// El estado normal sí se aísla lanzando cada instancia con su `HOME` y su
/// `XDG_DATA_HOME` —la base y las preferencias caen ahí debajo—, pero el
/// llavero no: en Linux `flutter_secure_storage` guarda bajo
/// `<APPLICATION_ID>.secureStorage` y se consulta por DBus, así que dos
/// procesos de la misma app leen la misma entrada por muy separados que tengan
/// los directorios. Sin perfil, dos instancias comparten device_id y la red las
/// ve como un solo aparato.
void main() {
  test('sin perfil la clave es la de siempre', () async {
    // Lo más importante de todo el archivo: un aparato ya instalado conserva su
    // device_id. Cambiárselo lo sacaría de su grupo de sincronización.
    final almacen = _AlmacenFalso();
    final servicio = DeviceIdentityService(storage: almacen, perfil: '');

    await servicio.obtenerOCrear();

    expect(servicio.clave, 'device_id');
    expect(almacen.datos.keys, ['device_id']);
  });

  test('dos perfiles dan dos identidades distintas', () async {
    // Comparten el almacén a propósito: es exactamente lo que pasa en una sola
    // computadora, donde el llavero es uno para las dos instancias.
    final llaveroCompartido = _AlmacenFalso();

    final uno = await DeviceIdentityService(
      storage: llaveroCompartido,
      perfil: 'p1',
    ).obtenerOCrear();
    final dos = await DeviceIdentityService(
      storage: llaveroCompartido,
      perfil: 'p2',
    ).obtenerOCrear();

    expect(uno, isNot(dos));
    expect(llaveroCompartido.datos.keys, containsAll(['device_id_p1', 'device_id_p2']));
  });

  test('el mismo perfil conserva su identidad entre arranques', () async {
    // Si cambiara en cada arranque no se podría probar un reencuentro tras
    // reiniciar: cada vuelta sería un aparato nuevo para el grupo.
    final llavero = _AlmacenFalso();

    final primera = await DeviceIdentityService(storage: llavero, perfil: 'p1').obtenerOCrear();
    final segunda = await DeviceIdentityService(storage: llavero, perfil: 'p1').obtenerOCrear();

    expect(primera, segunda);
  });

  test('un perfil no ve la identidad de otro ni la de "sin perfil"', () async {
    final llavero = _AlmacenFalso();

    final sinPerfil = await DeviceIdentityService(storage: llavero, perfil: '').obtenerOCrear();
    final conPerfil = await DeviceIdentityService(storage: llavero, perfil: 'p1').obtenerOCrear();

    expect(sinPerfil, isNot(conPerfil));
  });
}

/// Un llavero en memoria. El de verdad no se puede usar en pruebas: su canal
/// nativo no es interceptable, y ya nos costó un test colgado.
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
