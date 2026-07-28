import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/db_providers.dart';
import 'linea_venta_model.dart';
import 'venta_dao.dart';
import 'venta_model.dart';
import 'venta_notifier.dart';

const _uuid = Uuid();

class VentaEnCurso {
  const VentaEnCurso({this.lineas = const [], this.detalle});

  final List<LineaVenta> lineas;
  final String? detalle;

  double get total =>
      lineas.fold(0, (suma, l) => suma + l.precioAplicado * l.cantidad);

  VentaEnCurso copyWith({List<LineaVenta>? lineas, String? detalle}) {
    return VentaEnCurso(
      lineas: lineas ?? this.lineas,
      detalle: detalle ?? this.detalle,
    );
  }
}

/// El "carrito" de una venta en construccion (decision 0019) — nunca se usa
/// para editar/borrar una venta ya guardada, eso es VentaNotifier.revertir().
class VentaEnCursoNotifier extends Notifier<VentaEnCurso> {
  // OJO: se regenera cada vez que este Notifier se reconstruye. guardar()
  // llama ref.invalidateSelf() al final justamente para forzar una
  // reconstruccion y así obtener un id nuevo para la siguiente venta — sin
  // eso, dos ventas seguidas terminarían compartiendo el mismo id.
  final String ventaIdBorrador = _uuid.v4();

  @override
  VentaEnCurso build() => const VentaEnCurso();

  void agregarLineaDeCatalogo({
    required String productoId,
    required double precioAplicado,
    int cantidad = 1,
    String? nota,
  }) {
    _agregarLinea(LineaVenta(
      id: _uuid.v4(),
      ventaId: ventaIdBorrador,
      productoId: productoId,
      precioAplicado: precioAplicado,
      cantidad: cantidad,
      nota: nota,
      updatedAt: DateTime.now(),
    ));
  }

  /// Linea sin Producto de catalogo (decision 0016).
  void agregarLineaLibre({
    required String nombreLibre,
    required double precio,
    int cantidad = 1,
    String? nota,
  }) {
    _agregarLinea(LineaVenta(
      id: _uuid.v4(),
      ventaId: ventaIdBorrador,
      nombreLibre: nombreLibre,
      precioAplicado: precio,
      cantidad: cantidad,
      nota: nota,
      updatedAt: DateTime.now(),
    ));
  }

  void _agregarLinea(LineaVenta linea) {
    state = state.copyWith(lineas: [...state.lineas, linea]);
  }

  void quitarLinea(String lineaId) {
    state = state.copyWith(
      lineas: state.lineas.where((l) => l.id != lineaId).toList(),
    );
  }

  void editarLinea(
    String lineaId, {
    double? precioAplicado,
    int? cantidad,
    String? nota,
  }) {
    state = state.copyWith(
      lineas: [
        for (final l in state.lineas)
          if (l.id == lineaId)
            LineaVenta(
              id: l.id,
              ventaId: l.ventaId,
              productoId: l.productoId,
              nombreLibre: l.nombreLibre,
              precioAplicado: precioAplicado ?? l.precioAplicado,
              cantidad: cantidad ?? l.cantidad,
              nota: nota ?? l.nota,
              updatedAt: DateTime.now(),
            )
          else
            l,
      ],
    );
  }

  void setDetalle(String? detalle) {
    state = state.copyWith(detalle: detalle);
  }

  /// Persiste el borrador como Venta "activa" y arranca un carrito nuevo.
  Future<void> guardar() async {
    if (state.lineas.isEmpty) return;

    final db = await ref.read(databaseProvider.future);
    final dao = VentaDao(db);
    final venta = Venta(
      id: ventaIdBorrador,
      fechaHora: DateTime.now(),
      detalle: state.detalle,
      estado: EstadoVenta.activa,
      updatedAt: DateTime.now(),
    );
    await dao.guardar(venta, state.lineas);

    ref.invalidate(ventaNotifierProvider);
    ref.invalidateSelf(); // fuerza un ventaIdBorrador nuevo para la próxima venta
  }
}

final ventaEnCursoNotifierProvider =
    NotifierProvider<VentaEnCursoNotifier, VentaEnCurso>(
  VentaEnCursoNotifier.new,
);
