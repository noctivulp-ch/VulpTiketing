import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/import_export/almacen_publico.dart';

/// El tipo con el que se publica cada archivo en Descargas.
///
/// Parece un detalle y no lo es: MediaStore **renombra el archivo** para que la
/// extensión case con el tipo que se declara. Con el tipo equivocado, un
/// `catalogo.tiketdata` termina llamándose `catalogo.tiketdata.json` y el
/// selector de importar deja de reconocerlo — pasó en el aparato.
void main() {
  group('el tipo de cada formato', () {
    test('los formatos propios van como binario, aunque sean JSON por dentro', () {
      // `.tiketdata` ES json, y declararlo como tal es justamente lo que rompía
      // el nombre. La extensión es parte del formato: es por lo que el selector
      // de importar lo reconoce.
      expect(AlmacenPublico.mimeDe('catalogo.tiketdata'), 'application/octet-stream');
      expect(
        AlmacenPublico.mimeDe('vulptiketing-2026-08-03.tiketback'),
        'application/octet-stream',
      );
    });

    test('PDF y CSV sí llevan el suyo', () {
      // Es lo que hace que tocarlos desde Descargas ofrezca con qué abrirlos, y
      // su extensión ya coincide con el tipo, así que MediaStore no los toca.
      expect(AlmacenPublico.mimeDe('reporte-mes.pdf'), 'application/pdf');
      expect(AlmacenPublico.mimeDe('reporte-mes.csv'), 'text/csv');
    });

    test('da igual cómo esté escrita la extensión', () {
      expect(AlmacenPublico.mimeDe('REPORTE.PDF'), 'application/pdf');
      expect(AlmacenPublico.mimeDe('Reporte.Csv'), 'text/csv');
    });

    test('un nombre con puntos usa la ÚLTIMA extensión', () {
      // Los reportes se llaman "reporte-anio-2026-01-01.csv": si se tomara el
      // primer punto, el tipo saldría de "-2026-01-01.csv".
      expect(AlmacenPublico.mimeDe('reporte-anio-2026-01-01.csv'), 'text/csv');
    });

    test('lo desconocido cae a binario, no a un tipo inventado', () {
      // Declarar un tipo que no es hace que MediaStore renombre. Binario es la
      // respuesta honesta: "no sé qué es esto, no lo toques".
      expect(AlmacenPublico.mimeDe('sin-extension'), 'application/octet-stream');
      expect(AlmacenPublico.mimeDe('algo.raro'), 'application/octet-stream');
    });
  });
}
