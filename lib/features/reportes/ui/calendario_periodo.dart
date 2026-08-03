import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../periodos_con_datos_provider.dart';

/// Calendario de un mes para elegir **un día** o **una semana**.
///
/// Reemplaza a `showDatePicker` por dos motivos, los dos reportados desde el
/// aparato:
///
/// - No decía qué días tienen ventas, así que elegir era prueba y error:
///   tocar, esperar la carga y ver "sin ventas".
/// - Para la semana pedía "elegí un día de la semana", que es una pregunta que
///   nadie se hace. Acá se resalta la **semana entera** bajo el dedo y se elige
///   como un bloque.
class CalendarioPeriodo extends ConsumerStatefulWidget {
  const CalendarioPeriodo({
    super.key,
    required this.actual,
    required this.hoy,
    required this.porSemana,
  });

  final DateTime actual;
  final DateTime hoy;

  /// `true` para elegir una semana completa; `false` para un día suelto.
  final bool porSemana;

  @override
  ConsumerState<CalendarioPeriodo> createState() => _CalendarioPeriodoState();
}

class _CalendarioPeriodoState extends ConsumerState<CalendarioPeriodo> {
  late DateTime _mes = DateTime(widget.actual.year, widget.actual.month);

  static const _diasDeSemana = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  DateTime get _hoySinHora => DateTime(widget.hoy.year, widget.hoy.month, widget.hoy.day);

  static DateTime _lunesDe(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  bool _mismaSemana(DateTime a, DateTime b) => _lunesDe(a) == _lunesDe(b);

  void _mover(int meses) {
    final destino = DateTime(_mes.year, _mes.month + meses);
    // Ni el futuro ni antes de que la app existiera: un calendario que deja
    // navegar a 1998 hace perder el tiempo en llegar a ninguna parte.
    if (destino.isAfter(DateTime(widget.hoy.year, widget.hoy.month))) return;
    if (destino.isBefore(DateTime(2020))) return;
    setState(() => _mes = destino);
  }

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(periodosConDatosProvider(_mes.year)).valueOrNull;
    final primero = DateTime(_mes.year, _mes.month);
    final diasDelMes = DateTime(_mes.year, _mes.month + 1, 0).day;
    // Lunes = 1: cuántas celdas vacías van antes del día 1.
    final huecoInicial = primero.weekday - 1;

    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BarraDeMes(mes: _mes, onMover: _mover),
          const SizedBox(height: BentoSpacing.unidad),
          Row(
            children: [
              for (final d in _diasDeSemana)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: lacaDe(context).textoAtenuadoEnBandeja,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: BentoSpacing.unidad / 2),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 7,
            mainAxisSpacing: BentoSpacing.unidad / 2,
            crossAxisSpacing: BentoSpacing.unidad / 2,
            children: [
              for (var i = 0; i < huecoInicial; i++) const SizedBox.shrink(),
              for (var dia = 1; dia <= diasDelMes; dia++)
                _CeldaDia(
                  fecha: DateTime(_mes.year, _mes.month, dia),
                  // Un día que todavía no llegó no tiene ventas que mirar.
                  habilitada: !DateTime(_mes.year, _mes.month, dia).isAfter(_hoySinHora),
                  seleccionada: widget.porSemana
                      ? _mismaSemana(DateTime(_mes.year, _mes.month, dia), widget.actual)
                      : DateTime(_mes.year, _mes.month, dia) ==
                            DateTime(widget.actual.year, widget.actual.month, widget.actual.day),
                  conVentas: datos?.tieneDia(DateTime(_mes.year, _mes.month, dia)) ?? false,
                  onTap: () => Navigator.pop(context, DateTime(_mes.year, _mes.month, dia)),
                ),
            ],
          ),
          if (widget.porSemana) ...[
            const SizedBox(height: BentoSpacing.unidad),
            Text(
              'Se elige la semana entera',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: lacaDe(context).textoAtenuadoEnBandeja),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarraDeMes extends StatelessWidget {
  const _BarraDeMes({required this.mes, required this.onMover});

  final DateTime mes;
  final ValueChanged<int> onMover;

  static const _nombres = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: () => onMover(-1),
        ),
        Expanded(
          child: Text(
            '${_nombres[mes.month - 1]} ${mes.year}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mes siguiente',
          onPressed: () => onMover(1),
        ),
      ],
    );
  }
}

/// Un día del calendario: pozo, como todo lo elegible de la app.
///
/// El punto de abajo es la marca de "acá hay ventas". Es un punto y no un color
/// de fondo porque el fondo ya lo usa la selección, y dos significados en el
/// mismo canal no se distinguen.
class _CeldaDia extends StatelessWidget {
  const _CeldaDia({
    required this.fecha,
    required this.habilitada,
    required this.seleccionada,
    required this.conVentas,
    required this.onTap,
  });

  final DateTime fecha;
  final bool habilitada;
  final bool seleccionada;
  final bool conVentas;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final acento = Theme.of(context).colorScheme.primary;

    return Opacity(
      opacity: habilitada ? 1 : 0.35,
      child: BentoPozo(
        onTap: habilitada ? onTap : null,
        seleccionado: seleccionada,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${fecha.day}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: seleccionada ? acento : laca.textoEnBandeja),
            ),
            const SizedBox(height: 2),
            // El hueco se reserva siempre: sin él, los días con ventas empujan
            // el número hacia arriba y la cuadrícula queda temblando.
            SizedBox(
              height: 4,
              width: 4,
              child: conVentas
                  ? DecoratedBox(
                      decoration: BoxDecoration(color: acento, shape: BoxShape.circle),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
