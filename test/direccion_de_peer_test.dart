import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/sync/device_discovery_service.dart';

/// Con qué dirección se conecta a un aparato descubierto.
///
/// Parece un detalle y costó una tarde de teléfonos. Un Android anuncia a la
/// vez su IPv4, una IPv6 **link-local** (`fe80::…`) y a veces una ULA.
/// `service.hostAddress` devuelve **la primera de la lista**, y si esa sale
/// link-local el peer queda con una dirección a la que no se puede llegar: una
/// `fe80::` no se enruta sin decir por qué interfaz sale.
///
/// El síntoma en el aparato fue una sincronización **de una sola dirección**:
/// dos Registradoras en la misma WiFi, la que anunciaba IPv4 traía datos de la
/// otra, y al revés nunca. Reproducible, y sin rastro — el cliente se tragaba
/// los fallos de conexión en silencio para que un peer caído no tumbara la
/// ronda.
BonsoirService _servicioCon(List<String> direcciones) => BonsoirService(
  name: 'aparato',
  type: '_vulptiketing._tcp',
  port: 4321,
  hostAddresses: direcciones,
);

void main() {
  String? direccionDe(List<String> direcciones) =>
      BonsoirDeviceDiscoveryService.direccionUtilDe(_servicioCon(direcciones));

  test('con IPv4 y link-local, gana la IPv4', () {
    // El caso exacto que rompía: así se anuncia un Android real.
    expect(direccionDe(['fe80::280e:65ff:fe16:d1c2%wlan0', '192.168.10.33']), '192.168.10.33');
  });

  test('da igual el orden en que las anuncie', () {
    // No se puede depender de que la IPv4 venga primera: el orden lo decide el
    // sistema y cambia entre modelos.
    expect(direccionDe(['192.168.10.33', 'fe80::1%wlan0']), '192.168.10.33');
  });

  test('una link-local sola se descarta', () {
    // Mejor no tener peer que tener uno inalcanzable: un peer que nunca
    // responde deja la sincronización fallando en cada ronda, para siempre.
    expect(direccionDe(['fe80::280e:65ff:fe16:d1c2%wlan0']), isNull);
  });

  test('una IPv6 de verdad vale, y va entre corchetes', () {
    // Dentro de una URL, una IPv6 sin corchetes no se puede parsear: los dos
    // puntos se confunden con el separador del puerto.
    expect(
      direccionDe(['fd74:ae1:b69a:e600:280e:65ff:fe16:d1c2']),
      '[fd74:ae1:b69a:e600:280e:65ff:fe16:d1c2]',
    );
  });

  test('a la IPv6 se le quita el índice de interfaz', () {
    // `%wlan0` no tiene sentido en el otro extremo y rompe la URL.
    expect(direccionDe(['fd74:ae1:b69a::1%wlan0']), '[fd74:ae1:b69a::1]');
  });

  test('la IPv4 gana también a una IPv6 válida', () {
    // No por nada técnico: es la que siempre funciona en la red de una soda, y
    // no hay razón para arriesgar con la otra.
    expect(direccionDe(['fd74:ae1::1', '10.0.0.5']), '10.0.0.5');
  });

  test('sin ninguna dirección no se inventa un peer', () {
    expect(direccionDe([]), isNull);
  });

  test('la URL que sale es parseable en los dos casos', () {
    // La comprobación de verdad: que `Uri.http` acepte lo que devolvemos. Es lo
    // que hace `SyncClient`, y donde una IPv6 mal armada revienta.
    for (final direcciones in [
      ['192.168.10.33'],
      ['fd74:ae1:b69a::1'],
    ]) {
      final direccion = direccionDe(direcciones)!;
      final uri = Uri.http('$direccion:4321', '/sync/exportar');
      expect(uri.port, 4321, reason: 'el puerto se perdió en "$direccion"');
      expect(uri.host, isNotEmpty);
    }
  });
}
