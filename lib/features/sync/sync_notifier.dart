import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/device_identity_service.dart';
import '../auth/sesion_notifier.dart';
import 'device_discovery_service.dart';
import 'sync_group_coordinator.dart';

enum EstadoSync { idle, syncing, error }

/// Fachada Riverpod-facing: compone DeviceDiscoveryService +
/// SyncGroupCoordinator + RowSyncEngine (decision 0019). Expone estado a
/// la UI y si todos los dispositivos conocidos están sincronizados
/// (consultado por `ProductoNotifier.purgar`, decisión 0015).
///
/// Estado real de esta implementación: descubrimiento (0021, `bonsoir`) y
/// elección de orquestador (0007) ya funcionan de verdad. Lo que **falta**
/// es el protocolo de transporte para intercambiar filas entre
/// dispositivos una vez que se descubren — esa es una decisión de
/// arquitectura aparte, todavía no tomada (ver
/// docs/arquitectura/sincronizacion.md). Por eso
/// [todosLosDispositivosSincronizados] sigue devolviendo `false`: sin ese
/// protocolo ninguna sync se completa realmente todavía, decir que "está
/// sincronizado" sería falso.
///
/// Tampoco se llama a [iniciarSync] automáticamente desde ningún lado
/// todavía (ej. al abrir la app) — eso se conecta cuando el protocolo de
/// transporte exista, no antes.
class SyncNotifier extends Notifier<EstadoSync> {
  final _discovery = BonsoirDeviceDiscoveryService();
  final _coordinator = const SyncGroupCoordinator();
  final _deviceIdentity = DeviceIdentityService();

  List<PeerVisible> _paresDelMismoRol = [];
  String? _miDeviceId;

  @override
  EstadoSync build() => EstadoSync.idle;

  bool get todosLosDispositivosSincronizados => false;

  bool get esOrquestadorDeMiGrupo {
    final miDeviceId = _miDeviceId;
    if (miDeviceId == null) return false;
    return _coordinator.esOrquestador(
      miDeviceId: miDeviceId,
      paresVisiblesDelMismoRol: _paresDelMismoRol,
    );
  }

  List<PeerVisible> get paresVisibles => _paresDelMismoRol;

  Future<void> iniciarSync() async {
    final rol = ref.read(sesionNotifierProvider);
    if (rol == null) return;

    final miDeviceId = await _deviceIdentity.obtenerOCrear();
    _miDeviceId = miDeviceId;
    state = EstadoSync.syncing;

    await _discovery.anunciar(deviceId: miDeviceId, rol: rol.name);
    _discovery.descubrirPares().listen(
      (pares) => _paresDelMismoRol = pares.where((p) => p.rol == rol.name).toList(),
      onError: (_) => state = EstadoSync.error,
    );
  }

  Future<void> detenerSync() async {
    await _discovery.detener();
    _paresDelMismoRol = [];
    state = EstadoSync.idle;
  }
}

final syncNotifierProvider = NotifierProvider<SyncNotifier, EstadoSync>(SyncNotifier.new);
