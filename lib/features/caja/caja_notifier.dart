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
    this.ultimo,
  });

  const EstadoCaja.vacia()
    : cajaInicial = 0,
      efectivoDelTramo = 0,
      momentosAnotados = const {},
      ultimo = null;

  /// Lo que quedó en la caja en el último corte. Sin cortes todavía, cero.
  final double cajaInicial;

  /// El efectivo cobrado **desde** ese corte. Lo de antes no cuenta: ya se
  /// guardó.
  final double efectivoDelTramo;

  final Set<MomentoCorte> momentosAnotados;

  /// El último corte anotado hoy, o `null` si todavía no hay ninguno. Es el
  /// único que se puede rehacer.
  final CorteCaja? ultimo;

  /// Lo que debería haber en la caja ahora mismo. Es el número contra el que se
  /// compara el conteo a mano.
  double get cajaTotal => cajaInicial + efectivoDelTramo;

  /// El corte que toca, o `null` si el día ya se cerró.
  MomentoCorte? get siguiente => siguienteMomento(momentosAnotados);
}

/// Los cortes de caja del día de hoy.
///
/// **`registrar`, y nada más.** Un corte se cuenta, se valida y se cierra. No
/// hay `eliminar` ni un `actualizar` que apunte a cualquier fila: eso sería
/// inventarle un ciclo de vida que no tiene (decisión 0009) y permitiría
/// reescribir el historial del día, que es lo que un corte existe para impedir.
///
/// La única excepción es **rehacer el último**, y entró porque el diseño rígido
/// falló en el primer uso real: un cierre anotado con un 5 y quince ceros dejó
/// el día cerrado en ₡5 000 000 000 000 000 sin forma de arreglarlo desde la
/// app. Un dedazo no puede inutilizar la jornada.
///
/// Solo el último, y por la misma razón que existe el resto de la regla: los
/// anteriores ya sirvieron de frontera para el efectivo que se contó después, y
/// cambiarlos movería tramos que ya se cuadraron.
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
      ultimo: cortes.isEmpty ? null : cortes.last,
    );
  }

  /// Anota un corte, o corrige el último si es el que se vuelve a pulsar.
  ///
  /// Devuelve `false` si el momento no era ni el que toca ni el último anotado.
  ///
  /// La comprobación está acá y no solo en los botones: el botón deshabilitado
  /// es una comodidad de la pantalla, y esto es lo que impide que un cierre
  /// entre sin haber pasado por la apertura. Sin ella, un corte fuera de orden
  /// dejaría la caja inicial apuntando a un tramo que nunca existió.
  Future<bool> registrar(MomentoCorte momento, double monto) async {
    final estado = state.valueOrNull ?? const EstadoCaja.vacia();
    final ahora = DateTime.now();
    final dao = await _dao;

    if (estado.siguiente == momento) {
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
    } else if (estado.ultimo?.momento == momento) {
      await dao.corregirMonto(estado.ultimo!.id, monto, ahora);
    } else {
      return false;
    }

    state = AsyncData(await _calcular(dao, ahora));
    return true;
  }
}

final cajaNotifierProvider = AsyncNotifierProvider<CajaNotifier, EstadoCaja>(CajaNotifier.new);
