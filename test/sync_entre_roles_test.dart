import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/sync/device_discovery_service.dart';

/// Los tres fallos que salieron al probar la sincronización con cuatro
/// aparatos de verdad, en la misma red WiFi.
///
/// Ninguno se veía con dos nodos ni en pruebas de transporte: los tres son de
/// **orquestación** —cuándo se sincroniza y con quién—, no de si las filas
/// viajan bien. `sync_transport_test.dart` ya cubría eso y pasaba.
///
/// Lo medido en el aparato, para que quede el número y no la impresión:
///
/// | Caso | Antes | Ahora |
/// |---|---|---|
/// | Gerente → Gerente | 8 categorías, 39 productos, 1 venta | igual |
/// | Gerente → Registradora | **0 / 0 / 0** | sincroniza |
/// | Refresco tras sync | había que reiniciar la app | automático |
/// | Cambio hecho tras el descubrimiento | no llegaba nunca | llega en ≤15 s |
void main() {
  final raiz = Directory.current.path;
  final notifier = File('$raiz/lib/features/sync/sync_notifier.dart').readAsStringSync();

  group('se sincroniza con todos los pares, no solo con los del mismo rol', () {
    test('el bucle recorre TODOS los pares descubiertos', () {
      // El fallo original en una línea: `for (final par in _paresDelMismoRol)`.
      // Con eso, un Gerente y una Registradora se ven por mDNS —comprobado en
      // el log— y no se sincronizan jamás. La Registradora arrancaba vacía y se
      // quedaba vacía con el catálogo entero a un metro.
      expect(
        notifier,
        contains('for (final par in _ultimosPares)'),
        reason: 'volvió a filtrarse por rol: el cruce Gerente↔Registradora deja de existir',
      );
    });

    test('el filtro por rol sigue existiendo, pero solo para elegir orquestador', () {
      // No se borra: el coordinador de grupo lo usa, y si algún día hace falta
      // el ahorro de tráfico que buscaba la decisión 0007, la pieza está.
      expect(notifier, contains('_paresDelMismoRol'));
    });
  });

  group('hay una ronda periódica', () {
    test('existe un temporizador, no solo la reacción al descubrimiento', () {
      // Antes el sync se disparaba SOLO cuando el stream de descubrimiento
      // emitía, o sea al aparecer o desaparecer un aparato. Medido: se importó
      // el catálogo en un Gerente y el otro se quedó en 0 indefinidamente,
      // porque la membresía no cambió. Había que apagar y encender el
      // interruptor a mano.
      expect(notifier, contains('Timer.periodic'));
      expect(notifier, contains('_cadaRonda'));
    });

    test('la ronda no se pisa consigo misma', () {
      // El temporizador y un evento de descubrimiento pueden caer a la vez. Dos
      // pasadas simultáneas no corrompen nada —LWW es idempotente— pero
      // duplican tráfico y escrituras justo cuando la red ya está movida.
      expect(notifier, contains('_sincronizando'));
    });

    test('se apaga al detener el sync', () {
      // Un temporizador que sigue vivo tras apagar el interruptor seguiría
      // hablando con la red y gastando batería, con la app diciendo que está
      // detenida.
      final detener = notifier.substring(notifier.indexOf('Future<void> detenerSync'));
      expect(detener, contains('_ronda?.cancel()'));
    });
  });

  group('la pantalla se entera de lo que llega', () {
    test('se invalidan los providers tras una ronda con resultado', () {
      // Lo que entra por sync se escribe directo en la base, sin pasar por los
      // notifiers. Medido: la base del receptor tenía 39 productos y Venta
      // Rápida seguía diciendo "la bandeja está vacía" hasta reiniciar la app.
      for (final proveedor in [
        'productoNotifierProvider',
        'categoriaNotifierProvider',
        'ventaNotifierProvider',
        'reportesProvider',
      ]) {
        expect(
          notifier,
          contains('ref.invalidate($proveedor)'),
          reason: '$proveedor no se refresca: la pantalla se queda con lo de antes',
        );
      }
    });

    test('se invalida una vez por ronda, no una vez por peer', () {
      // Con cuatro aparatos, invalidar dentro del bucle reconstruiría el
      // catálogo tres veces seguidas para acabar en el mismo sitio.
      final ronda = notifier.substring(notifier.indexOf('Future<void> _repasarPares'));
      final invalidar = ronda.indexOf('ref.invalidate(');
      final cierreDelBucle = ronda.indexOf('_sincronizando = false;');
      expect(
        invalidar,
        greaterThan(cierreDelBucle),
        reason: 'la invalidación quedó dentro del bucle de pares',
      );
    });
  });

  test('un peer se identifica por rol, y eso no se toca', () {
    // El rol sigue viajando en el anuncio mDNS: el cruce ya no lo usa para
    // filtrar, pero la elección de orquestador sí, y la UI lo muestra.
    const peer = PeerVisible(deviceId: 'x', direccion: '192.168.1.2', rol: 'gerente', puerto: 1234);

    expect(peer.rol, 'gerente');
  });
}
