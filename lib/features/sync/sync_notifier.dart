import 'package:flutter_riverpod/flutter_riverpod.dart';

enum EstadoSync { idle, syncing, error }

/// Fachada Riverpod-facing: compone DeviceDiscoveryService +
/// SyncGroupCoordinator + RowSyncEngine (decision 0019). Expone el estado a
/// la UI y si todos los dispositivos conocidos estan sincronizados
/// (consultado por ProductoNotifier.purgar — decision 0015).
///
/// TODO: implementar una vez elegido el paquete de mDNS
/// (ver device_discovery_service.dart). Mientras tanto,
/// [todosLosDispositivosSincronizados] devuelve `false` a proposito —
/// mejor dejar Purgar bloqueado por defecto que arriesgar un falso
/// positivo antes de que sync exista de verdad.
class SyncNotifier extends Notifier<EstadoSync> {
  @override
  EstadoSync build() => EstadoSync.idle;

  bool get todosLosDispositivosSincronizados => false;

  Future<void> iniciarSync() {
    throw UnimplementedError('TODO(0007): pendiente DeviceDiscoveryService');
  }

  Future<void> detenerSync() {
    throw UnimplementedError('TODO(0007): pendiente DeviceDiscoveryService');
  }
}

final syncNotifierProvider =
    NotifierProvider<SyncNotifier, EstadoSync>(SyncNotifier.new);
