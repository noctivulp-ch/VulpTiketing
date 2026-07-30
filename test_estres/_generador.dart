// Genera bases de datos con volumen para las pruebas de estrés.
//
// Usa `AppDatabase.esquema` — el DDL real de la app, no una copia — para que
// el esquema de las pruebas no pueda divergir del de producción.
//
// Dos estrategias según el tamaño:
// - **En memoria** para el nivel realista: 350 k filas se generan en segundos.
// - **En archivo cacheado en disco** para los niveles grandes: regenerar 11–22
//   M de filas en cada corrida haría la suite inusable. La caché se invalida
//   por `_versionGenerador`.


import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';

import '_escalera.dart';

/// Subir esto invalida todas las cachés en disco. Hacerlo al cambiar la forma
/// de los datos generados o el esquema.
const _versionGenerador = 1;

/// Catálogo real de la soda, con la mezcla que importa: los primeros 8
/// son los items de alta rotación (₡800–1.000) y son los que se venden más.
/// Generar con precios uniformes daría un ticket promedio irreal y mediciones
/// engañosas.
const _catalogoBarato = [
  ('Pasteles arroz con pollo', 800.0),
  ('Café negro', 800.0),
  ('Tamarindo', 800.0),
  ('Chan', 800.0),
  ('Empanada frita', 900.0),
  ('Frutas', 900.0),
  ('Café con leche', 1000.0),
  ('Horchata', 1000.0),
];

const _catalogoCaro = [
  ('Casado con bistec res encebollado', 3000.0),
  ('Casado con carne en salsa', 3000.0),
  ('Arroz cantones (entero)', 3800.0),
  ('Arroz con pollo tipo chino (entero)', 3500.0),
  ('Pinto con carne en salsa', 2800.0),
  ('Hamburguesa con papas', 2500.0),
  ('Pollo frito (pechuga y ala)', 2500.0),
  ('Frappé de café', 2800.0),
];

class BaseDeEstres {
  BaseDeEstres({required this.db, required this.nivel, required this.productoIds, required this.totalSembrado});

  final Database db;
  final Nivel nivel;
  final List<String> productoIds;

  /// Suma exacta de todo lo sembrado. Las pruebas de correctitud comparan el
  /// total del reporte contra esto: una medición de rendimiento sobre un
  /// cálculo incorrecto no vale nada.
  final double totalSembrado;
}

/// Las bases cacheadas van a DISCO REAL, no a `Directory.systemTemp`.
///
/// En Linux `/tmp` suele ser tmpfs, o sea RAM. Medir I/O de base de datos ahí
/// daría números irreales — el objetivo es una tablet con almacenamiento lento,
/// el extremo opuesto — y además una base de 1,7 GB consumiría memoria en vez
/// de disco. Se puede redirigir con `VULP_ESTRES_CACHE`.
String _rutaCache(Nivel nivel) {
  final base = Platform.environment['VULP_ESTRES_CACHE'] ??
      p.join(Platform.environment['HOME']!, '.cache', 'vulptiketing', 'estres');
  final dir = Directory(base);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return p.join(dir.path, 'v$_versionGenerador-${nivel.nombre}.db');
}

/// Devuelve una base con el volumen del nivel. Si el nivel es cacheable y la
/// caché existe, la reutiliza.
Future<BaseDeEstres> baseCon(Nivel nivel, {void Function(String)? log}) async {
  final avisar = log ?? (_) {};

  if (nivel.cacheable) {
    final ruta = _rutaCache(nivel);
    if (File(ruta).existsSync()) {
      avisar('  [${nivel.nombre}] usando cache en disco');
      final db = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      return BaseDeEstres(
        db: db,
        nivel: nivel,
        productoIds: await _idsDeProducto(db),
        totalSembrado: await _totalDe(db),
      );
    }
    avisar('  [${nivel.nombre}] generando ${nivel.filas} filas en disco (una sola vez)…');
    final db = await databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final total = await _poblar(db, nivel, avisar);
    return BaseDeEstres(
      db: db,
      nivel: nivel,
      productoIds: await _idsDeProducto(db),
      totalSembrado: total,
    );
  }

  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  final total = await _poblar(db, nivel, avisar);
  return BaseDeEstres(
    db: db,
    nivel: nivel,
    productoIds: await _idsDeProducto(db),
    totalSembrado: total,
  );
}

Future<List<String>> _idsDeProducto(Database db) async {
  final rows = await db.query('producto', columns: ['id']);
  return rows.map((r) => r['id'] as String).toList();
}

Future<double> _totalDe(Database db) async {
  final r = await db.rawQuery(
    'SELECT SUM(precio_aplicado * cantidad) AS t FROM linea_venta',
  );
  return (r.first['t'] as num?)?.toDouble() ?? 0;
}

