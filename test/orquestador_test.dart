import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/sync/device_discovery_service.dart';
import 'package:vulp_tiketing/features/sync/sync_group_coordinator.dart';

/// Quién orquesta un grupo, y —sobre todo— cuándo NO hay orquestador.
///
/// El fallo que motivó estas pruebas: con la lista de pares vacía,
/// `[miDeviceId].first == miDeviceId` se cumple siempre, así que **todos los
/// aparatos se declaraban orquestador de un grupo de uno**. En pantalla salía
/// "0 dispositivos visibles — este es el orquestador", que se lee como que la
/// red va bien justo en el caso en que no se está viendo a nadie.
///
/// Lo detectó el dueño leyendo las dos pantallas a la vez: las dos decían ser
/// el orquestador, y eso no puede pasar en un grupo con dos miembros.
PeerVisible _par(String id) =>
    PeerVisible(deviceId: id, direccion: '192.168.1.9', rol: 'registradora', puerto: 1234);

void main() {
  const coordinador = SyncGroupCoordinator();

  bool orquesta(String yo, List<String> pares) => coordinador.esOrquestador(
    miDeviceId: yo,
    paresVisiblesDelMismoRol: [for (final p in pares) _par(p)],
  );

  group('sin pares no hay orquestador', () {
    test('un aparato solo NO es orquestador', () {
      // Orquestar es coordinar CON alguien: el paso 3/4 de la decisión 0007 es
      // un handshake entre los orquestadores de los dos grupos, y no hay nada
      // que coordinar sin un segundo aparato.
      expect(orquesta('aaa', const []), isFalse);
    });

    test('da igual cuál sea su id', () {
      // El fallo venía de comparar contra una lista de un solo elemento, así
      // que se cumplía para cualquier id.
      for (final id in ['aaa', 'zzz', '000', 'ffffffff']) {
        expect(orquesta(id, const []), isFalse, reason: id);
      }
    });
  });

  group('con pares, manda el id más bajo', () {
    test('el menor orquesta', () {
      expect(orquesta('aaa', const ['bbb', 'ccc']), isTrue);
    });

    test('y los demás no', () {
      expect(orquesta('bbb', const ['aaa', 'ccc']), isFalse);
      expect(orquesta('ccc', const ['aaa', 'bbb']), isFalse);
    });

    test('solo UNO orquesta en un grupo — que es lo que fallaba', () {
      // La comprobación que hizo saltar el fallo: dos aparatos que se ven no
      // pueden decir los dos que son el orquestador.
      const grupo = ['aaa', 'bbb', 'ccc'];
      final lideres = grupo
          .where((yo) => orquesta(yo, grupo.where((o) => o != yo).toList()))
          .toList();

      expect(lideres, ['aaa']);
    });

    test('el orden en que se descubren no cambia quién manda', () {
      // Se recalcula en cada ciclo de mDNS y los eventos llegan en cualquier
      // orden: si el resultado dependiera de eso, el liderazgo bailaría solo.
      expect(orquesta('aaa', const ['ccc', 'bbb']), isTrue);
      expect(orquesta('aaa', const ['bbb', 'ccc']), isTrue);
    });
  });

  test('calcularOrquestador sigue devolviendo el id, aunque sea uno solo', () {
    // `esOrquestador` es el que decide si hay grupo; el cálculo puro se deja
    // como estaba para no romper a quien lo use para otra cosa.
    expect(
      coordinador.calcularOrquestador(miDeviceId: 'aaa', paresVisiblesDelMismoRol: const []),
      'aaa',
    );
  });
}
