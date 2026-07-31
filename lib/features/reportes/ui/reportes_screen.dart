import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/nav/retroceso.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_tallado.dart';
import '../../../core/theme/bento_velo.dart';
import '../../../core/theme/bento_theme.dart';
import '../../auth/sesion_notifier.dart';
import '../../../core/ui/bento_falla.dart';
import '../../import_export/carpeta_exportacion.dart';
import '../reporte_export_service.dart';
import '../reportes_provider.dart';
import 'elegir_periodo.dart';

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

  /// Exporta lo que se está mirando: el mismo período, el mismo total.
  ///
  /// Las ventas se piden aparte porque el reporte de pantalla trae solo los
  /// agregados — el detalle se carga bajo demanda para no traer el año entero
  /// cada vez que se abre Reportes.
  Future<void> _exportarPeriodo(ReporteResultado reporte) async {
    final params = ReportesParametros(rango: _rango, fechaReferencia: _fecha);
    await _exportar(
      titulo: '${_tituloDelRango()} · ${_tituloPeriodo()}',
      sufijoArchivo: _rango.name,
      total: reporte.total,
      porTurno: reporte.porTurno,
      // Las ventas se piden aparte porque el reporte de pantalla trae solo los
      // agregados: el detalle se carga bajo demanda para no arrastrar el año
      // entero cada vez que se abre Reportes.
      cargarVentas: () async {
        final detalle = await ref.read(detalleRangoProvider(params).future);
        return (
          detalle.ventas,
          detalle.truncado
              ? 'Incluye las ${detalle.ventas.length} ventas más recientes de '
                    '${detalle.totalVentas}.'
              : null,
        );
      },
    );
  }

  /// Un turno suelto. Sus ventas ya están en el reporte de pantalla —vienen
  /// con el cálculo por turno—, así que acá no hay nada que volver a consultar.
  Future<void> _exportarTurno(ReporteResultado reporte, Turno turno) async {
    await _exportar(
      titulo: '${_nombreTurno(turno)} · ${_tituloPeriodo()}',
      sufijoArchivo: '${_rango.name}-${turno.name}',
      total: reporte.porTurno[turno]!,
      cargarVentas: () async => (reporte.ventasPorTurno[turno]!, null),
    );
  }

  Future<void> _exportar({
    required String titulo,
    required String sufijoArchivo,
    required double total,
    required Future<(List<VentaConLineas>, String?)> Function() cargarVentas,
    Map<Turno, double>? porTurno,
  }) async {
    final formato = await showDialog<FormatoReporte>(
      context: context,
      builder: (_) => const _ElegirFormato(),
    );
    if (formato == null || !mounted) return;

    final (ventas, nota) = await cargarVentas();
    if (!mounted) return;

    final (desde, _) = rangoDeFechas(_rango, _fecha);
    try {
      final bytes = await const ReporteExportService().generar(
        formato: formato,
        titulo: titulo,
        total: total,
        porTurno: porTurno,
        ventas: ventas,
        nota: nota,
      );
      // A la carpeta de exportación, sin selector: se elige una vez desde
      // Configuración y de ahí en adelante exportar es un toque.
      final destino = await const CarpetaExportacion().archivoPara(
        'reporte-$sufijoArchivo-${desde.toIso8601String().split('T').first}'
        '.${formato.extension}',
      );
      await destino.writeAsBytes(bytes);
      // Con el nombre en el aviso: sin selector, si no se dice dónde quedó,
      // nadie lo encuentra.
      if (mounted) mostrarAviso(context, '✓ ${p.basename(destino.path)}');
    } catch (_) {
      if (mounted) mostrarAviso(context, '✗ No se pudo guardar el reporte');
    }
  }

  String _tituloPeriodo() {
    final (desde, hasta) = rangoDeFechas(_rango, _fecha);
    final fin = hasta.subtract(const Duration(days: 1));
    String d(DateTime x) => '${x.day}/${x.month}/${x.year}';
    return desde == fin ? d(desde) : '${d(desde)} a ${d(fin)}';
  }

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
                          onExportar: () => _exportarPeriodo(reporte),
                          onExportarTurno: (t) => _exportarTurno(reporte, t),
                          onElegirFecha: () async {
                            final elegida = await elegirPeriodo(
                              context,
                              rango: _rango,
                              actual: _fecha,
                            );
                            if (elegida != null) setState(() => _fecha = elegida);
                          },
                        ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => BentoFalla(
                    mensaje: 'No se pudieron cargar las ventas del período.',
                    error: e,
                    onReintentar: () => ref.invalidate(reportesProvider(params)),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Por debajo de este alto la pantalla se considera acostada: apilar bloques
/// ya no entra, y hay ancho de sobra para repartirlos a lo largo.
const double _altoAcostado = 520;

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
          error: (e, st) => BentoFalla(
            mensaje: 'No se pudo cargar el detalle de las ventas.',
            error: e,
            onReintentar: () => ref.invalidate(detalleRangoProvider(params)),
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
    required this.onVerDetalle,
    required this.onExportar,
    required this.onExportarTurno,
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

  /// Mantener presionado el total exporta el período que se está mirando.
  final VoidCallback onExportar;

  /// Y mantener presionado un turno exporta solo ese turno.
  final ValueChanged<Turno> onExportarTurno;

  final VoidCallback onElegirFecha;

  /// Dice QUÉ período se está mirando, no solo de qué tipo es.
  ///
  /// Con "Este mes" fijo, mirar marzo y mirar abril se veían idénticos salvo
  /// por los números: nada en pantalla decía cuál de los dos era.
  String _tituloRango(RangoReporte r, DateTime f, bool esHoy) {
    final ahora = DateTime.now();
    switch (r) {
      case RangoReporte.dia:
        return esHoy ? 'Hoy' : '${f.day}/${f.month}/${f.year}';
      case RangoReporte.semana:
        final (inicio, _) = rangoDeFechas(r, f);
        final (inicioActual, _) = rangoDeFechas(r, ahora);
        return inicio == inicioActual ? 'Esta semana' : 'Semana del ${inicio.day}/${inicio.month}';
      case RangoReporte.mes:
        return f.year == ahora.year && f.month == ahora.month
            ? 'Este mes'
            : '${_nombreMes(f.month)} ${f.year}';
      case RangoReporte.anio:
        return f.year == ahora.year ? 'Este año' : '${f.year}';
    }
  }

  static String _nombreMes(int mes) => const [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Setiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ][mes - 1];

  /// Lo mínimo para que un ranking siga siendo legible: su título más un par
  /// de filas.
  static const double _altoMinimoRanking = 160;

  /// Lo que ocupan hero, turnos, las separaciones y el selector de rango.
  static const double _altoResto = 220;

  /// Alto del bloque de rankings: en teléfono se apilan, así que hacen falta
  /// dos mínimos y la pared entre ellos, no uno.
  static double _altoMinimoRankings(BuildContext context) => BentoAncho.de(context).esCompacto
      ? _altoMinimoRanking * 2 + BentoSpacing.pared
      : _altoMinimoRanking;

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
    // La pantalla se desplaza cuando no entra, y llena el alto cuando sí.
    //
    // `SizedBox` con el alto REAL de la caja: dentro de un scroll el alto es
    // infinito y `Flexible`/`Expanded` no reparten infinitos. Y el mínimo evita
    // que, acostado, los rankings se aplasten por debajo de lo legible — ahí
    // simplemente se desplaza.
    return LayoutBuilder(
      builder: (context, restricciones) {
        final acostado =
            restricciones.maxHeight < _altoAcostado && !BentoAncho.de(context).esCompacto;
        return SingleChildScrollView(
          child: SizedBox(
            height: acostado
                ? restricciones.maxHeight
                : math.max(restricciones.maxHeight, _altoResto + _altoMinimoRankings(context)),
            child: acostado ? _cuerpoAcostado(context, esHoy) : _cuerpo(context, esHoy),
          ),
        );
      },
    );
  }

  Widget _cuerpo(BuildContext context, bool esHoy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _resumen(context, esHoy),
        const SizedBox(height: BentoSpacing.pared),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: _altoMinimoRankings(context)),
            child: _rankings(),
          ),
        ),
        const SizedBox(height: BentoSpacing.unidad),
        _selector(),
      ],
    );
  }

  /// Acostado el alto es el recurso escaso y el ancho sobra: el resumen se va a
  /// una columna y los rankings a la otra, en vez de apilarse y obligar a
  /// desplazar para ver el selector de rango.
  Widget _cuerpoAcostado(BuildContext context, bool esHoy) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // El hero se queda con lo que sobre; turnos y selector piden su
              // alto natural. Con la cuadrícula normal aquí dentro el alto
              // intrínseco de hero+turnos excedía la columna y desbordaba 32.
              Expanded(child: _hero(context, esHoy)),
              if (rango == RangoReporte.dia) ...[
                const SizedBox(height: BentoSpacing.pared),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, celda) in _turnos().indexed) ...[
                        if (i > 0) const SizedBox(width: BentoSpacing.pared),
                        Expanded(child: celda),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: BentoSpacing.unidad),
              _selector(),
            ],
          ),
        ),
        const SizedBox(width: BentoSpacing.pared),
        Expanded(flex: 4, child: _rankings()),
      ],
    );
  }

  Widget _resumen(BuildContext context, bool esHoy) {
    return BentoCuadricula(
      hijos: [
        BentoCelda(compacto: 6, medio: 6, amplio: 3, hijo: _hero(context, esHoy)),
        if (rango == RangoReporte.dia)
          for (final celda in _turnos()) BentoCelda(compacto: 2, medio: 2, amplio: 1, hijo: celda),
      ],
    );
  }

  List<Widget> _turnos() => [
    for (final (nombre, turno) in const [
      ('Mañana', Turno.manana),
      ('Tarde', Turno.tarde),
      ('Noche', Turno.noche),
    ])
      _TarjetaTurno(
        nombre: nombre,
        monto: reporte.porTurno[turno]!,
        onTap: () => onSeleccionarTurno(turno),
        onExportar: () => onExportarTurno(turno),
      ),
  ];

  Widget _hero(BuildContext context, bool esHoy) {
    return BentoPozo(
      onTap: onVerDetalle,
      // Mantener presionado exporta. Va acá y no en un botón siempre visible
      // porque exportar es de fin de mes, no de cada rato: un botón fijo
      // competiría por atención con el número, que es lo que se viene a ver.
      onLongPress: onExportar,
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
              // El calendario vale para los CUATRO rangos: antes solo el día se
              // podía cambiar, así que semana, mes y año eran siempre los
              // actuales y no había forma de mirar el mes pasado — que es justo
              // lo que se hace al cerrar cuentas.
              if (esGerente)
                IconButton(
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  tooltip: switch (rango) {
                    RangoReporte.dia => 'Elegir día',
                    RangoReporte.semana => 'Elegir semana',
                    RangoReporte.mes => 'Elegir mes',
                    RangoReporte.anio => 'Elegir año',
                  },
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
    );
  }

  /// Lado a lado desde tablet y apilados en teléfono, donde dos listas de
  /// ~156 dp con nombre y cantidad no se leen.
  Widget _rankings() {
    return BentoCuadricula(
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
    );
  }

  ButtonSegment<RangoReporte> _segmento(RangoReporte valor, String etiqueta) {
    return ButtonSegment(
      value: valor,
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(etiqueta, maxLines: 1)),
    );
  }

  Widget _selector() {
    // `Wrap` porque el Gerente tiene cuatro segmentos y la Registradora
    // dos: el ancho de este control depende del ROL, no solo del aparato.
    return Wrap(
      children: [
        SegmentedButton<RangoReporte>(
          segments: [
            // Etiquetas que se encogen en vez de partirse: escalar el texto no
            // toca el alto del control, así que el objetivo táctil de 48 dp
            // sigue intacto (regla 7).
            _segmento(RangoReporte.dia, 'Día'),
            _segmento(RangoReporte.semana, 'Semana'),
            if (esGerente) ...[
              _segmento(RangoReporte.mes, 'Mes'),
              _segmento(RangoReporte.anio, 'Año'),
            ],
          ],
          selected: {rango},
          // Sin la marca de verificación: roba ~40 dp y en la columna angosta
          // del modo acostado partía "Día" en tres líneas. El segmento elegido
          // ya se distingue por el relleno.
          showSelectedIcon: false,
          // Padding horizontal reducido, no fuente más chica: con el de fábrica
          // "Semana" se parte en dos renglones en la columna angosta del modo
          // acostado. El alto —y con él el objetivo táctil de 48 dp— no cambia.
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: BentoSpacing.unidad)),
          ),
          onSelectionChanged: (s) => onCambiarRango(s.first),
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
  const _TarjetaTurno({
    required this.nombre,
    required this.monto,
    required this.onTap,
    required this.onExportar,
  });

  final String nombre;
  final double monto;
  final VoidCallback onTap;
  final VoidCallback onExportar;

  @override
  Widget build(BuildContext context) {
    return BentoPozo(
      onTap: onTap,
      // El mismo gesto que en el total: mantener presionado exporta lo que se
      // está tocando. Si vale para el período, vale para cada turno.
      onLongPress: onExportar,
      padding: const EdgeInsets.symmetric(
        horizontal: BentoSpacing.paddingCelda,
        vertical: BentoSpacing.unidad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Una línea cada uno: en la columna angosta del modo acostado
          // "Mañana" se partía en "Maña/na" y el monto en dos renglones.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(nombre, style: Theme.of(context).textTheme.bodyMedium, maxLines: 1),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₡${monto.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
            ),
          ),
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
    final acostado = MediaQuery.sizeOf(context).height < _altoAcostado;
    return Column(
      // `stretch` y no `start`: con `start` cada hijo tomaba su ancho NATURAL,
      // así que la celda del título se encogía hasta el largo del número —
      // ₡1.500 daba una celda angosta y ₡142.468 una ancha. Una celda de bandeja
      // se dimensiona por la pantalla, no por lo que le tocó contener.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onVolver,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Volver'),
          ),
        ),
        // Acostado el encabezado se aprieta: con el padding y el número
        // grandes se llevaba un tercio del alto y la lista de ventas —que es a
        // lo que se vino— quedaba en una franja.
        BentoPozo(
          padding: EdgeInsets.all(
            acostado ? BentoSpacing.paddingCelda : BentoSpacing.paddingCeldaGrande,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
              BentoTextoTallado(
                '\u20a1${total.toStringAsFixed(2)}',
                sobre: lacaDe(context).pozo,
                nivel: TalladoNivel.marcado,
                estilo: acostado
                    ? Theme.of(context).textTheme.headlineSmall
                    : Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
        if (nota != null) ...[
          const SizedBox(height: BentoSpacing.unidad),
          Text(nota!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: BentoSpacing.unidad),
        // `Flexible` con mínimo, igual que en la vista general: acostado, entre
        // el botón de volver y la celda del total no queda alto para la lista, y
        // un `Expanded` a secas la dejaba en cero.
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _altoMinimoLista),
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
        ),
      ],
    );
  }

  /// Lo mínimo para que la lista de ventas siga sirviendo.
  static const double _altoMinimoLista = 140;
}

/// Elegir en qué se exporta. Dos opciones y cada una dice para qué sirve: la
/// diferencia entre PDF y CSV no es obvia para quien atiende una soda.
class _ElegirFormato extends StatelessWidget {
  const _ElegirFormato();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exportar reporte'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final formato in FormatoReporte.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(formato.etiqueta),
              subtitle: Text(formato.explicacion),
              onTap: () => Navigator.pop(context, formato),
            ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
