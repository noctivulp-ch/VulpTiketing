import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

/// Anuncia el rol activo de este dispositivo via mDNS y descubre pares
/// visibles en la red local. No sabe nada de LWW ni de que datos se
/// sincronizan (decision 0019).
///
/// Implementacion real con `bonsoir` (decision 0021) — unico paquete que
/// cubre Android+Linux+Windows con anunciar Y descubrir. En Linux depende
/// de `avahi-daemon` corriendo en el sistema (ver 0021); si no esta activo,
/// simplemente no se ve a otros dispositivos — no es un error fatal (0007:
/// la app funciona 100% offline sin sync).
abstract class DeviceDiscoveryService {
  /// [puerto] es el puerto REAL donde este dispositivo ya esta escuchando
  /// (asignado dinamicamente por el SO al arrancar SyncServer, nunca un
  /// numero fijo — decision 0022, evita coordinarlo/hardcodearlo en
  /// ningun lado. mDNS es justo el mecanismo para que los pares se enteren
  /// del puerto real sin adivinarlo).
  Future<void> anunciar({required String deviceId, required String rol, required int puerto});
  Stream<List<PeerVisible>> descubrirPares();
  Future<void> detener();
}

class PeerVisible {
  const PeerVisible({
    required this.deviceId,
    required this.rol,
    required this.direccion,
    required this.puerto,
  });

  final String deviceId;
  final String rol;
  final String direccion;
  final int puerto;
}

/// Tipo de servicio mDNS propio — sintaxis exigida por RFC 6335:
/// "_nombre._tcp", primera parte <= 15 caracteres.
const _tipoServicio = '_vulptiketing._tcp';

class BonsoirDeviceDiscoveryService implements DeviceDiscoveryService {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  @override
  Future<void> anunciar({
    required String deviceId,
    required String rol,
    required int puerto,
  }) async {
    final service = BonsoirService(
      name: deviceId,
      type: _tipoServicio,
      port: puerto,
      attributes: {'rol': rol},
    );
    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  /// La dirección con la que SÍ se puede abrir una conexión, de todas las que
  /// anuncia un aparato.
  ///
  /// `service.hostAddress` devuelve la primera de la lista, y esa elección no
  /// es inocente: un Android anuncia a la vez su IPv4, una IPv6 **link-local**
  /// (`fe80::…`) y a veces una ULA. Si la primera sale link-local, el peer
  /// queda con una dirección **a la que no se puede llegar** — una `fe80::` no
  /// se enruta sin decir por qué interfaz sale.
  ///
  /// Se vio en el aparato: dos Registradoras en la misma WiFi, una anunciándose
  /// por IPv4 y la otra por `fe80::`, y la sincronización quedaba **de una sola
  /// dirección** — la que tenía IPv4 traía datos del otro, y al revés nunca.
  /// Reproducible, y sin dejar rastro: el cliente se traga los fallos de
  /// conexión por peer para que uno caído no tumbe la ronda.
  ///
  /// Se prefiere IPv4 porque es lo que siempre funciona en la red de una soda.
  /// Una IPv6 normal sirve igual y se devuelve entre corchetes, que es como
  /// tiene que ir dentro de una URL. Las link-local se descartan.
  static String? direccionUtilDe(BonsoirService service) {
    final direcciones = service.hostAddresses;
    if (direcciones.isEmpty) return service.hostAddress;

    for (final d in direcciones) {
      if (!d.contains(':')) return d; // IPv4
    }
    for (final d in direcciones) {
      // `fe80::` solo vale con el índice de interfaz, que no viaja en la URL.
      if (d.toLowerCase().startsWith('fe80:')) continue;
      return '[${d.split('%').first}]';
    }
    return null;
  }

  @override
  Stream<List<PeerVisible>> descubrirPares() {
    final discovery = BonsoirDiscovery(type: _tipoServicio);
    _discovery = discovery;

    final pares = <String, PeerVisible>{};
    late final StreamController<List<PeerVisible>> controller;
    controller = StreamController<List<PeerVisible>>.broadcast(
      onListen: () async {
        await discovery.initialize();
        discovery.eventStream?.listen((evento) {
          switch (evento) {
            case BonsoirDiscoveryServiceFoundEvent(:final service):
              discovery.serviceResolver.resolveService(service);
            case BonsoirDiscoveryServiceResolvedEvent(:final service):
              final direccion = direccionUtilDe(service);
              if (direccion == null) break;
              pares[service.name] = PeerVisible(
                deviceId: service.name,
                rol: service.attributes['rol'] ?? '',
                direccion: direccion,
                puerto: service.port,
              );
              controller.add(pares.values.toList());
            case BonsoirDiscoveryServiceLostEvent(:final service):
              pares.remove(service.name);
              controller.add(pares.values.toList());
            default:
              break;
          }
        });
        await discovery.start();
      },
      onCancel: () => discovery.stop(),
    );
    return controller.stream;
  }

  @override
  Future<void> detener() async {
    await _broadcast?.stop();
    await _discovery?.stop();
  }
}
