// Grupo D — backup `.tiketback` con volumen.
//
// `TiketbackService` lee la base ENTERA a memoria, la cifra y escribe el
// resultado. El pico esperado es ~3× el tamaño del archivo (bytes originales +
// texto cifrado + bundle empaquetado). En una tablet limitada eso es lo primero
// que puede quedarse sin memoria, así que acá interesa tanto el tiempo como el
// RSS.
@Timeout(Duration(minutes: 45))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/features/import_export/tiketback_service.dart';

import '_escalera.dart';
import '_generador.dart';

final _tabla = <List<String>>[];
void _anotar(String nivel, String medicion, String valor, [String extra = '']) =>
    _tabla.add([nivel, medicion, valor, extra]);

void main() {
  setUpAll(() {
    // `TiketbackService` empaqueta las preferencias junto a la base, asi que
    // necesita el binding de Flutter y SharedPreferences mockeado — si no,
    // falla con "Binding has not yet been initialized" antes de cifrar nada.
    TestWidgetsFlutterBinding.ensureInitialized();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() {
    if (_tabla.isEmpty) return;
    final anchos = [0, 1, 2, 3]
        .map((c) => _tabla.map((f) => f[c].length).reduce((a, b) => a > b ? a : b))
        .toList();
    stdout.writeln('\n=== MEDICIONES — grupo D, backup .tiketback ===');
    for (final f in _tabla) {
      stdout.writeln('  ${f[0].padRight(anchos[0])}  ${f[1].padRight(anchos[1])}  '
          '${f[2].padLeft(anchos[2])}  ${f[3]}');
    }
  });

  // Solo los niveles cacheables tienen archivo en disco que copiar; el realista
  // se genera en memoria y no tiene archivo que cifrar.
  for (final nivel in nivelesActivos.where((n) => n.cacheable)) {
    group('nivel ${nivel.nombre}', () {
      late Directory temporal;
      late String rutaDb;

      setUpAll(() async {
        // Genera (o reutiliza) la base del nivel, y copia su archivo: el backup
        // trabaja sobre el archivo, no sobre la conexión.
        final base = await baseCon(nivel, log: stdout.writeln);
        final origen = await _rutaDe(base.db);
        await base.db.close();

        temporal = Directory.systemTemp.createTempSync('vulp-backup-${nivel.nombre}');
        rutaDb = p.join(temporal.path, 'copia.db');
        if (origen != null) File(origen).copySync(rutaDb);
      });

      tearDownAll(() {
        if (temporal.existsSync()) temporal.deleteSync(recursive: true);
      });

      test('exportar y restaurar conserva los bytes exactos', () async {
        final tamanoMb = File(rutaDb).lengthSync() / (1024 * 1024);
        _anotar(nivel.nombre, 'tamaño de la base', '${tamanoMb.toStringAsFixed(1)} MB');

        final servicio = TiketbackService();
        final destino = p.join(temporal.path, 'backup.tiketback');
        final original = File(rutaDb).readAsBytesSync();

        final rssAntesExportar = rssMb();
        final (_, tomoExportar) = await medir(() => servicio.exportar(
              contrasenaExportacion: 'clave-de-estres',
              directorioDatos: temporal.path,
              nombreBasePrincipal: p.basename(rutaDb),
              archivosDeLibro: const [],
              rutaDestino: destino,
            ));
        final picoExportar = rssMb();

        final backupMb = File(destino).lengthSync() / (1024 * 1024);
        _anotar(nivel.nombre, 'exportar', ms(tomoExportar),
            'backup ${backupMb.toStringAsFixed(1)} MB, RSS +${picoExportar - rssAntesExportar} MB');

        final rssAntesRestaurar = rssMb();
        final (_, tomoRestaurar) = await medir(() => servicio.restaurar(
              contrasenaExportacion: 'clave-de-estres',
              directorioDatos: temporal.path,
              nombreBasePrincipal: p.basename(rutaDb),
              rutaOrigen: destino,
              alcance: AlcanceRestauracion.todo,
            ));
        final picoRestaurar = rssMb();
        _anotar(nivel.nombre, 'restaurar', ms(tomoRestaurar),
            'RSS +${picoRestaurar - rssAntesRestaurar} MB');

        // Integridad: el backup no sirve si no devuelve exactamente lo mismo.
        final restaurado = File(rutaDb).readAsBytesSync();
        expect(restaurado.length, equals(original.length),
            reason: 'el tamaño restaurado no coincide en ${nivel.nombre}');
        expect(restaurado, equals(original),
            reason: 'los bytes restaurados no son idénticos en ${nivel.nombre}');

        expect(tomoExportar, lessThan(umbralCatastrofe),
            reason: 'exportar en ${nivel.nombre} tardó ${ms(tomoExportar)}');
        expect(tomoRestaurar, lessThan(umbralCatastrofe),
            reason: 'restaurar en ${nivel.nombre} tardó ${ms(tomoRestaurar)}');
      });

      test('la contraseña equivocada no restaura nada', () async {
        // Con volumen el riesgo es distinto al del caso chico: si la
        // verificación del MAC ocurriera DESPUÉS de escribir, una clave mala
        // dejaría la base destruida. Tiene que fallar antes de tocar el archivo.
        final servicio = TiketbackService();
        final destino = p.join(temporal.path, 'backup2.tiketback');
        await servicio.exportar(
          contrasenaExportacion: 'la-correcta',
          directorioDatos: temporal.path,
          nombreBasePrincipal: p.basename(rutaDb),
          archivosDeLibro: const [],
          rutaDestino: destino,
        );

        final antes = File(rutaDb).readAsBytesSync();
        await expectLater(
          servicio.restaurar(
            contrasenaExportacion: 'la-incorrecta',
            directorioDatos: temporal.path,
            nombreBasePrincipal: p.basename(rutaDb),
            rutaOrigen: destino,
            alcance: AlcanceRestauracion.todo,
          ),
          throwsA(anything),
        );
        expect(File(rutaDb).readAsBytesSync(), equals(antes),
            reason: 'una clave incorrecta no puede dejar la base a medio escribir');
      });
    });
  }
}

/// Ruta del archivo de una conexión abierta, vía `PRAGMA database_list`.
Future<String?> _rutaDe(Database db) async {
  final rows = await db.rawQuery('PRAGMA database_list');
  for (final row in rows) {
    if (row['name'] == 'main') {
      final archivo = row['file'] as String?;
      if (archivo != null && archivo.isNotEmpty) return archivo;
    }
  }
  return null;
}
