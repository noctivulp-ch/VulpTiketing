import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_providers.dart';
import '../../../core/nav/gesto_dos_dedos.dart';
import '../../../core/nav/retroceso.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_tallado.dart';
import '../../../core/theme/bento_velo.dart';
import '../../../core/theme/bento_theme.dart';
import '../../auth/sesion_notifier.dart';
import '../../../core/ui/bento_falla.dart';
import '../../import_export/almacen_publico.dart';
import '../../import_export/carpeta_exportacion.dart';
import '../reporte_export_service.dart';
import '../../venta/venta_model.dart';
import '../../venta/venta_notifier.dart';
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

  /// Qué tanda del detalle se está mirando. Se pasa con dos dedos.
  int _paginaDetalle = 0;

  bool get enDetalle => _turnoSeleccionado != null || _detalleDelRango;

  void volver() => setState(() {
    _turnoSeleccionado = null;
    _detalleDelRango = false;
    // Se vuelve a la primera tanda: reabrir el detalle y aparecer en la página
    // 7 de la vez pasada no lo espera nadie.
    _paginaDetalle = 0;
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
      // TODAS las ventas del período, sin el tope de la pantalla. Ese tope
      // existe porque nadie desplaza 5.000 filas en un teléfono; un informe es
      // otra cosa, y uno que dijera "incluye las 300 más recientes de 2.847" no
      // se le manda a nadie.
      lotes: () async => ventasDelRangoPorLotes(await ref.read(databaseProvider.future), params),
    );
  }

  /// Un turno suelto. Sus ventas ya están en el reporte de pantalla —vienen
  /// con el cálculo por turno—, así que acá no hay nada que volver a consultar.
  Future<void> _exportarTurno(ReporteResultado reporte, Turno turno) async {
    await _exportar(
      titulo: '${_nombreTurno(turno)} · ${_tituloPeriodo()}',
      sufijoArchivo: '${_rango.name}-${turno.name}',
      total: reporte.porTurno[turno]!,
      // Un turno suelto ya viene entero en el reporte de pantalla: no hay tope
      // que quitar ni consulta que repetir.
      lotes: () async => Stream.value(reporte.ventasPorTurno[turno]!),
    );
  }

  Future<void> _exportar({
    required String titulo,
    required String sufijoArchivo,
    required double total,
    required Future<Stream<List<VentaConLineas>>> Function() lotes,
    Map<Turno, double>? porTurno,
  }) async {
    final formato = await showDialog<FormatoReporte>(
      context: context,
      builder: (_) => const _ElegirFormato(),
    );
    if (formato == null || !mounted) return;

    final (desde, _) = rangoDeFechas(_rango, _fecha);
    final servicio = const ReporteExportService();
    try {
      // A la carpeta de exportación, sin selector: se elige una vez desde
      // Configuración y de ahí en adelante exportar es un toque.
      final destino = await const CarpetaExportacion().archivoPara(
        'reporte-$sufijoArchivo-${desde.toIso8601String().split('T').first}'
        '.${formato.extension}',
      );

      switch (formato) {
        case FormatoReporte.csv:
          // Lote a lote y directo al archivo: el consumo se mantiene plano sea
          // cual sea el período, así que exportar un año no depende de que
          // quepa en memoria.
          await servicio.escribirCsvPorLotes(
            destino: destino,
            titulo: titulo,
            total: total,
            porTurno: porTurno,
            lotes: await lotes(),
          );
        case FormatoReporte.pdf:
          // El PDF sí necesita el documento entero antes de escribirlo — es
          // como funciona el generador. Se junta acá, en un solo sitio.
          final ventas = <VentaConLineas>[];
          await for (final lote in await lotes()) {
            ventas.addAll(lote);
          }
          await destino.writeAsBytes(
            await servicio.generar(
              formato: formato,
              titulo: titulo,
              total: total,
              porTurno: porTurno,
              ventas: ventas,
            ),
          );
      }

      final donde = await const AlmacenPublico().publicar(destino);
      // Con el nombre en el aviso: sin selector, si no se dice dónde quedó,
      // nadie lo encuentra. Y si no llegó a Descargas se dice —el archivo
      // existe igual, pero en un sitio donde no se va a buscar.
      if (mounted) {
        mostrarAviso(
          context,
          AlmacenPublico.ultimoFallo == null ? '✓ $donde' : '⚠ Guardado, pero no en Descargas',
        );
      }
    } catch (e) {
      // Con el motivo, no solo "no se pudo": exportar el año en PDF falló por
      // el tope de páginas del generador y el aviso a secas no daba por dónde
      // empezar a mirar.
      if (mounted) mostrarAviso(context, '✗ No se pudo exportar: ${_motivo(e)}');
    }
  }

  /// Lo que se le puede decir al usuario de un fallo de exportación, en una
  /// línea. El texto crudo de una excepción no le sirve a nadie.
  String _motivo(Object error) {
    final texto = error.toString();
    if (texto.contains('TooBigPage')) return 'el reporte no cabe en el PDF';
    if (texto.contains('No space left')) return 'no queda espacio en el teléfono';
    if (texto.contains('Permission denied')) return 'sin permiso para escribir';
    return 'error inesperado';
  }

  /// Los rangos que este rol puede mirar, en el orden del selector.
  ///
  /// La Registradora tiene dos y el Gerente cuatro (Mes y Año son suyos), así
  /// que el gesto recorre lo que hay: llevarla a un rango que su selector no
  /// muestra la dejaría en una pantalla de la que no sabría salir.
  List<RangoReporte> _rangosDe(bool esGerente) =>
      esGerente ? RangoReporte.values : const [RangoReporte.dia, RangoReporte.semana];

  /// Pide el identificador de la transferencia de una venta SINPE.
  ///
  /// Se anota **después** de cobrar, con calma: al cobrar hay cola y nadie
  /// transcribe doce dígitos con el cliente delante. Por eso el campo llega
  /// vacío o con lo que ya hubiera, y guardarlo en blanco lo borra.
  Future<void> _anotarReferencia(Venta venta) async {
    final controlador = TextEditingController(text: venta.referenciaPago ?? '');
    final anotada = await showDialog<String>(
      context: context,
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('Referencia del SINPE'),
        contenido: TextField(
          controller: controlador,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(labelText: 'Identificador de la transferencia'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        acciones: BentoAcciones(
          izquierda: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controlador.text),
              child: const Text('Guardar'),
            ),
          ],
          derecha: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
    if (anotada == null || !mounted) return;

    await ref.read(ventaNotifierProvider.notifier).anotarReferenciaDePago(venta.id, anotada);
    if (!mounted) return;
    // Se invalida el detalle, no todo el reporte: los totales no cambiaron.
    ref.invalidate(detalleRangoProvider);
    mostrarAviso(context, anotada.trim().isEmpty ? '✓ Referencia borrada' : '✓ Referencia anotada');
  }

  /// Un paso en las tandas del detalle.
  ///
  /// Se apoya en lo que el provider ya trajo —cuántas hay en total— en vez de
  /// consultar de nuevo para saber si queda algo: pasarse de la última página
  /// mostraría una lista vacía sin decir por qué.
  void _moverPagina(int paso) {
    final detalle = ref
        .read(
          detalleRangoProvider(
            PaginaDetalle(
              ReportesParametros(rango: _rango, fechaReferencia: _fecha),
              pagina: _paginaDetalle,
            ),
          ),
        )
        .valueOrNull;
    if (detalle == null) return;

    final destino = _paginaDetalle + paso;
    if (destino < 0 || destino >= detalle.paginas) return;
    setState(() => _paginaDetalle = destino);
  }

  /// Un paso en la lista de rangos. En los extremos no da la vuelta, igual que
  /// la navegación entre ventanas.
  void _moverRango(int paso, bool esGerente) {
    final rangos = _rangosDe(esGerente);
    final destino = rangos.indexOf(_rango) + paso;
    if (destino < 0 || destino >= rangos.length) return;
    setState(() {
      _rango = rangos[destino];
      _paginaDetalle = 0;
    });
  }

  /// Exporta lo que se está mirando: el turno abierto, si hay uno, y si no el
  /// período completo.
  ///
  /// El gesto necesita el reporte ya calculado, y quien lo dispara es la
  /// pantalla entera —no la celda—, así que se lee del provider en vez de
  /// pasarlo por parámetro.
  Future<void> _exportarLoQueSeVe() async {
    final params = ReportesParametros(rango: _rango, fechaReferencia: _fecha);
    final reporte = ref.read(reportesProvider(params)).valueOrNull;
    // Todavía cargando: exportar un total que no está sería exportar un cero.
    if (reporte == null) return;

    if (_turnoSeleccionado != null) {
      await _exportarTurno(reporte, _turnoSeleccionado!);
    } else {
      await _exportarPeriodo(reporte);
    }
  }

  Future<void> _elegirFecha() async {
    final elegida = await elegirPeriodo(context, rango: _rango, actual: _fecha);
    if (elegida != null && mounted) {
      setState(() {
        _fecha = elegida;
        _paginaDetalle = 0;
      });
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

    // Los mismos atajos que en el teléfono son gestos. Sin `Ctrl` las flechas y
    // las teclas de página, porque Reportes no tiene un solo campo de texto con
    // el que puedan chocar; `Ctrl+E` sí lo lleva, que una E suelta es una letra.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _detalleDelRango ? _moverPagina(1) : _moverRango(1, esGerente),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _detalleDelRango ? _moverPagina(-1) : _moverRango(-1, esGerente),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _moverPagina(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _moverPagina(-1),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): _exportarLoQueSeVe,
        // El período: `F` de fecha. Solo el Gerente lo elige, igual que el gesto
        // y que el botón del calendario.
        if (esGerente && !enDetalle)
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): _elegirFecha,
        // Salir del detalle sin buscar el botón.
        if (enDetalle) const SingleActivator(LogicalKeyboardKey.escape): volver,
      },
      child: GestoDeDosDedos(
        // Dos dedos de lado recorren los rangos, en el mismo orden en que están
        // en el selector: Día → Semana → Mes → Año. Con un dedo el horizontal ya
        // es cambiar de ventana, así que esto no le pisa nada (decisión 0030).
        // Dentro del detalle el mismo gesto pasa de PÁGINA, no de rango: ahí lo
        // que se recorre son las ventas, y cambiar el rango por debajo de una
        // lista que se está leyendo sería desconcertante.
        alDeslizarIzquierda: _detalleDelRango
            ? () => _moverPagina(1)
            : () => _moverRango(1, esGerente),
        alDeslizarDerecha: _detalleDelRango
            ? () => _moverPagina(-1)
            : () => _moverRango(-1, esGerente),
        // Abajo despliega el selector del rango actual —calendario, meses o
        // años—, que es el mismo sentido de "abrir" que en Ventana 2.
        alDeslizarAbajo: enDetalle || !esGerente ? null : _elegirFecha,
        // Y arriba, exportar. No cerrar: para salir del detalle ya están el botón
        // de volver y el retroceso del sistema, así que gastar el gesto en eso
        // era desperdiciarlo. Exportar, en cambio, no tenía atajo — vivía
        // escondido en un "mantener presionado" que no se descubre solo.
        alDeslizarArriba: _exportarLoQueSeVe,
        child: RetrocesoCierra(
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
                  ? _DetalleDelRango(
                      peticion: PaginaDetalle(params, pagina: _paginaDetalle),
                      titulo: _tituloDelRango(),
                      onVolver: volver,
                      onAnotarReferencia: _anotarReferencia,
                    )
                  : reporteAsync.when(
                      data: (reporte) => _turnoSeleccionado != null
                          ? _VistaDrillDown(
                              titulo: _nombreTurno(_turnoSeleccionado!),
                              ventas: reporte.ventasPorTurno[_turnoSeleccionado]!,
                              total: reporte.porTurno[_turnoSeleccionado]!,
                              vacio: 'Sin ventas en este turno',
                              onVolver: volver,
                              onAnotarReferencia: _anotarReferencia,
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
                              onElegirFecha: _elegirFecha,
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
  const _DetalleDelRango({
    required this.peticion,
    required this.titulo,
    required this.onVolver,
    required this.onAnotarReferencia,
  });

  final PaginaDetalle peticion;
  final String titulo;
  final VoidCallback onVolver;
  final ValueChanged<Venta> onAnotarReferencia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(detalleRangoProvider(peticion))
        .when(
          data: (detalle) => _VistaDrillDown(
            titulo: titulo,
            ventas: detalle.ventas,
            total: detalle.ventas.fold<double>(0, (s, v) => s + v.total),
            onVolver: onVolver,
            onAnotarReferencia: onAnotarReferencia,
            // Dónde está parado, no una disculpa. Antes decía "mostrando las
            // 300 más recientes de 2.847" y ahí se acababa el asunto: no había
            // forma de ver las otras 2.547.
            nota: detalle.truncado
                ? '${detalle.desplazamiento + 1}–'
                      '${detalle.desplazamiento + detalle.ventas.length} '
                      'de ${detalle.totalVentas} · página ${detalle.pagina + 1} '
                      'de ${detalle.paginas} · dos dedos para pasar'
                : null,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => BentoFalla(
            mensaje: 'No se pudo cargar el detalle de las ventas.',
            error: e,
            onReintentar: () => ref.invalidate(detalleRangoProvider(peticion)),
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
          // Esta columna SE DESPLAZA si no entra, en vez de repartir por flex.
          // Con `Expanded` en el hero, un día de Gerente —cuatro segmentos de
          // rango en vez de dos— no dejaba nada que repartir y la columna
          // desbordaba: un `Expanded` que recibe menos que cero no encoge,
          // desborda. Y repartir entre hero y turnos aplastaba los turnos por
          // debajo de su texto, que desbordaba 43.
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _hero(context, esHoy),
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
          // El desglose solo aparece cuando hubo transferencias: en un día en
          // que todo entró en efectivo, "SINPE ₡0" es una línea que no dice
          // nada y le quita sitio al número que sí importa.
          if (reporte.porSinpe > 0)
            Text(
              'Efectivo ₡${reporte.porEfectivo.toStringAsFixed(2)}'
              '  ·  SINPE ₡${reporte.porSinpe.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: lacaDe(context).textoAtenuadoEnBandeja),
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
                    // Sin esto el `ListView` hereda el padding del sistema —la
                    // barra de estado, unos 100 px en este teléfono— y el
                    // primer producto del ranking aparecía a dos tercios de
                    // altura, con un hueco muerto encima y el segundo cortado.
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      title: Text(items[i].nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    required this.onAnotarReferencia,
    this.vacio = 'Sin ventas en este período',
    this.nota,
  });

  final String titulo;
  final List<VentaConLineas> ventas;
  final double total;
  final VoidCallback onVolver;

  /// Qué hacer al tocar una venta de SINPE. La lista no sabe guardar nada: solo
  /// avisa cuál se tocó.
  final ValueChanged<Venta> onAnotarReferencia;

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
                      // Mismo motivo que en el ranking: el padding del sistema
                      // se cuela y deja un hueco al principio de la lista.
                      padding: EdgeInsets.zero,
                      itemCount: ventas.length,
                      itemBuilder: (context, i) {
                        final vc = ventas[i];
                        final f = vc.venta.fechaHora;
                        final hora = TimeOfDay.fromDateTime(f).format(context);
                        // Qué se vendió, no cuántas líneas tenía: "2 línea(s)"
                        // no le sirve a nadie para reconocer una venta.
                        final sinpe = vc.venta.metodoPago == MetodoPago.sinpe;
                        return ListTile(
                          title: Text(vc.resumen, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            // El método solo se nombra cuando NO es el normal:
                            // poner "Efectivo" en nueve de cada diez ventas es
                            // ruido que hace más difícil ver la que sí importa.
                            sinpe
                                ? '${f.day}/${f.month} · $hora · SINPE'
                                      '${vc.venta.referenciaPago == null ? '' : ' · ${vc.venta.referenciaPago}'}'
                                : '${f.day}/${f.month} · $hora',
                          ),
                          trailing: Text('\u20a1${vc.total.toStringAsFixed(2)}'),
                          // Solo las de SINPE se tocan: es donde hay algo que
                          // anotar. Una venta en efectivo no tiene referencia
                          // que agregar, y abrir un diálogo vacío sería una
                          // promesa rota.
                          onTap: sinpe ? () => onAnotarReferencia(vc.venta) : null,
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
    return BentoDialogo(
      titulo: const Text('Exportar reporte'),
      contenido: Column(
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
      acciones: BentoAcciones(
        derecha: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      ),
    );
  }
}
