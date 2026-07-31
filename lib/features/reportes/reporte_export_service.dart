import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

  /// [porTurno] solo cuando el período los tiene: exportando UN turno, una
  /// tabla de turnos con dos ceros y su propio total repetido no informa nada.
  Future<void> exportar({
    required String rutaDestino,
    required FormatoReporte formato,
    required String titulo,
    required double total,
    required List<VentaConLineas> ventas,
    Map<Turno, double>? porTurno,
    String? nota,
  }) async {
    final archivo = File(rutaDestino);
    switch (formato) {
      case FormatoReporte.csv:
        await archivo.writeAsString(
          _csv(titulo: titulo, total: total, porTurno: porTurno, ventas: ventas, nota: nota),
        );
      case FormatoReporte.pdf:
        await archivo.writeAsBytes(
          await _pdf(titulo: titulo, total: total, porTurno: porTurno, ventas: ventas, nota: nota),
        );
    }
  }

  String _csv({
    required String titulo,
    required double total,
    required List<VentaConLineas> ventas,
    Map<Turno, double>? porTurno,
    String? nota,
  }) {
    final lineas = <String>[
      _fila(['Reporte', titulo]),
      _fila(['Total', total.toStringAsFixed(2)]),
      if (porTurno != null)
        for (final turno in Turno.values)
          _fila([_nombreTurno(turno), porTurno[turno]!.toStringAsFixed(2)]),
      '',
      _fila(['Fecha', 'Hora', 'Líneas', 'Total']),
      for (final venta in ventas)
        _fila([
          _fecha(venta.venta.fechaHora),
          _hora(venta.venta.fechaHora),
          '${venta.lineas.length}',
          venta.total.toStringAsFixed(2),
        ]),
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
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, text: titulo),
          pw.Text(
            'Total: ₡${total.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
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
          pw.Text('Ventas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          if (ventas.isEmpty)
            pw.Text('Sin ventas en el período.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Fecha', 'Hora', 'Líneas', 'Total'],
              data: [
                for (final venta in ventas)
                  [
                    _fecha(venta.venta.fechaHora),
                    _hora(venta.venta.fechaHora),
                    '${venta.lineas.length}',
                    '₡${venta.total.toStringAsFixed(2)}',
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

  String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _nombreTurno(Turno turno) => switch (turno) {
    Turno.manana => 'Mañana',
    Turno.tarde => 'Tarde',
    Turno.noche => 'Noche',
  };
}
