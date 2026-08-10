import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/import_export/archivo_entrante_service.dart';

/// Qué hace la app con el archivo que se tocó en el explorador.
///
/// La extensión es lo ÚNICO que separa un catálogo de un respaldo completo, y de
/// esa decisión depende si se importan productos o se pisa la base entera. El
/// filtro del manifest va por patrón de ruta —no por tipo MIME, porque estas dos
/// extensiones no las conoce el sistema— y un patrón puede colar algo que no es
/// nuestro, así que acá se vuelve a comprobar.
void main() {
  test('un .tiketdata es catálogo', () {
    expect(ArchivoEntranteService.claseDe('menu-de-ejemplo.tiketdata'), ClaseDeArchivo.catalogo);
  });

  test('un .tiketback es respaldo', () {
    expect(
      ArchivoEntranteService.claseDe('respaldo-2026-08-10.tiketback'),
      ClaseDeArchivo.respaldo,
    );
  });

  test('la extensión en mayúsculas vale igual', () {
    // Un archivo que dio la vuelta por WhatsApp o por correo puede llegar con la
    // extensión cambiada de caja.
    expect(ArchivoEntranteService.claseDe('MENU.TIKETDATA'), ClaseDeArchivo.catalogo);
    expect(ArchivoEntranteService.claseDe('Respaldo.TiketBack'), ClaseDeArchivo.respaldo);
  });

  test('lo que no es nuestro se descarta', () {
    // El filtro del manifest usa mimeType */* junto al patrón de ruta, así que
    // puede llegar cualquier cosa. Aplicar un archivo ajeno como si fuera un
    // catálogo dejaría la carta en un estado imposible de explicar.
    for (final nombre in ['foto.jpg', 'reporte.csv', 'datos.db', 'respaldo.zip', 'sinextension']) {
      expect(ArchivoEntranteService.claseDe(nombre), isNull, reason: nombre);
    }
  });

  test('no basta con que la extensión aparezca en el medio del nombre', () {
    // "menu.tiketdata.txt" es un .txt: alguien lo renombró o el gestor de
    // descargas le pegó la extensión detrás.
    expect(ArchivoEntranteService.claseDe('menu.tiketdata.txt'), isNull);
    expect(ArchivoEntranteService.claseDe('respaldo.tiketback.bak'), isNull);
  });

  test('un nombre que solo es la extensión también se acepta', () {
    // Poco probable, pero el archivo es válido y rechazarlo por el nombre sería
    // rechazar datos buenos.
    expect(ArchivoEntranteService.claseDe('.tiketdata'), ClaseDeArchivo.catalogo);
  });
}
