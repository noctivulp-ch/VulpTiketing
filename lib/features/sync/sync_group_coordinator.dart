import 'device_discovery_service.dart';

/// Calcula el orquestador de un grupo de rol (UUID mas bajo visible —
/// decision 0007) y si el grupo tiene tareas pendientes. No sabe como se
/// mezclan filas (eso es RowSyncEngine) — decision 0019.
///
/// La pertenencia a un grupo es una propiedad en vivo, no fija (addendum de
/// la decision 0007): quien llama arma [paresVisiblesDelMismoRol] a partir
/// del rol *actual* de cada dispositivo, no de un registro estatico.
class SyncGroupCoordinator {
  const SyncGroupCoordinator();

  /// Regla determinista y best-effort (no consenso distribuido estricto,
  /// ver 0007): el deviceId que ordena primero alfabeticamente entre los
  /// pares visibles de este mismo rol (incluyendome) es el orquestador.
  String calcularOrquestador({
    required String miDeviceId,
    required List<PeerVisible> paresVisiblesDelMismoRol,
  }) {
    final ids = [miDeviceId, ...paresVisiblesDelMismoRol.map((p) => p.deviceId)]..sort();
    return ids.first;
  }

  bool esOrquestador({
    required String miDeviceId,
    required List<PeerVisible> paresVisiblesDelMismoRol,
  }) {
    return calcularOrquestador(
          miDeviceId: miDeviceId,
          paresVisiblesDelMismoRol: paresVisiblesDelMismoRol,
        ) ==
        miDeviceId;
  }
}
