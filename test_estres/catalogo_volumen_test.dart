// Grupos B y E — catálogo grande y `.tiketdata`.
//
// El catálogo no crece como las ventas: una soda tiene decenas de productos, no
// miles. Pero `productoQueryProvider` filtra y ordena EN DART en cada pulsación
// de tecla, y `.tiketdata` está pensado para compartirse entre negocios — así
// que el techo razonable acá es un catálogo mucho más grande que el propio, por
// si alguien importa uno ajeno.
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/import_export/tiketdata_service.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_query_provider.dart';

import '_escalera.dart';
import '_generador.dart';

/// Catálogos a probar. 40 es el real de la soda; 5.000 es el absurdo
/// deliberado, para ver dónde deja de responder el filtrado por tecla.
const _tamanos = [40, 500, 5000];

final _tabla = <List<String>>[];
void _anotar(String caso, String medicion, String valor, [String extra = '']) =>
    _tabla.add([caso, medicion, valor, extra]);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // El analizador no reconoce `test_estres/` como directorio de pruebas —
    // está fuera de `test/` a propósito, para que `flutter test` no lo recorra —
    // así que hay que silenciarle esta advertencia. Es una prueba igual.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() {
    if (_tabla.isEmpty) return;
    final anchos = [0, 1, 2, 3]
        .map((c) => _tabla.map((f) => f[c].length).reduce((a, b) => a > b ? a : b))
        .toList();
    stdout.writeln('\n=== MEDICIONES — grupos B y E, catálogo ===');
    for (final f in _tabla) {
      stdout.writeln('  ${f[0].padRight(anchos[0])}  ${f[1].padRight(anchos[1])}  '
          '${f[2].padLeft(anchos[2])}  ${f[3]}');
    }
  });

  Future<Database> conCatalogo(int cuantos) async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    await db.transaction((txn) async {
      await txn.insert('categoria', {
        'id': 'c1',
        'nombre': 'General',
        'updated_at': DateTime(2020).toIso8601String(),
      });
      for (var i = 0; i < cuantos; i++) {
        await txn.insert('producto', {
          'id': 'p$i',
          'nombre': 'Producto ${i.toString().padLeft(5, "0")} casado empanada café',
          'categoria_id': 'c1',
          'precio_base': 800 + (i % 30) * 100,
          'updated_at': DateTime(2020).toIso8601String(),
        });
      }
    });
    return db;
  }

  for (final cuantos in _tamanos) {
    group('catálogo de $cuantos productos', () {
      test('filtrar por pulsación de tecla', () async {
        final db = await conCatalogo(cuantos);
        addTearDown(db.close);

        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
        );
        addTearDown(container.dispose);

        // Calentamiento del camino COMPLETO, no solo del notifier. Sin esto la
        // primera medición incluye la carga desde SQLite, la inicialización del
        // provider derivado y el JIT — y eso dominaba el resultado: el catálogo
        // de 40 productos "tardaba" 16 ms mientras el de 500 tardaba 1 ms, que
        // es imposible. Se estaba midiendo el arranque, no el filtrado.
        await container.read(productoNotifierProvider.future);
        for (final calentar in ['a', 'ab', 'abc']) {
          container.read(productoBusquedaProvider.notifier).state = calentar;
          container.read(productoQueryProvider).valueOrNull?.length;
        }

        // Simula escribir "empanada" letra por letra, que es el caso real: cada
        // pulsación re-filtra y re-ordena la lista completa en Dart. Se repite
        // varias veces y se toma la MEDIANA: una sola pasada es demasiado
        // sensible al ruido del planificador para medir milisegundos.
        const termino = 'empanada';
        final muestras = <Duration>[];
        for (var repeticion = 0; repeticion < 5; repeticion++) {
          for (var i = 1; i <= termino.length; i++) {
            final reloj = Stopwatch()..start();
            container.read(productoBusquedaProvider.notifier).state =
                '${termino.substring(0, i)}${" " * repeticion}';
            container.read(productoQueryProvider).valueOrNull?.length;
            reloj.stop();
            muestras.add(reloj.elapsed);
          }
        }
        muestras.sort();
        final peor = muestras[(muestras.length * 0.9).floor()]; // percentil 90

        final presupuesto = presupuestoLaptop(objetivoBusquedaPorTecla);
        _anotar('$cuantos productos', 'tecla (p90)', ms(peor),
            peor <= presupuesto ? 'OK' : 'excede ${ms(presupuesto)}');

        // Presupuesto duro solo en el catálogo realista: 5.000 productos en una
        // soda no va a pasar, y exigirlo sería inventar un requisito.
        if (cuantos <= 500) {
          expect(peor, lessThanOrEqualTo(presupuesto),
              reason: 'filtrar $cuantos productos por tecla tardó ${ms(peor)}');
        }
      });
    });
  }

  group('importar .tiketdata', () {
    for (final cuantos in [500, 5000]) {
      test('$cuantos productos, modo fusionar', () async {
        final origen = await conCatalogo(cuantos);
        addTearDown(origen.close);

        final temporal = Directory.systemTemp.createTempSync('vulp-tiketdata');
        addTearDown(() => temporal.deleteSync(recursive: true));
        final archivo = p.join(temporal.path, 'catalogo.tiketdata');

        await TiketdataService(origen).exportarCatalogo(archivo);
        final pesoKb = File(archivo).lengthSync() / 1024;

        final destino = await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        addTearDown(destino.close);
        await AppDatabase.crearEsquema(destino);

        final reloj = Stopwatch()..start();
        await TiketdataService(destino).importarCatalogo(
          rutaOrigen: archivo,
          modo: ModoImportacion.fusionar,
        );
        reloj.stop();

        _anotar('$cuantos productos', 'importar (fusionar)', ms(reloj.elapsed),
            'archivo ${pesoKb.toStringAsFixed(0)} KB');

        // Correctitud: tiene que llegar todo.
        final llegaron =
            (await destino.rawQuery('SELECT COUNT(*) c FROM producto')).first['c'] as int;
        expect(llegaron, equals(cuantos));

        expect(reloj.elapsed, lessThan(umbralCatastrofe));
      });
    }

    test('importar dos veces no duplica ni pierde nada', () async {
      // Compartir un catálogo entre negocios implica reimportarlo cuando cambia.
      // Si la segunda importación duplicara productos, el catálogo del negocio
      // quedaría inservible.
      const cuantos = 500;
      final origen = await conCatalogo(cuantos);
      addTearDown(origen.close);

      final temporal = Directory.systemTemp.createTempSync('vulp-tiketdata2');
      addTearDown(() => temporal.deleteSync(recursive: true));
      final archivo = p.join(temporal.path, 'catalogo.tiketdata');
      await TiketdataService(origen).exportarCatalogo(archivo);

      final destino = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(destino.close);
      await AppDatabase.crearEsquema(destino);

      final servicio = TiketdataService(destino);
      await servicio.importarCatalogo(
          rutaOrigen: archivo, modo: ModoImportacion.fusionar);
      await servicio.importarCatalogo(
          rutaOrigen: archivo, modo: ModoImportacion.fusionar);

      final total =
          (await destino.rawQuery('SELECT COUNT(*) c FROM producto')).first['c'] as int;
      expect(total, equals(cuantos), reason: 'reimportar no puede duplicar productos');
    });

    test('un archivo corrupto no deja el catalogo a medias', () async {
      // Compartir archivos entre dispositivos implica que alguno va a llegar
      // truncado. Lo que no puede pasar es que se apliquen las primeras filas y
      // el resto no: `RowUpserter` ahora usa transacción justamente por esto.
      final destino = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(destino.close);
      await AppDatabase.crearEsquema(destino);

      final temporal = Directory.systemTemp.createTempSync('vulp-tiketdata3');
      addTearDown(() => temporal.deleteSync(recursive: true));
      final archivo = p.join(temporal.path, 'roto.tiketdata');

      // JSON valido en su forma, pero con una fila que le falta una columna
      // obligatoria: revienta a mitad de la aplicacion.
      File(archivo).writeAsStringSync(jsonEncode({
        'categorias': [
          {
            'id': 'c1',
            'nombre': 'General',
            'updated_at': DateTime(2020).toIso8601String(),
            'deleted_at': null,
          }
        ],
        'productos': [
          {
            'id': 'p1',
            'nombre': 'Bueno',
            'imagen': null,
            'categoria_id': 'c1',
            'precio_base': 900,
            'updated_at': DateTime(2020).toIso8601String(),
            'deleted_at': null,
          },
          {'id': 'p2', 'columna_que_no_existe': 1},
        ],
      }));

      await expectLater(
        TiketdataService(destino).importarCatalogo(
          rutaOrigen: archivo,
          modo: ModoImportacion.fusionar,
        ),
        throwsA(anything),
      );

      // La transaccion tiene que haber revertido el lote de productos completo.
      final productos =
          (await destino.rawQuery('SELECT COUNT(*) c FROM producto')).first['c'] as int;
      expect(productos, equals(0),
          reason: 'un lote que falla no puede dejar filas aplicadas a medias');
    });
  });
}
