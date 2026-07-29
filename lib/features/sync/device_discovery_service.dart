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
              final direccion = service.hostAddress;
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
