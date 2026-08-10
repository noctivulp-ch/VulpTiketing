import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../venta/venta_model.dart';
import 'reportes_provider.dart';

/// En qué se exporta un reporte.
///
/// CSV y no `.xlsx`: se abre igual en Excel, en LibreOffice y en Google Sheets,
/// se puede mirar con cualquier editor de texto si algo sale mal, y no arrastra
/// una dependencia más para escribir un formato binario. Lo que hace falta acá
/// es una tabla que el contador pueda abrir, no una hoja de cálculo con
/// fórmulas.
enum FormatoReporte {
  pdf('PDF', 'pdf', 'Para imprimir o mandar por WhatsApp'),
  csv('Tabla (CSV)', 'csv', 'Se abre en Excel, LibreOffice o Google Sheets');

  const FormatoReporte(this.etiqueta, this.extension, this.explicacion);

  final String etiqueta;
  final String extension;
  final String explicacion;
}

/// Arma el archivo de un reporte ya calculado. No consulta la base: recibe lo
/// que la pantalla ya tiene, así que exportar muestra exactamente lo mismo que
/// se está viendo — si volviera a consultar podría exportar otra cosa.
class ReporteExportService {
  const ReporteExportService();

  /// El archivo ya armado, en memoria.
  ///
  /// Se devuelve en bytes y no se escribe acá porque en Android el selector de
  /// archivos EXIGE los bytes: `saveFile` lanza `ArgumentError` si no se le
  /// pasan, y sin ellos exportar no llegaba ni a abrir el selector. Un reporte
  /// pesa unos pocos cientos de KB, así que tenerlo entero en memoria no es
  /// problema — a diferencia del backup, que por eso va por otro camino.
  ///
  /// [porTurno] solo cuando el período los tiene: exportando UN turno, una
  /// tabla de turnos con dos ceros y su propio total repetido no informa nada.
  Future<Uint8List> generar({
    required FormatoReporte formato,
    required String titulo,
    required double total,
    required List<VentaConLineas> ventas,
    Map<Turno, double>? porTurno,
    String? nota,
  }) async {
    switch (formato) {
      case FormatoReporte.csv:
        return Uint8List.fromList(
          utf8.encode(
            _csv(titulo: titulo, total: total, porTurno: porTurno, ventas: ventas, nota: nota),
          ),
        );
      case FormatoReporte.pdf:
        return Uint8List.fromList(
          await _pdf(titulo: titulo, total: total, porTurno: porTurno, ventas: ventas, nota: nota),
        );
    }
  }

  /// Escribe un CSV **completo** lote a lote, sin cargar el período entero en
  /// memoria.
  ///
  /// Existe porque un informe no puede venir recortado: la lista de pantalla
  /// tiene tope (`limiteDetalleRango`) porque nadie desplaza 5.000 filas, pero
  /// nadie manda a su contador un archivo que dice "incluye las 300 ventas más
  /// recientes de 2.847". Acá no hay tope, y por eso tampoco puede haber una
  /// lista entera en memoria.
  ///
  /// Devuelve cuántas ventas se escribieron.
  Future<int> escribirCsvPorLotes({
    required File destino,
    required String titulo,
    required double total,
    required Stream<List<VentaConLineas>> lotes,
    Map<Turno, double>? porTurno,
  }) async {
    final salida = destino.openWrite(encoding: utf8);
    var ventas = 0;
    var articulos = 0;
    try {
      // CRLF y BOM: sin ellos Excel en Windows abre el archivo en una sola
      // columna y con los acentos rotos. Es el destino más probable de esto.
      salida.write('\u{FEFF}');
      void fila(List<String> celdas) => salida.write('${_fila(celdas)}\r\n');

      fila(['Reporte', titulo]);
      fila(['Total', total.toStringAsFixed(2)]);
      if (porTurno != null) {
        for (final turno in Turno.values) {
          fila([_nombreTurno(turno), porTurno[turno]!.toStringAsFixed(2)]);
        }
      }
      salida.write('\r\n');
      fila(_cabeceraDetalle);

      await for (final lote in lotes) {
        for (final venta in lote) {
          ventas++;
          for (final l in venta.lineas) {
            articulos += l.linea.cantidad;
            fila(_filaDetalle(venta, l));
          }
        }
      }

      // El recuento va al FINAL porque hasta acá no se sabe: es el precio de no
      // tener el período entero en memoria, y es un precio barato.
      salida.write('\r\n');
      fila(['Ventas', '$ventas']);
      fila(['Artículos', '$articulos']);
    } finally {
      await salida.close();
    }
    return ventas;
  }

  static const _cabeceraDetalle = [
    'Fecha',
    'Hora',
    'Producto',
    'Cantidad',
    'Precio unitario',
    'Subtotal',
    'Nota',
    'Pago',
    'Referencia',
    'Venta',
  ];

