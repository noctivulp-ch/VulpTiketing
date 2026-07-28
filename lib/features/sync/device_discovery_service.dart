/// Anuncia el rol activo de este dispositivo via mDNS y descubre pares
/// visibles en la red local. No sabe nada de LWW ni de que datos se
/// sincronizan (decision 0019).
///
/// TODO: elegir el paquete de mDNS que soporte anunciar (advertise) Y
/// descubrir (discover) en Android + Linux + Windows a la vez — pendiente
/// de validar (candidatos: multicast_dns, nsd). A proposito NO se agrego
/// ningun paquete de mDNS a pubspec.yaml todavia, para no comprometerse
/// antes de confirmar soporte multiplataforma real.
abstract class DeviceDiscoveryService {
  Future<void> anunciar({required String deviceId, required String rol});
  Stream<List<PeerVisible>> descubrirPares();
  Future<void> detener();
}

class PeerVisible {
  const PeerVisible({
    required this.deviceId,
    required this.rol,
    required this.direccion,
  });

  final String deviceId;
  final String rol;
  final String direccion;
}
