import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/db_providers.dart';
import 'corte_caja_dao.dart';
import 'corte_caja_model.dart';

const _uuid = Uuid();

/// Lo que la pantalla necesita saber de la caja de hoy.
///
/// Se calcula, no se guarda: guardar la caja esperada la dejaría vieja en
/// cuanto entrara una venta más, y el número solo sirve si es el de ahora.
class EstadoCaja {
  const EstadoCaja({
    required this.cajaInicial,
    required this.efectivoDelTramo,
    required this.momentosAnotados,
  });

  const EstadoCaja.vacia() : cajaInicial = 0, efectivoDelTramo = 0, momentosAnotados = const {};

  /// Lo que quedó en la caja en el último corte. Sin cortes todavía, cero.
  final double cajaInicial;

  /// El efectivo cobrado **desde** ese corte. Lo de antes no cuenta: ya se
  /// guardó.
  final double efectivoDelTramo;

  final Set<MomentoCorte> momentosAnotados;

  /// Lo que debería haber en la caja ahora mismo. Es el número contra el que se
  /// compara el conteo a mano.
  double get cajaTotal => cajaInicial + efectivoDelTramo;

  /// El corte que toca, o `null` si el día ya se cerró.
  MomentoCorte? get siguiente => siguienteMomento(momentosAnotados);
}

/// Los cortes de caja del día de hoy.
///
/// **Solo `registrar`.** Un corte no se edita ni se borra: se cuenta, se valida
/// y se da por cerrado — así lo describió el dueño. Darle `actualizar` o
/// `eliminar` "por consistencia" con otros notifiers sería inventarle al corte
/// un ciclo de vida que no tiene (decisión 0009), y de paso permitiría reescribir
/// un conteo ya cerrado, que es exactamente lo que un corte de caja existe para
/// impedir.
class CajaNotifier extends AsyncNotifier<EstadoCaja> {
  /// El DAO se resuelve en cada llamada, nunca se guarda en un campo — mismo
  /// motivo que en ProductoNotifier.
  Future<CorteCajaDao> get _dao async => CorteCajaDao(await ref.read(databaseProvider.future));

  @override
  Future<EstadoCaja> build() async {
    // `watch` y no `read`: si la base se reabre, el estado se recalcula.
    final dao = CorteCajaDao(await ref.watch(databaseProvider.future));
    return _calcular(dao, DateTime.now());
  }

  Future<EstadoCaja> _calcular(CorteCajaDao dao, DateTime ahora) async {
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final cortes = await dao.listarDelDia(diaDe(hoy));

    // Desde el último corte; sin cortes, desde que empezó el día. El final es
    // el día siguiente y no "ahora" para que una venta cobrada mientras se
    // mira la pantalla no quede fuera por unos segundos de reloj.
    final desde = cortes.isEmpty ? hoy : cortes.last.fechaHora;
    final efectivo = await dao.efectivoEntre(desde, hoy.add(const Duration(days: 1)));

    return EstadoCaja(
      cajaInicial: cortes.isEmpty ? 0 : cortes.last.monto,
      efectivoDelTramo: efectivo,
      momentosAnotados: {for (final corte in cortes) corte.momento},
    );
  }

  /// Anota un corte. Devuelve `false` si no era el que tocaba.
  ///
  /// La comprobación está acá y no solo en los botones: el botón deshabilitado
  /// es una comodidad de la pantalla, y esto es lo que impide que un cierre
  /// entre sin haber pasado por la apertura. Sin ella, un corte fuera de orden
  /// dejaría la caja inicial apuntando a un tramo que nunca existió.
  Future<bool> registrar(MomentoCorte momento, double monto) async {
    final estado = state.valueOrNull ?? const EstadoCaja.vacia();
    if (estado.siguiente != momento) return false;

    final ahora = DateTime.now();
    final dao = await _dao;
    await dao.insertar(
      CorteCaja(
        id: _uuid.v4(),
        dia: diaDe(ahora),
        momento: momento,
        monto: monto,
        fechaHora: ahora,
        updatedAt: ahora,
      ),
    );

    state = AsyncData(await _calcular(dao, ahora));
    return true;
  }
}

final cajaNotifierProvider = AsyncNotifierProvider<CajaNotifier, EstadoCaja>(CajaNotifier.new);
