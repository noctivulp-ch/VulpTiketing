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

  /// Si este dispositivo es el orquestador de su grupo.
  ///
  /// **Sin pares a la vista no hay orquestador**, y devuelve `false`. Antes
  /// devolvia `true`: con la lista vacia, `[miDeviceId].first == miDeviceId` se
  /// cumple siempre, asi que un aparato solo se declaraba lider de un grupo de
  /// uno.
  ///
  /// No es un tecnicismo. Orquestar es coordinar CON alguien —el paso 3/4 de
  /// 0007 es un handshake entre los orquestadores de los dos grupos— y no hay
  /// nada que coordinar sin un segundo aparato. El sintoma en pantalla era
  /// "0 dispositivos visibles — este es el orquestador", que se lee como que la
  /// red funciona cuando en realidad no se esta viendo a nadie: es justo el
  /// caso en el que hay que sospechar, y la app decia lo contrario.
  bool esOrquestador({
    required String miDeviceId,
    required List<PeerVisible> paresVisiblesDelMismoRol,
  }) {
    if (paresVisiblesDelMismoRol.isEmpty) return false;
    return calcularOrquestador(
          miDeviceId: miDeviceId,
          paresVisiblesDelMismoRol: paresVisiblesDelMismoRol,
        ) ==
        miDeviceId;
  }
}
