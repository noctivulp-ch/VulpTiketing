import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import '../auth/device_identity_service.dart';
import '../auth/sesion_notifier.dart';
import 'device_discovery_service.dart';
import 'sync_client.dart';
import 'sync_group_coordinator.dart';
import 'sync_server.dart';

enum EstadoSync { idle, syncing, error }

/// Fachada Riverpod-facing: compone DeviceDiscoveryService + SyncServer +
/// SyncClient + SyncGroupCoordinator (decisiones 0019/0022). Expone estado
/// a la UI y si todos los dispositivos conocidos están sincronizados
/// (consultado por `ProductoNotifier.purgar`, decisión 0015).
///
/// Estado real de esta implementación: descubrimiento (0021), transporte
/// (0022, servidor HTTP + cliente) y sync **intra-grupo** (pares del mismo
/// rol, pairwise) ya funcionan de verdad. Lo que **falta** es el protocolo
/// de coordinación *entre* grupos (Gerente ↔ Registradora vía sus
/// orquestadores electos — el paso 3/4 del diseño de 0007): hoy cada
/// dispositivo solo sincroniza con pares de su propio rol, no cruza a la
/// otra red. Por eso [todosLosDispositivosSincronizados] sigue devolviendo
/// `false`: sin el handshake entre orquestadores, un Gerente y una
/// Registradora nunca terminan de verse entre sí, y ese caso es
/// justamente el que le importa a la purga (0015).
///
/// Tampoco se llama a [iniciarSync] automáticamente desde ningún lado
/// todavía (ej. al abrir la app) — es una decisión de producto pendiente
/// (¿siempre en segundo plano? ¿solo cuando el usuario lo activa?), no
/// bloquea que el transporte ya funcione.
class SyncNotifier extends Notifier<EstadoSync> {
  final _discovery = BonsoirDeviceDiscoveryService();
  final _coordinator = const SyncGroupCoordinator();
  final _deviceIdentity = DeviceIdentityService();
  SyncServer? _server;

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

    final db = await ref.read(databaseProvider.future);
    final miDeviceId = await _deviceIdentity.obtenerOCrear();
    _miDeviceId = miDeviceId;

    final server = SyncServer(db);
    final puerto = await server.iniciar();
    _server = server;
    state = EstadoSync.syncing;

    await _discovery.anunciar(deviceId: miDeviceId, rol: rol.name, puerto: puerto);

    final cliente = SyncClient(db);
    _discovery.descubrirPares().listen(
      (pares) async {
        _paresDelMismoRol = pares.where((p) => p.rol == rol.name).toList();
        for (final par in _paresDelMismoRol) {
          try {
            await cliente.sincronizarCon(par);
          } catch (_) {
            // Un peer que se desconecta a mitad de sync no debe tumbar toda
            // la sesión — se reintenta solo en el próximo ciclo de
            // descubrimiento (mismo principio de robustez best-effort de
            // 0007: el peor caso es una sync redundante, no una caída).
          }
        }
      },
      onError: (_) => state = EstadoSync.error,
    );
  }

  Future<void> detenerSync() async {
    await _discovery.detener();
    await _server?.detener();
    _server = null;
    _paresDelMismoRol = [];
    state = EstadoSync.idle;
  }
}

final syncNotifierProvider = NotifierProvider<SyncNotifier, EstadoSync>(SyncNotifier.new);
