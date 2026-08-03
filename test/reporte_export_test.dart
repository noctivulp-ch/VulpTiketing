import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/reportes/reporte_export_service.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';
import 'package:vulp_tiketing/features/venta/linea_venta_model.dart';
import 'package:vulp_tiketing/features/venta/venta_model.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('vulp-export'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  VentaConLineas venta(
    String id,
    DateTime cuando,
    double precio, {
    String descripcion = 'Casado con pollo',
    int cantidad = 1,
    String? nota,
  }) => VentaConLineas(
    venta: Venta(id: id, fechaHora: cuando, estado: EstadoVenta.activa, updatedAt: cuando),
    lineas: [
      LineaDetallada(
        descripcion: descripcion,
        linea: LineaVenta(
          id: '$id-1',
          ventaId: id,
          productoId: 'p1',
          precioAplicado: precio,
          cantidad: cantidad,
          nota: nota,
          updatedAt: cuando,
        ),
      ),
    ],
  );

  final reporte = ReporteResultado(
    total: 3000,
    porTurno: {Turno.manana: 1000, Turno.tarde: 2000, Turno.noche: 0},
    ventasPorTurno: {Turno.manana: const [], Turno.tarde: const [], Turno.noche: const []},
    masVendidos: const [],
    menosVendidos: const [],
  );

  final ventas = [
    venta('v1', DateTime(2026, 3, 4, 9, 5), 1000),
    venta('v2', DateTime(2026, 3, 4, 14, 30), 2000),
  ];

  // El binding hace falta para `rootBundle`: el PDF incrusta su fuente desde
  // los assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String> exportarCsv({String? nota}) async {
    final ruta = '${dir.path}/reporte.csv';
    await const ReporteExportService().exportar(
      rutaDestino: ruta,
      formato: FormatoReporte.csv,
      titulo: 'Ventas del día · 4/3/2026',
      total: reporte.total,
      porTurno: reporte.porTurno,
      ventas: ventas,
      nota: nota,
    );
    return File(ruta).readAsString();
  }

  test('el CSV lleva el total, los turnos y una fila por línea', () async {
    final csv = await exportarCsv();

    expect(csv, contains('"Total","3000.00"'));
    expect(csv, contains('"Mañana","1000.00"'));
    // QUÉ se vendió, no cuántas líneas tenía la venta: el reporte decía
    // "2 línea(s)" y con eso no se puede revisar un día raro ni cuadrar caja.
    expect(csv, contains('"04/03/2026","09:05","Casado con pollo","1","1000.00","1000.00"'));
    expect(csv, contains('"04/03/2026","14:30","Casado con pollo","1","2000.00","2000.00"'));
  });

  test('el CSV trae cantidad, nota y el id que agrupa las líneas', () async {
    final ruta = '${dir.path}/detalle.csv';
    await const ReporteExportService().exportar(
      rutaDestino: ruta,
      formato: FormatoReporte.csv,
      titulo: 'Detalle',
      total: 7500,
      ventas: [
        venta(
          'v9',
          DateTime(2026, 3, 4, 12),
          2500,
          descripcion: 'Batido de mora',
          cantidad: 3,
          nota: 'sin azúcar',
        ),
      ],
    );
    final csv = await File(ruta).readAsString();

    expect(csv, contains('"Batido de mora","3","2500.00","7500.00","sin azúcar","v9"'));
    // El encabezado dice qué es cada columna: un CSV sin encabezado obliga a
    // adivinar cuál de los dos montos es el unitario.
    expect(csv, contains('"Producto","Cantidad","Precio unitario","Subtotal"'));
    expect(csv, contains('"Artículos","3"'), reason: 'tres unidades, no una línea');
  });

  test('el CSV abre bien en Excel: BOM y saltos CRLF', () async {
    // Sin esto, Excel en Windows —el destino más probable— lo abre en una sola
    // columna y con los acentos rotos. Se comprueba en BYTES: al leer como
    // texto, el decodificador de UTF-8 se come el BOM y la prueba pasaría
    // aunque el archivo no lo tuviera.
    await exportarCsv();
    final bytes = await File('${dir.path}/reporte.csv').readAsBytes();

    expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF], reason: 'falta el BOM');
    expect(await File('${dir.path}/reporte.csv').readAsString(), contains('\r\n'));
  });

  test('una lista recortada lo dice DENTRO del archivo', () async {
    // Un reporte que omite ventas sin avisar es peor que no exportar nada:
    // alguien cuadraría caja contra un total incompleto sin saberlo.
    final csv = await exportarCsv(nota: 'Incluye las 300 ventas más recientes de 1200.');

    expect(csv, contains('300 ventas más recientes de 1200'));
  });

  test('las comillas del contenido no rompen la tabla', () async {
    final ruta = '${dir.path}/comillas.csv';
    await const ReporteExportService().exportar(
      rutaDestino: ruta,
      formato: FormatoReporte.csv,
      titulo: 'Reporte "especial", con coma',
      total: reporte.total,
      porTurno: reporte.porTurno,
      ventas: const [],
    );

    final csv = await File(ruta).readAsString();
    expect(csv, contains('"Reporte ""especial"", con coma"'));
  });

  test('el PDF escribe el símbolo del colón', () async {
    // Las fuentes de fábrica del generador no tienen ₡ y los montos salían sin
    // moneda, avisando solo por consola. Si el archivo no trae la fuente
    // incrustada, es que se volvió a caer en eso.
    final ruta = '${dir.path}/moneda.pdf';
    await const ReporteExportService().exportar(
      rutaDestino: ruta,
      formato: FormatoReporte.pdf,
      titulo: 'Ventas del día',
      total: reporte.total,
      porTurno: reporte.porTurno,
      ventas: ventas,
    );

    final crudo = String.fromCharCodes(await File(ruta).readAsBytes());
    expect(crudo, contains('NotoSans'), reason: 'el PDF no incrustó la fuente con ₡');
  });

  test('el PDF sale como PDF', () async {
    final ruta = '${dir.path}/reporte.pdf';
    await const ReporteExportService().exportar(
      rutaDestino: ruta,
      formato: FormatoReporte.pdf,
      titulo: 'Ventas del mes',
      total: reporte.total,
      porTurno: reporte.porTurno,
      ventas: ventas,
    );

    final bytes = await File(ruta).readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  test('exportar UN turno no incluye la tabla de turnos', () async {
    // Con dos ceros y su propio total repetido, esa tabla no informa nada.
    final ruta = '${dir.path}/turno.csv';
    await const ReporteExportService().exportar(
      rutaDestino: ruta,
      formato: FormatoReporte.csv,
      titulo: 'Tarde · 4/3/2026',
      total: 2000,
      ventas: ventas,
    );

    final csv = await File(ruta).readAsString();
    expect(csv, contains('"Total","2000.00"'));
    expect(csv, isNot(contains('"Mañana"')));
    expect(csv, isNot(contains('"Noche"')));
  });

  test('un período sin ventas exporta igual, no falla', () async {
    final ruta = '${dir.path}/vacio.pdf';
    await const ReporteExportService().exportar(
      rutaDestino: ruta,
      formato: FormatoReporte.pdf,
      titulo: 'Ventas del día',
      total: reporte.total,
      porTurno: reporte.porTurno,
      ventas: const [],
    );

    expect(File(ruta).existsSync(), isTrue);
  });

  test('el PDF de un año entero no revienta por el tope de páginas', () async {
    // El fallo que el usuario encontró en el aparato: exportar el año en PDF
    // decía "no se pudo guardar el reporte". El generador corta en 20 páginas y
    // lanza `PdfTooBigPageException`; con una fila por VENTA cabía justo, y
    // desde que el detalle va línea por línea, no.
    //
    // 300 ventas es el tope real de `limiteDetalleRango`, y dos líneas por
    // venta es el promedio de la base de pruebas.
    final muchas = [
      for (var i = 0; i < 300; i++)
        VentaConLineas(
          venta: Venta(
            id: 'v$i',
            fechaHora: DateTime(2026, 1 + (i % 12), 1 + (i % 28), 8 + (i % 12)),
            estado: EstadoVenta.activa,
            updatedAt: DateTime(2026),
          ),
          lineas: [
            for (var j = 0; j < 2; j++)
              LineaDetallada(
                descripcion: 'Casado con chuleta cerdo encebollada $j',
                linea: LineaVenta(
                  id: 'l$i-$j',
                  ventaId: 'v$i',
                  productoId: 'p1',
                  precioAplicado: 2500,
                  cantidad: 1 + (j % 3),
                  updatedAt: DateTime(2026),
                ),
              ),
          ],
        ),
    ];

    final bytes = await const ReporteExportService().generar(
      formato: FormatoReporte.pdf,
      titulo: 'Ventas del año · 2026',
      total: 1500000,
      porTurno: {Turno.manana: 500000, Turno.tarde: 700000, Turno.noche: 300000},
      ventas: muchas,
    );

    expect(bytes.length, greaterThan(10000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
