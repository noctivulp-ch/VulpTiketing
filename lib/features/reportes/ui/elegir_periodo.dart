import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../periodos_con_datos_provider.dart';
import 'calendario_periodo.dart';
import '../../../core/theme/bento_theme.dart';
import '../reportes_provider.dart';

/// Elegir QUÉ período se está mirando, con la forma que pide cada rango.
///
/// Antes solo el día tenía selector, así que semana, mes y año eran siempre
/// los actuales: no había forma de mirar el mes pasado, que es exactamente lo
/// que se hace al cerrar cuentas.
///
/// Un `showDatePicker` para los cuatro habría sido más corto de escribir y peor
/// de usar: para elegir "2025" nadie quiere navegar un calendario de días. La
/// forma sigue a la pregunta — un calendario para día y semana, una cuadrícula
/// de meses para mes, una lista de años para año.
Future<DateTime?> elegirPeriodo(
  BuildContext context, {
  required RangoReporte rango,
  required DateTime actual,
}) {
  final hoy = DateTime.now();
  switch (rango) {
    case RangoReporte.dia:
    case RangoReporte.semana:
      // Calendario propio y no `showDatePicker`: el de Material no sabe marcar
      // los días que tienen ventas ni resaltar una semana entera, que son
      // justamente las dos cosas que faltaban.
      return showDialog<DateTime>(
        context: context,
        builder: (_) => BentoDialogo(
          titulo: Text(rango == RangoReporte.semana ? 'Elegí la semana' : 'Elegí el día'),
          contenido: CalendarioPeriodo(
            actual: actual,
            hoy: hoy,
            porSemana: rango == RangoReporte.semana,
          ),
          acciones: BentoAcciones(
            derecha: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ],
          ),
        ),
      );
    case RangoReporte.mes:
      return showDialog<DateTime>(
        context: context,
        builder: (_) => _ElegirMes(actual: actual, hoy: hoy),
      );
    case RangoReporte.anio:
      return showDialog<DateTime>(
        context: context,
        builder: (_) => _ElegirAnio(actual: actual, hoy: hoy),
      );
  }
}

const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

/// Año primero, mes después: doce celdas en una cuadrícula de 3×4.
class _ElegirMes extends ConsumerStatefulWidget {
  const _ElegirMes({required this.actual, required this.hoy});

  final DateTime actual;
  final DateTime hoy;

  @override
  ConsumerState<_ElegirMes> createState() => _ElegirMesState();
}

class _ElegirMesState extends ConsumerState<_ElegirMes> {
  late int _anio = widget.actual.year;

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(periodosConDatosProvider(_anio)).valueOrNull;
    return BentoDialogo(
      titulo: const Text('Elegí el mes'),
      contenido: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BarraDeAnio(
              anio: _anio,
              minimo: 2020,
              maximo: widget.hoy.year,
              onCambio: (a) => setState(() => _anio = a),
            ),
            const SizedBox(height: BentoSpacing.unidad),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: BentoSpacing.unidad,
              crossAxisSpacing: BentoSpacing.unidad,
              childAspectRatio: 2,
              children: [
                for (var mes = 1; mes <= 12; mes++)
                  _CeldaPeriodo(
                    etiqueta: _meses[mes - 1],
                    // Un mes que todavía no empezó no tiene ventas que mirar.
                    habilitada:
                        _anio < widget.hoy.year ||
                        (_anio == widget.hoy.year && mes <= widget.hoy.month),
                    seleccionada: _anio == widget.actual.year && mes == widget.actual.month,
                    conVentas: datos?.tieneMes(_anio, mes) ?? false,
                    onTap: () => Navigator.pop(context, DateTime(_anio, mes)),
                  ),
              ],
            ),
          ],
        ),
      ),
      acciones: BentoAcciones(
        derecha: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      ),
    );
  }
}

class _ElegirAnio extends ConsumerWidget {
  const _ElegirAnio({required this.actual, required this.hoy});

  final DateTime actual;
  final DateTime hoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anios = [for (var a = hoy.year; a >= 2020; a--) a];
    final conVentas = ref.watch(aniosConVentasProvider).valueOrNull ?? const <int>{};
    return BentoDialogo(
      titulo: const Text('Elegí el año'),
      contenido: SizedBox(
        width: 280,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          mainAxisSpacing: BentoSpacing.unidad,
          crossAxisSpacing: BentoSpacing.unidad,
          childAspectRatio: 2,
          children: [
            for (final a in anios)
              _CeldaPeriodo(
                etiqueta: '$a',
                habilitada: true,
                seleccionada: a == actual.year,
                conVentas: conVentas.contains(a),
                onTap: () => Navigator.pop(context, DateTime(a)),
              ),
          ],
        ),
      ),
      acciones: BentoAcciones(
        derecha: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      ),
    );
  }
}

class _BarraDeAnio extends StatelessWidget {
  const _BarraDeAnio({
    required this.anio,
    required this.minimo,
    required this.maximo,
    required this.onCambio,
  });

  final int anio;
  final int minimo;
  final int maximo;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Año anterior',
          onPressed: anio > minimo ? () => onCambio(anio - 1) : null,
        ),
        Text('$anio', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Año siguiente',
          onPressed: anio < maximo ? () => onCambio(anio + 1) : null,
        ),
      ],
    );
  }
}

/// Celda de mes o año: un pozo, como todo lo elegible de la app.
class _CeldaPeriodo extends StatelessWidget {
  const _CeldaPeriodo({
    required this.etiqueta,
    required this.habilitada,
    required this.seleccionada,
    required this.onTap,
    this.conVentas = false,
  });

  final String etiqueta;
  final bool habilitada;
  final bool seleccionada;

  /// Marca de "acá hay ventas". Un punto y no un color de fondo: el fondo ya lo
  /// usa la selección, y dos significados en el mismo canal no se distinguen.
  final bool conVentas;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    return Opacity(
      opacity: habilitada ? 1 : 0.4,
      child: BentoPozo(
        onTap: habilitada ? onTap : null,
        seleccionado: seleccionada,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              etiqueta,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: seleccionada ? Theme.of(context).colorScheme.primary : laca.textoEnBandeja,
              ),
            ),
            const SizedBox(height: 2),
            // El hueco se reserva siempre: sin él, las celdas con ventas
            // empujan su etiqueta y la cuadrícula queda temblando.
            SizedBox(
              height: 4,
              width: 4,
              child: conVentas
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
