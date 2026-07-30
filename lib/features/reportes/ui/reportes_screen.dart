import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nav/retroceso.dart';
import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_tallado.dart';
import '../../../core/theme/bento_velo.dart';
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

  /// Detalle del RANGO completo, abierto al tocar el total. Es otro nivel que
  /// el de turno: uno recorta por franja horaria y este no recorta nada.
  bool _detalleDelRango = false;

  bool get enDetalle => _turnoSeleccionado != null || _detalleDelRango;

  void volver() => setState(() {
    _turnoSeleccionado = null;
    _detalleDelRango = false;
  });

  String _tituloDelRango() => switch (_rango) {
    RangoReporte.dia => 'Ventas del día',
    RangoReporte.semana => 'Ventas de la semana',
    RangoReporte.mes => 'Ventas del mes',
    RangoReporte.anio => 'Ventas del año',
  };

  @override
  Widget build(BuildContext context) {
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;
    final params = ReportesParametros(rango: _rango, fechaReferencia: _fecha);
    final reporteAsync = ref.watch(reportesProvider(params));

    return RetrocesoCierra(
      activo: enDetalle,
      alRetroceder: volver,
      child: Scaffold(
        body: Padding(
          // El hero no scrollea: acá el espacio superior se reserva de verdad,
          // no se atraviesa.
          padding: EdgeInsets.fromLTRB(
            BentoSpacing.gapCelda,
            bentoInsetSuperior(context),
            BentoSpacing.gapCelda,
            BentoSpacing.gapCelda,
          ),
          child: _detalleDelRango
              ? _DetalleDelRango(params: params, titulo: _tituloDelRango(), onVolver: volver)
              : reporteAsync.when(
                  data: (reporte) => _turnoSeleccionado != null
                      ? _VistaDrillDown(
                          titulo: _nombreTurno(_turnoSeleccionado!),
                          ventas: reporte.ventasPorTurno[_turnoSeleccionado]!,
                          total: reporte.porTurno[_turnoSeleccionado]!,
                          vacio: 'Sin ventas en este turno',
                          onVolver: volver,
                        )
                      : _VistaGeneral(
                          rango: _rango,
                          fecha: _fecha,
                          reporte: reporte,
                          esGerente: esGerente,
                          onCambiarRango: (r) => setState(() => _rango = r),
                          onSeleccionarTurno: (t) => setState(() => _turnoSeleccionado = t),
                          onVerDetalle: () => setState(() => _detalleDelRango = true),
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
      ),
    );
  }
}

String _nombreTurno(Turno turno) => switch (turno) {
  Turno.manana => 'Mañana',
  Turno.tarde => 'Tarde',
  Turno.noche => 'Noche',
};

/// Carga el detalle del rango bajo demanda: pedirlo por adelantado haría que
/// abrir Reportes trajera el año entero aunque nadie mire la lista.
class _DetalleDelRango extends ConsumerWidget {
  const _DetalleDelRango({required this.params, required this.titulo, required this.onVolver});

  final ReportesParametros params;
  final String titulo;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(detalleRangoProvider(params))
        .when(
          data: (detalle) => _VistaDrillDown(
            titulo: titulo,
            ventas: detalle.ventas,
            total: detalle.ventas.fold<double>(0, (s, v) => s + v.total),
            onVolver: onVolver,
            nota: detalle.truncado
                ? 'Mostrando las ${detalle.ventas.length} más recientes '
                      'de ${detalle.totalVentas}.'
                : null,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
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
    required this.onVerDetalle,
    required this.onElegirFecha,
  });

  final RangoReporte rango;
  final DateTime fecha;
  final ReporteResultado reporte;
  final bool esGerente;
  final ValueChanged<RangoReporte> onCambiarRango;
  final ValueChanged<Turno> onSeleccionarTurno;

  /// Abre la lista de ventas del rango completo. Antes solo se podía entrar al
  /// detalle por turno, y solo con el rango de día: no había forma de ver qué
  /// ventas componían el total de una semana, un mes o un año.
  final VoidCallback onVerDetalle;

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

    // Hero y turnos en la retícula de 6 columnas (decisión 0026). Cada uno
    // sigue siendo su propia celda —el usuario confirmó que así se ven mejor
    // que fusionadas con líneas divisorias internas— y las de una misma fila
    // comparten altura, que es lo que `BentoCuadricula` garantiza.
    //
    // Los spans son lo que arregla el desborde: antes eran cuatro celdas en una
    // `Row` fija, así que a 360 dp el hero quedaba en ~146 dp con un número de
    // 40 px y cada turno en ~52 dp. Ahora en teléfono el hero toma la fila
    // entera y los tres turnos la siguiente; en escritorio 3+1+1+1 vuelve a dar
    // exactamente la fila de siempre.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BentoCuadricula(
          hijos: [
            BentoCelda(
              compacto: 6,
              medio: 6,
              amplio: 3,
              hijo: BentoPozo(
                onTap: onVerDetalle,
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
                    // El hero es el numero mas importante de la pantalla
                    // — debe destacar claramente sobre los turnos, no
                    // ser "casi del mismo tamano" (skill
                    // visual-hierarchy: minimo 1.5x de diferencia).
                    // displaySmall (40) vs bodyLarge (16) de los turnos
                    // da 2.5x.
                    BentoTextoTallado(
                      '₡${reporte.total.toStringAsFixed(2)}',
                      sobre: lacaDe(context).pozo,
                      nivel: TalladoNivel.marcado,
                      estilo: Theme.of(context).textTheme.displaySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (rango == RangoReporte.dia)
              for (final (nombre, turno) in const [
                ('Mañana', Turno.manana),
                ('Tarde', Turno.tarde),
                ('Noche', Turno.noche),
              ])
                BentoCelda(
                  compacto: 2,
                  medio: 2,
                  amplio: 1,
                  hijo: _TarjetaTurno(
                    nombre: nombre,
                    monto: reporte.porTurno[turno]!,
                    onTap: () => onSeleccionarTurno(turno),
                  ),
                ),
          ],
        ),
        const SizedBox(height: BentoSpacing.pared),
        // Los rankings quedan lado a lado desde tablet y apilados en teléfono,
        // donde dos listas de ~156 dp con nombre y cantidad no se leen.
        Expanded(
          child: BentoCuadricula(
            llenarAlto: true,
            hijos: [
              BentoCelda(
                compacto: 6,
                medio: 3,
                amplio: 3,
                hijo: _Ranking(titulo: 'Más vendidos', items: reporte.masVendidos),
              ),
              BentoCelda(
                compacto: 6,
                medio: 3,
                amplio: 3,
                hijo: _Ranking(titulo: 'Menos vendidos', items: reporte.menosVendidos),
              ),
            ],
          ),
        ),
        const SizedBox(height: BentoSpacing.unidad),
        // `Wrap` porque el Gerente tiene cuatro segmentos y la Registradora
        // dos: el ancho de este control depende del ROL, no solo del aparato.
        Wrap(
          children: [
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
        ),
      ],
    );
  }
}

/// Tarjeta individual de turno — celda bento propia (el usuario confirmo
/// que el look de tarjeta redondeada individual se veia mejor que fusionar
/// los 3 turnos en un bloque con lineas divisorias internas). Va en una Row
/// junto al hero y sus hermanas (`Expanded` + `IntrinsicHeight`/stretch en
/// `_VistaGeneral.build`) para llenar la misma altura que el hero, en vez
/// de quedar con una altura fija que no se acomoda al espacio disponible.
class _TarjetaTurno extends StatelessWidget {
  const _TarjetaTurno({required this.nombre, required this.monto, required this.onTap});

  final String nombre;
  final double monto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BentoPozo(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: BentoSpacing.paddingCelda,
        vertical: BentoSpacing.unidad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(nombre, style: Theme.of(context).textTheme.bodyMedium),
          Text('₡${monto.toStringAsFixed(0)}', style: Theme.of(context).textTheme.titleMedium),
        ],
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
    return BentoPozo(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(BentoSpacing.pared),
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

/// Detalle: la lista de ventas de un turno o de un rango completo.
///
/// El mismo widget para los dos casos — un turno y "todo el mes" son la misma
/// pregunta con distinto recorte, y tener dos pantallas casi iguales las haría
/// divergir a la primera corrección.
class _VistaDrillDown extends StatelessWidget {
  const _VistaDrillDown({
    required this.titulo,
    required this.ventas,
    required this.total,
    required this.onVolver,
    this.vacio = 'Sin ventas en este período',
    this.nota,
  });

  final String titulo;
  final List<VentaConLineas> ventas;
  final double total;
  final VoidCallback onVolver;
  final String vacio;

  /// Aviso cuando la lista no trae todo lo que hay (ver [limiteDetalleRango]).
  final String? nota;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: onVolver,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Volver'),
        ),
        BentoPozo(
          padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
              BentoTextoTallado(
                '\u20a1${total.toStringAsFixed(2)}',
                sobre: lacaDe(context).pozo,
                nivel: TalladoNivel.marcado,
                estilo: Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
        if (nota != null) ...[
          const SizedBox(height: BentoSpacing.unidad),
          Text(nota!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: BentoSpacing.unidad),
        Expanded(
          child: ventas.isEmpty
              ? Center(child: Text(vacio))
              : BentoPozo(
                  padding: EdgeInsets.zero,
                  child: ListView.builder(
                    itemCount: ventas.length,
                    itemBuilder: (context, i) {
                      final vc = ventas[i];
                      final f = vc.venta.fechaHora;
                      final hora = TimeOfDay.fromDateTime(f).format(context);
                      return ListTile(
                        title: Text('${f.day}/${f.month} $hora'),
                        subtitle: Text('${vc.lineas.length} l\u00ednea(s)'),
                        trailing: Text('\u20a1${vc.total.toStringAsFixed(2)}'),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
