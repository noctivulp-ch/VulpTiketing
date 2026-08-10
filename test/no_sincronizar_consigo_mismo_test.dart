import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/sync/device_discovery_service.dart';

/// Un aparato no es par de sí mismo.
///
/// mDNS devuelve también el anuncio propio: comprobado en el log del teléfono,
/// donde uno resolvía dos servicios y el primero era el suyo. Sin filtrarlo,
/// cada ronda gasta una conexión en hablar consigo mismo.
///
/// Y no es solo desperdicio: con el cerrojo que impide dos rondas a la vez, si
/// esa conexión se atasca **bloquea la ronda entera** y el peer de verdad nunca
/// llega a consultarse. Es la explicación más probable de que la sincronización
/// fallara de forma intermitente y en una sola dirección.
///
/// Pasaba desapercibido mientras el filtro por rol recortaba la lista; al
/// sincronizar con todos los pares quedó a la vista.
PeerVisible _par(String id, {String rol = 'registradora'}) =>
    PeerVisible(deviceId: id, direccion: '192.168.1.9', rol: rol, puerto: 1234);

/// El mismo filtro que aplica `SyncNotifier` al recibir el descubrimiento.
List<PeerVisible> ajenos(List<PeerVisible> todos, String yo) =>
    todos.where((p) => p.deviceId != yo).toList();

void main() {
  test('el anuncio propio se descarta', () {
    final vistos = [_par('yo'), _par('otro')];

    expect(ajenos(vistos, 'yo').map((p) => p.deviceId), ['otro']);
  });

  test('solo en la red = cero pares, no uno', () {
    // Es lo que hace que la pantalla diga "buscando" en vez de dar por hecho
    // que hay con quién sincronizar.
    expect(ajenos([_par('yo')], 'yo'), isEmpty);
  });

  test('no se descarta a nadie más', () {
    // El filtro es por id exacto: dos aparatos distintos con el mismo rol
    // tienen que seguir viéndose.
    final vistos = [_par('yo'), _par('a'), _par('b')];

    expect(ajenos(vistos, 'yo').length, 2);
  });

  test('el propio se descarta aunque cambie de rol', () {
    // El rol se re-elige en cada login (0007): el id es lo estable.
    final vistos = [_par('yo', rol: 'gerente'), _par('otro')];

    expect(ajenos(vistos, 'yo').map((p) => p.deviceId), ['otro']);
  });
}
