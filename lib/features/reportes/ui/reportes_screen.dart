import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_theme.dart';
import '../../auth/sesion_notifier.dart';
import '../reportes_provider.dart';

/// Ventana 4 — ver docs/pantallas/flujo-descripcion.md#ventana-4--reportes
/// y docs/pantallas/prototipos-ascii.md. Reporte unificado con drill-down
/// (turno → ventas individuales). Exportar PDF/CSV queda pendiente
/// (research aparte, no bloquea el resto).
class ReportesScreen extends ConsumerStatefulWidget {
  const ReportesScreen({super.key});

  @override
  ConsumerState<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends ConsumerState<ReportesScreen> {
  RangoReporte _rango = RangoReporte.dia;
  DateTime _fecha = DateTime.now();
  Turno? _turnoSeleccionado;

  @override
  Widget build(BuildContext context) {
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;
    final params = ReportesParametros(rango: _rango, fechaReferencia: _fecha);
    final reporteAsync = ref.watch(reportesProvider(params));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(BentoSpacing.gapCelda),
        child: reporteAsync.when(
          data: (reporte) => _turnoSeleccionado != null
              ? _VistaDrillDown(
                  turno: _turnoSeleccionado!,
                  ventas: reporte.ventasPorTurno[_turnoSeleccionado]!,
                  onVolver: () => setState(() => _turnoSeleccionado = null),
                )
              : _VistaGeneral(
                  rango: _rango,
                  fecha: _fecha,
                  reporte: reporte,
                  esGerente: esGerente,
                  onCambiarRango: (r) => setState(() => _rango = r),
                  onSeleccionarTurno: (t) => setState(() => _turnoSeleccionado = t),
                  onElegirFecha: () async {
                    final elegida = await showDatePicker(
                      context: context,
                      initialDate: _fecha,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (elegida != null) setState(() => _fecha = elegida);
                  },
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }
}

class _VistaGeneral extends StatelessWidget {
  const _VistaGeneral({
    required this.rango,
    required this.fecha,
    required this.reporte,
    required this.esGerente,
    required this.onCambiarRango,
    required this.onSeleccionarTurno,
    required this.onElegirFecha,
  });

  final RangoReporte rango;
  final DateTime fecha;
  final ReporteResultado reporte;
  final bool esGerente;
  final ValueChanged<RangoReporte> onCambiarRango;
  final ValueChanged<Turno> onSeleccionarTurno;
  final VoidCallback onElegirFecha;

  String _tituloRango(RangoReporte r, DateTime f, bool esHoy) {
    switch (r) {
      case RangoReporte.dia:
        return esHoy ? 'Hoy' : '${f.day}/${f.month}/${f.year}';
      case RangoReporte.semana:
        return 'Esta semana';
      case RangoReporte.mes:
        return 'Este mes';
      case RangoReporte.anio:
        return 'Este año';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final esHoy = fecha.year == ahora.year && fecha.month == ahora.month && fecha.day == ahora.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          // El hero (total del periodo) es el numero mas importante de la
          // pantalla — debe destacar claramente sobre los tiles de turno,
          // no ser "casi del mismo tamano" (skill visual-hierarchy: al
          // menos 1.5x de diferencia). displaySmall (40) vs el texto de
          // los tiles (bodyLarge, 16) da una diferencia de 2.5x.
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            _tituloRango(rango, fecha, esHoy),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (esGerente && rango == RangoReporte.dia)
                            IconButton(
                              icon: const Icon(Icons.calendar_month_outlined, size: 18),
                              tooltip: 'Elegir día',
                              onPressed: onElegirFecha,
                            ),
                        ],
                      ),
                      Text(
                        '₡${reporte.total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (rango == RangoReporte.dia) ...[
              const SizedBox(width: BentoSpacing.gapCelda),
              _TileTurno(
                nombre: 'Mañana',
                monto: reporte.porTurno[Turno.manana]!,
                onTap: () => onSeleccionarTurno(Turno.manana),
              ),
              const SizedBox(width: BentoSpacing.unidad),
              _TileTurno(
                nombre: 'Tarde',
                monto: reporte.porTurno[Turno.tarde]!,
                onTap: () => onSeleccionarTurno(Turno.tarde),
              ),
              const SizedBox(width: BentoSpacing.unidad),
              _TileTurno(
                nombre: 'Noche',
                monto: reporte.porTurno[Turno.noche]!,
                onTap: () => onSeleccionarTurno(Turno.noche),
              ),
            ],
          ],
        ),
        const SizedBox(height: BentoSpacing.gapCelda),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Ranking(titulo: 'Más vendidos', items: reporte.masVendidos)),
              const SizedBox(width: BentoSpacing.gapCelda),
              Expanded(child: _Ranking(titulo: 'Menos vendidos', items: reporte.menosVendidos)),
            ],
          ),
        ),
        const SizedBox(height: BentoSpacing.unidad),
        SegmentedButton<RangoReporte>(
          segments: [
            const ButtonSegment(value: RangoReporte.dia, label: Text('Día')),
            const ButtonSegment(value: RangoReporte.semana, label: Text('Semana')),
            if (esGerente) ...[
              const ButtonSegment(value: RangoReporte.mes, label: Text('Mes')),
              const ButtonSegment(value: RangoReporte.anio, label: Text('Año')),
            ],
          ],
          selected: {rango},
          onSelectionChanged: (s) => onCambiarRango(s.first),
        ),
      ],
    );
  }
}

class _TileTurno extends StatelessWidget {
  const _TileTurno({required this.nombre, required this.monto, required this.onTap});

  final String nombre;
  final double monto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BentoRadius.celda),
          child: Padding(
            padding: const EdgeInsets.all(BentoSpacing.unidad * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(nombre, style: Theme.of(context).textTheme.bodyMedium),
                Text('₡${monto.toStringAsFixed(0)}', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Deslizante (scroll), sin opción de exportar por ahora — a pedido
/// explícito, se agrega solo si se pide la característica.
class _Ranking extends StatelessWidget {
  const _Ranking({required this.titulo, required this.items});

  final String titulo;
  final List<RankingItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(BentoSpacing.unidad * 1.5),
            child: Text(titulo, style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('Sin datos'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      title: Text(items[i].nombre),
                      trailing: Text('${items[i].cantidad}'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _VistaDrillDown extends StatelessWidget {
  const _VistaDrillDown({
    required this.turno,
    required this.ventas,
    required this.onVolver,
  });

  final Turno turno;
  final List<VentaConLineas> ventas;
  final VoidCallback onVolver;

  String get _nombreTurno {
    switch (turno) {
      case Turno.manana:
        return 'Mañana';
      case Turno.tarde:
        return 'Tarde';
      case Turno.noche:
        return 'Noche';
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = ventas.fold<double>(0, (s, v) => s + v.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: onVolver,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Volver'),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_nombreTurno, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '₡${total.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: BentoSpacing.unidad),
        Expanded(
          child: ventas.isEmpty
              ? const Center(child: Text('Sin ventas en este turno'))
              : ListView.builder(
                  itemCount: ventas.length,
                  itemBuilder: (context, i) {
                    final vc = ventas[i];
                    final hora = TimeOfDay.fromDateTime(vc.venta.fechaHora).format(context);
                    return ListTile(
                      title: Text('$hora — ${vc.lineas.length} línea(s)'),
                      trailing: Text('₡${vc.total.toStringAsFixed(2)}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