  List<String> _filaDetalle(VentaConLineas venta, LineaDetallada l) => [
    _fecha(venta.venta.fechaHora),
    _hora(venta.venta.fechaHora),
    l.descripcion,
    '${l.linea.cantidad}',
    l.linea.precioAplicado.toStringAsFixed(2),
    l.subtotal.toStringAsFixed(2),
    l.linea.nota ?? '',
    // Cómo entró la plata y con qué referencia: es lo que se cruza contra el
    // estado de cuenta al cerrar el mes, y sin esas dos columnas habría que
    // volver a la app venta por venta.
    venta.venta.metodoPago.etiqueta,
    venta.venta.referenciaPago ?? '',
    // El id de la venta agrupa las líneas: sin él, dos ventas de la misma hora
    // se confunden al ordenar la tabla en Excel.
    venta.venta.id,
  ];

  /// Escribe el archivo en una ruta. Lo usan las pruebas y el escritorio, donde
  /// el selector sí devuelve una ruta escribible.
  Future<void> exportar({
    required String rutaDestino,
    required FormatoReporte formato,
    required String titulo,
    required double total,
    required List<VentaConLineas> ventas,
    Map<Turno, double>? porTurno,
    String? nota,
  }) async {
    await File(rutaDestino).writeAsBytes(
      await generar(
        formato: formato,
        titulo: titulo,
        total: total,
        ventas: ventas,
        porTurno: porTurno,
        nota: nota,
      ),
    );
  }

  String _csv({
    required String titulo,
    required double total,
    required List<VentaConLineas> ventas,
    Map<Turno, double>? porTurno,
    String? nota,
  }) {
    final articulos = ventas.fold<int>(
      0,
      (s, v) => s + v.lineas.fold<int>(0, (t, l) => t + l.linea.cantidad),
    );
    final lineas = <String>[
      _fila(['Reporte', titulo]),
      _fila(['Total', total.toStringAsFixed(2)]),
      _fila(['Ventas', '${ventas.length}']),
      _fila(['Artículos', '$articulos']),
      if (porTurno != null)
        for (final turno in Turno.values)
          _fila([_nombreTurno(turno), porTurno[turno]!.toStringAsFixed(2)]),
      '',
      // Una fila por LÍNEA, no por venta. Con una fila por venta lo único que
      // salía era "2 línea(s)": un archivo del que no se puede sacar qué se
      // vendió no sirve ni para el contador ni para revisar un día raro.
      _fila(_cabeceraDetalle),
      for (final venta in ventas)
        for (final l in venta.lineas) _fila(_filaDetalle(venta, l)),
      if (nota != null) ...[
        '',
        _fila([nota]),
      ],
    ];
    // CRLF y BOM: sin ellos Excel en Windows abre el archivo en una sola
    // columna y con los acentos rotos. Es el destino más probable de esto.
    return '﻿${lineas.join('\r\n')}\r\n';
  }

