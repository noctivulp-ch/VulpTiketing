// Siembra compartida por el banco y por los experimentos: los dos tienen que
// medir sobre EXACTAMENTE el mismo volumen, o sus números no se pueden
// comparar entre sí.
//
// Un año de una soda pequeña, no una base de demostración: con pocos datos
// todo es rápido y no se ve ningún cuello.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Volumen de la siembra. Un año de una soda pequeña.
const _productos = 120;
const _ventasPorDia = 60;
const _diasConVentas = 180;

/// Deja la base lista: libro de ventas abierto y volumen sembrado.
///
/// En una instalación virgen todavía no existe ningún libro, y
/// `AppDatabase.open()` solo adjunta el que YA está abierto: sin esto se muere
/// con "no such table: venta". `prepararPara` es el mismo camino que usa la app
/// al cobrar la primera venta del día.
Future<Database> prepararBaseDePruebas() async {
  final db = await AppDatabase.open();
  final libros = LibroVentasService(directorio: p.dirname(await AppDatabase.ruta()));
  await libros.prepararPara(db, DateTime.now());
  await _sembrar(db);
  return db;
}

Future<void> _sembrar(Database db) async {
  final yaSembrado = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM producto'));
  if ((yaSembrado ?? 0) >= _productos) {
    // ignore: avoid_print
    print('BANCO\tsiembra\tya estaba\t$yaSembrado');
    return;
  }

  final reloj = Stopwatch()..start();
  final ahora = DateTime.now();
  await db.transaction((txn) async {
    await txn.insert('categoria', {
      'id': 'cat-banco',
      'nombre': 'Banco',
      'updated_at': ahora.toIso8601String(),
    });
    for (var i = 0; i < _productos; i++) {
      await txn.insert('producto', {
        'id': 'pb$i',
        'nombre': 'Café con leche variante $i',
        'categoria_id': 'cat-banco',
        'precio_base': 500.0 + (i % 20) * 250,
        'updated_at': ahora.toIso8601String(),
      });
    }
  });

  // Las ventas van en el libro abierto, que es donde viven de verdad (0025).
  var venta = 0;
  for (var dia = 0; dia < _diasConVentas; dia++) {
    final fecha = ahora.subtract(Duration(days: dia));
    await db.transaction((txn) async {
      for (var v = 0; v < _ventasPorDia; v++) {
        final id = 'vb${venta++}';
        final momento = DateTime(
          fecha.year,
          fecha.month,
          fecha.day,
          6 + (v % 16),
          v % 60,
        ).toIso8601String();
        await txn.insert('venta', {
          'id': id,
          'fecha_hora': momento,
          'estado': 'activa',
          'updated_at': momento,
        });
        for (var l = 0; l < 3; l++) {
          await txn.insert('linea_venta', {
            'id': '$id-$l',
            'venta_id': id,
            'producto_id': 'pb${(v * 3 + l) % _productos}',
            'precio_aplicado': 500.0 + (l % 20) * 250,
            'cantidad': 1 + (l % 3),
            'updated_at': momento,
          });
        }
      }
    });
  }
  reloj.stop();
  // ignore: avoid_print
  print('BANCO\tsiembra\t$venta ventas\t${reloj.elapsedMilliseconds}');
}
