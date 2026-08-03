import 'package:flutter/material.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/ui/bento_dialogo.dart';
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
      return showDatePicker(
        context: context,
        initialDate: actual,
        firstDate: DateTime(2020),
        lastDate: hoy,
      );
    case RangoReporte.semana:
      // Cualquier día sirve: `rangoDeFechas` lo lleva al lunes de su semana.
      return showDatePicker(
        context: context,
        initialDate: actual,
        firstDate: DateTime(2020),
        lastDate: hoy,
        helpText: 'Elegí un día de la semana',
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
class _ElegirMes extends StatefulWidget {
  const _ElegirMes({required this.actual, required this.hoy});

  final DateTime actual;
  final DateTime hoy;

  @override
  State<_ElegirMes> createState() => _ElegirMesState();
}

class _ElegirMesState extends State<_ElegirMes> {
  late int _anio = widget.actual.year;

  @override
  Widget build(BuildContext context) {
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

class _ElegirAnio extends StatelessWidget {
  const _ElegirAnio({required this.actual, required this.hoy});

  final DateTime actual;
  final DateTime hoy;

  @override
  Widget build(BuildContext context) {
    final anios = [for (var a = hoy.year; a >= 2020; a--) a];
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
  });

  final String etiqueta;
  final bool habilitada;
  final bool seleccionada;
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
        child: Center(
          child: Text(
            etiqueta,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: seleccionada ? Theme.of(context).colorScheme.primary : laca.textoEnBandeja,
            ),
          ),
        ),
      ),
    );
  }
}