  /// Comillas dobles siempre: los nombres llevan comas y acentos, y un CSV
  /// partido por una coma de más no lo abre nadie.
  String _fila(List<String> celdas) => celdas.map((c) => '"${c.replaceAll('"', '""')}"').join(',');

  /// Las fuentes de fábrica del generador de PDF (Helvetica y compañía) NO
  /// tienen el símbolo del colón: el reporte de una soda costarricense salía
  /// con los montos sin moneda y un aviso en consola que nadie ve. Por eso se
  /// incrusta Noto Sans, que sí lo trae.
  ///
  /// Recortada a los caracteres que el reporte usa —ver
  /// `scripts/generar-fuente-pdf.sh`—: las dos variantes completas pesaban
  /// 1,2 MB y quedaron en 42 KB. Este APK corre en un teléfono de gama baja.
  Future<pw.ThemeData> _tema() async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  Future<List<int>> _pdf({
    required String titulo,
    required double total,
    required List<VentaConLineas> ventas,
    Map<Turno, double>? porTurno,
    String? nota,
  }) async {
    final doc = pw.Document(theme: await _tema());
    final masVendido = _masVendido(ventas);
    final articulos = ventas.fold<int>(
      0,
      (s, v) => s + v.lineas.fold<int>(0, (t, l) => t + l.linea.cantidad),
    );
    // Del detalle que se está exportando, no de otra consulta: el archivo tiene
    // que cuadrar consigo mismo.
    final sinpe = ventas
        .where((v) => v.venta.metodoPago == MetodoPago.sinpe)
        .fold<double>(0, (s, v) => s + v.total);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        // Calculado del contenido, no un número fijo. El paquete corta en 20
        // páginas por defecto y lanza `PdfTooBigPageException`; poner un tope
        // arbitrario solo mueve el problema, porque un informe recortado no es
        // un informe. Acá se estima de las filas que hay y se deja margen.
        maxPages: _paginasNecesarias(ventas),
        build: (context) => [
          pw.Header(level: 0, text: titulo),
          pw.Text(
            'Total: ₡${total.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('${ventas.length} venta(s) · $articulos artículo(s)'),
          // Cuánto entró por transferencia: es lo que se cruza contra el estado
          // de cuenta. Solo si hubo alguna — en un período sin SINPE la línea
          // no aporta.
          if (sinpe > 0)
            pw.Text(
              'Efectivo ₡${(total - sinpe).toStringAsFixed(2)}  ·  '
              'SINPE ₡${sinpe.toStringAsFixed(2)}',
            ),
          pw.SizedBox(height: 8),
          if (porTurno != null) ...[
            pw.TableHelper.fromTextArray(
              headers: const ['Turno', 'Total'],
              data: [
                for (final turno in Turno.values)
                  [_nombreTurno(turno), '₡${porTurno[turno]!.toStringAsFixed(2)}'],
              ],
            ),
            pw.SizedBox(height: 16),
          ],
          // Lo más vendido, antes del detalle: es lo que se mira primero para
          // decidir qué reponer, y sale gratis de lo que ya se trajo.
          if (masVendido.isNotEmpty) ...[
            pw.Text('Lo más vendido', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: const ['Producto', 'Cantidad', 'Total'],
              data: [
                for (final item in masVendido)
                  [item.$1, '${item.$2}', '₡${item.$3.toStringAsFixed(2)}'],
              ],
            ),
            pw.SizedBox(height: 16),
          ],
          pw.Text('Detalle', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          if (ventas.isEmpty)
            pw.Text('Sin ventas en el período.')
          else
            // Una fila por LÍNEA: antes decía "2 línea(s)" y no había forma de
            // saber qué se había vendido.
            pw.TableHelper.fromTextArray(
              headers: const ['Fecha', 'Hora', 'Producto', 'Cant.', 'Unitario', 'Subtotal', 'Pago'],
              cellAlignments: const {
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              data: [
                for (final venta in ventas)
                  for (final l in venta.lineas)
                    [
                      _fecha(venta.venta.fechaHora),
                      _hora(venta.venta.fechaHora),
                      l.linea.nota == null ? l.descripcion : '${l.descripcion} (${l.linea.nota})',
                      '${l.linea.cantidad}',
                      '₡${l.linea.precioAplicado.toStringAsFixed(2)}',
                      '₡${l.subtotal.toStringAsFixed(2)}',
                      // Solo se nombra lo que NO es lo normal, y con la
                      // referencia cuando está: en una columna de doscientas
                      // filas repetir "Efectivo" es ruido.
                      venta.venta.metodoPago == MetodoPago.sinpe
                          ? 'SINPE${venta.venta.referenciaPago == null ? '' : ' ${venta.venta.referenciaPago}'}'
                          : '',
                    ],
              ],
            ),
          if (nota != null) ...[
            pw.SizedBox(height: 8),
            pw.Text(nota, style: const pw.TextStyle(fontSize: 10)),
          ],
        ],
      ),
    );
    return doc.save();
  }

  /// Una cota SUPERIOR de las páginas que puede necesitar el detalle.
  ///
  /// No es una estimación de cuántas van a salir: es un número que el documento
  /// no puede superar pase lo que pase. Una fila ocupa como mucho una página
  /// entera —un nombre absurdamente largo—, así que "una página por fila, más
  /// diez para cabecera, turnos y ranking" no se queda corto nunca.
  ///
  /// Estimar el promedio fue el primer intento y estuvo mal: se calculó con 25
  /// filas por página, salieron 16, y el documento se cortó igual. El paquete
  /// usa este número como guardarraíl contra un widget que se repite infinito,
  /// no como tope de diseño — pasarse de generoso no cuesta nada, quedarse
  /// corto recorta el informe.
  int _paginasNecesarias(List<VentaConLineas> ventas) {
    final filas = ventas.fold<int>(0, (s, v) => s + v.lineas.length);
    return filas + 10;
  }

  /// Ranking del período exportado, calculado sobre las mismas ventas que van
  /// en el detalle. No se consulta la base: lo que se exporta tiene que cuadrar
  /// con lo que se exporta, aunque el reporte de pantalla haya cambiado.
  List<(String, int, double)> _masVendido(List<VentaConLineas> ventas) {
    final cantidades = <String, int>{};
    final montos = <String, double>{};
    for (final venta in ventas) {
      for (final l in venta.lineas) {
        cantidades[l.descripcion] = (cantidades[l.descripcion] ?? 0) + l.linea.cantidad;
        montos[l.descripcion] = (montos[l.descripcion] ?? 0) + l.subtotal;
      }
    }
    final orden = cantidades.keys.toList()
      ..sort((a, b) => cantidades[b]!.compareTo(cantidades[a]!));
    return [for (final nombre in orden.take(10)) (nombre, cantidades[nombre]!, montos[nombre]!)];
  }

  String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _nombreTurno(Turno turno) => nombreDeTurno(turno);
}