/// Inserción por lotes en transacciones. Fila por fila con commit propio sería
/// órdenes de magnitud más lento — que es exactamente el problema que estas
/// pruebas van a medir en `RowUpserter`, pero acá no se está probando eso: es
/// fixture, y tiene que ser rápido.
Future<double> _poblar(Database db, Nivel nivel, void Function(String) avisar) async {
  await AppDatabase.crearEsquema(db);

  final aleatorio = Random(42); // semilla fija: volúmenes reproducibles
  final catalogo = [..._catalogoBarato, ..._catalogoCaro];

  final categoriaId = 'cat-estres';
  final productoIds = <String>[];
  await db.transaction((txn) async {
    await txn.insert('categoria', {
      'id': categoriaId,
      'nombre': 'Estrés',
      'updated_at': DateTime(2020).toIso8601String(),
    });
    for (var i = 0; i < catalogo.length; i++) {
      final id = 'prod-$i';
      productoIds.add(id);
      await txn.insert('producto', {
        'id': id,
        'nombre': catalogo[i].$1,
        'imagen': null,
        'categoria_id': categoriaId,
        'precio_base': catalogo[i].$2,
        'updated_at': DateTime(2020).toIso8601String(),
      });
    }
  });

  // 70 % de las líneas caen en los 8 items baratos: esa es la mezcla que
  // produce el ticket real del negocio.
  int indiceProductoSesgado() {
    if (aleatorio.nextDouble() < 0.7) {
      return aleatorio.nextInt(_catalogoBarato.length);
    }
    return _catalogoBarato.length + aleatorio.nextInt(_catalogoCaro.length);
  }

  // Reparto por hora sesgado al mediodía, para que los tres turnos tengan
  // datos representativos. Sembrar todo a la misma hora dejaba dos turnos en
  // cero y hacía inútil la medición por turno.
  int horaConPicoAlMediodia() {
    const pesos = [
      // 6  7  8  9 10 11 12 13 14 15 16 17 18 19
      3, 5, 6, 5, 4, 8, 14, 13, 7, 4, 4, 5, 6, 4,
    ];
    final total = pesos.reduce((a, b) => a + b);
    var tirada = aleatorio.nextInt(total);
    for (var i = 0; i < pesos.length; i++) {
      tirada -= pesos[i];
      if (tirada < 0) return 6 + i;
    }
    return 12;
  }

  final inicio = DateTime(2020, 1, 1);
  var totalSembrado = 0.0;
  var ventasHechas = 0;
  const ventasPorLote = 5000;

  while (ventasHechas < nivel.ventas) {
    final enEsteLote = min(ventasPorLote, nivel.ventas - ventasHechas);
    await db.transaction((txn) async {
      for (var i = 0; i < enEsteLote; i++) {
        final indiceGlobal = ventasHechas + i;
        final dia = indiceGlobal ~/ nivel.ventasPorDia;
        final fecha = inicio.add(Duration(days: dia)).copyWith(
              hour: horaConPicoAlMediodia(),
              minute: aleatorio.nextInt(60),
              second: aleatorio.nextInt(60),
            );
        final ventaId = 'v-$indiceGlobal';
        await txn.insert('venta', {
          'id': ventaId,
          'fecha_hora': fecha.toIso8601String(),
          'detalle': null,
          'estado': 'activa',
          'motivo_reversion': null,
          'updated_at': fecha.toIso8601String(),
        });
        for (var l = 0; l < 2; l++) {
          final idx = indiceProductoSesgado();
          final precio = catalogo[idx].$2;
          final cantidad = aleatorio.nextInt(2) + 1;
          totalSembrado += precio * cantidad;
          await txn.insert('linea_venta', {
            'id': 'l-$indiceGlobal-$l',
            'venta_id': ventaId,
            'producto_id': productoIds[idx],
            'nombre_libre': null,
            'precio_aplicado': precio,
            'cantidad': cantidad,
            'nota': null,
            'updated_at': fecha.toIso8601String(),
          });
        }
      }
    });
    ventasHechas += enEsteLote;
    if (nivel.filas > 1000000 && ventasHechas % 100000 == 0) {
      avisar('    ${ventasHechas ~/ 1000}k/${nivel.ventas ~/ 1000}k ventas');
    }
  }

  return totalSembrado;
}

/// Mide cuánto tarda [accion] y devuelve el par (resultado, duración).
Future<(T, Duration)> medir<T>(Future<T> Function() accion) async {
  final reloj = Stopwatch()..start();
  final resultado = await accion();
  reloj.stop();
  return (resultado, reloj.elapsed);
}

String ms(Duration d) => '${d.inMilliseconds} ms';

/// RSS del proceso, para detectar picos de memoria (por ejemplo el de 3× que se
/// espera en el backup).
int rssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);
