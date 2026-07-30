import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/import_export/tiketback_service.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// El backup con el modelo de libros ([decisión 0025](../docs/decisiones/0025-archivado-anual-rodante.md)).
///
/// Estas pruebas usan bases SQLite de verdad, no archivos de texto como antes:
/// desde que restaurar sabe distinguir catálogo de ventas, tiene que abrir y
/// consultar los archivos, y un fixture de mentira no ejercitaría nada de eso.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late String rutaPrincipal;
  late String rutaBackup;

  const nombrePrincipal = 'vulp_tiketing.db';

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'orden_producto': 'precio',
      'acento_tinte': 'grisVerdoso',
    });
    dir = await Directory.systemTemp.createTemp('tiketback_test_');
    rutaPrincipal = p.join(dir.path, nombrePrincipal);
    rutaBackup = p.join(dir.path, 'respaldo.tiketback');
  });

  tearDown(() async {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<Database> abrirPrincipal() => databaseFactory.openDatabase(
        rutaPrincipal,
        options: OpenDatabaseOptions(singleInstance: false),
      );

  /// Monta la topología real: base principal con catálogo e índice, más un
  /// archivo por libro con sus ventas dentro.
  Future<List<String>> sembrar({
    required List<String> productos,
    required Map<String, double> ventasPorLibro,
  }) async {
    final db = await abrirPrincipal();
    await AppDatabase.crearEsquema(db);
    await db.insert('categoria', {
      'id': 'cat',
      'nombre': 'General',
      'updated_at': DateTime(2026).toIso8601String(),
    });
    for (final nombre in productos) {
      await db.insert('producto', {
        'id': 'prod-$nombre',
        'nombre': nombre,
        'categoria_id': 'cat',
        'precio_base': 1000.0,
        'updated_at': DateTime(2026).toIso8601String(),
      });
    }

    final archivos = <String>[];
    var i = 0;
    for (final entrada in ventasPorLibro.entries) {
      final archivo = entrada.key;
      archivos.add(archivo);
      final libro = await databaseFactory.openDatabase(
        p.join(dir.path, archivo),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await aplicarEsquemaLibro(libro);
      final fecha = DateTime(2026, 1, 1 + i).toIso8601String();
      await libro.insert('venta', {
        'id': 'v-$archivo',
        'fecha_hora': fecha,
        'estado': 'activa',
        'updated_at': fecha,
      });
      await libro.insert('linea_venta', {
        'id': 'l-$archivo',
        'venta_id': 'v-$archivo',
        'nombre_libre': 'algo',
        'precio_aplicado': entrada.value,
        'cantidad': 1,
        'updated_at': fecha,
      });
      await libro.close();

      await db.insert('libro_ventas', {
        'id': 'libro-$i',
        'archivo': archivo,
        'fecha_inicio': DateTime(2026, 1, 1 + i).toIso8601String(),
        'fecha_fin': null,
        'dias_con_ventas': 1,
        'ultimo_dia': DateTime(2026, 1, 1 + i).toIso8601String(),
        'cerrado': i < ventasPorLibro.length - 1 ? 1 : 0,
      });
      i++;
    }
    await db.close();
    return archivos;
  }

  /// Suma de todas las ventas, recorriendo los libros que el índice declara.
  Future<double> totalVendido() async {
    final db = await abrirPrincipal();
    final libros = await db.query('libro_ventas', columns: ['archivo']);
    await db.close();

    var total = 0.0;
    for (final fila in libros) {
      final ruta = p.join(dir.path, fila['archivo'] as String);
      if (!File(ruta).existsSync()) continue;
      final libro = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final r = await libro.rawQuery(
        'SELECT SUM(precio_aplicado * cantidad) t FROM linea_venta',
      );
      await libro.close();
      total += (r.first['t'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  Future<List<String>> nombresDeProducto() async {
    final db = await abrirPrincipal();
    final filas = await db.query('producto', columns: ['nombre'], orderBy: 'nombre');
    await db.close();
    return filas.map((f) => f['nombre'] as String).toList();
  }

  Future<void> exportar(List<String> libros, {String clave = 'clave-correcta'}) {
    return TiketbackService().exportar(
      contrasenaExportacion: clave,
      directorioDatos: dir.path,
      nombreBasePrincipal: nombrePrincipal,
      archivosDeLibro: libros,
      rutaDestino: rutaBackup,
    );
  }

  Future<void> restaurar(AlcanceRestauracion alcance, {String clave = 'clave-correcta'}) {
    return TiketbackService().restaurar(
      contrasenaExportacion: clave,
      directorioDatos: dir.path,
      nombreBasePrincipal: nombrePrincipal,
      rutaOrigen: rutaBackup,
      alcance: alcance,
    );
  }

  test('el backup incluye los libros y las ventas vuelven con el', () async {
    // Este es EL fallo que la 0025 dejó abierto: antes el backup copiaba solo
    // `vulp_tiketing.db` y no contenía una sola venta. Nadie se enteraba hasta
    // el día que necesitaba el respaldo.
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01_2026-06-30.db': 5000, 'ventas-2026-07-01.db': 3000},
    );
    await exportar(libros);

    // Desastre total: se borra todo.
    for (final entrada in dir.listSync()) {
      if (entrada.path != rutaBackup) entrada.deleteSync();
    }

    await restaurar(AlcanceRestauracion.todo);

    expect(await totalVendido(), closeTo(8000, 0.01));
    expect(await nombresDeProducto(), equals(['Café']));
    for (final archivo in libros) {
      expect(File(p.join(dir.path, archivo)).existsSync(), isTrue,
          reason: '$archivo tiene que volver del backup');
    }
  });

  test('restaurar solo el menu no mueve las ventas', () async {
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    await exportar(libros);

    // Después del backup: cambia el menú y se venden ₡2.000 más.
    final db = await abrirPrincipal();
    await db.delete('producto');
    await db.insert('producto', {
      'id': 'prod-nuevo',
      'nombre': 'Horchata',
      'categoria_id': 'cat',
      'precio_base': 900.0,
      'updated_at': DateTime(2026, 8).toIso8601String(),
    });
    await db.close();

    final libro = await databaseFactory.openDatabase(
      p.join(dir.path, 'ventas-2026-01-01.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await libro.insert('venta', {
      'id': 'v-posterior', 'fecha_hora': '2026-08-01T10:00:00.000',
      'estado': 'activa', 'updated_at': '2026-08-01T10:00:00.000',
    });
    await libro.insert('linea_venta', {
      'id': 'l-posterior', 'venta_id': 'v-posterior', 'nombre_libre': 'x',
      'precio_aplicado': 2000.0, 'cantidad': 1, 'updated_at': '2026-08-01T10:00:00.000',
    });
    await libro.close();

    await restaurar(AlcanceRestauracion.soloMenu);

    expect(await nombresDeProducto(), equals(['Café']), reason: 'el menú vuelve al del backup');
    expect(await totalVendido(), closeTo(7000, 0.01),
        reason: 'las ventas posteriores al backup NO pueden desaparecer');
  });

  test('restaurar solo las ventas no toca el menu', () async {
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    await exportar(libros);

    final db = await abrirPrincipal();
    await db.insert('producto', {
      'id': 'prod-nuevo',
      'nombre': 'Horchata',
      'categoria_id': 'cat',
      'precio_base': 900.0,
      'updated_at': DateTime(2026, 8).toIso8601String(),
    });
    await db.close();
    File(p.join(dir.path, 'ventas-2026-01-01.db')).deleteSync();

    await restaurar(AlcanceRestauracion.soloVentas);

    expect(await totalVendido(), closeTo(5000, 0.01), reason: 'las ventas vuelven');
    expect(await nombresDeProducto(), equals(['Café', 'Horchata']),
        reason: 'el producto agregado después del backup tiene que sobrevivir');
  });

  test('restaurar todo borra los libros que el backup no traia', () async {
    // Un libro huérfano en la carpeta seguiría sumando en los reportes si
    // alguna vez volviera a entrar al índice. El índice manda.
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    await exportar(libros);

    final intruso = File(p.join(dir.path, 'ventas-2030-01-01.db'));
    await intruso.writeAsString('libro que no estaba en el backup');

    await restaurar(AlcanceRestauracion.todo);

    expect(intruso.existsSync(), isFalse);
  });

  test('un backup del formato viejo, sin libros, todavia se restaura', () async {
    // Formato 1: [u32 largo][db][u32 largo][prefs], sin magic. Se generó cuando
    // las ventas vivían dentro de la base principal; abrirlo tiene que seguir
    // funcionando, y la migración a v3 se encarga del resto al abrir la app.
    final db = await abrirPrincipal();
    await AppDatabase.crearEsquema(db);
    await aplicarEsquemaLibro(db); // como era una base v2
    await db.close();

    final bytesV2 = await File(rutaPrincipal).readAsBytes();
    await File(rutaBackup).writeAsBytes(
      await _cifrarFormato1(bytesV2, utf8.encode('{"orden_producto":"nombre"}')),
      flush: true,
    );
    await File(rutaPrincipal).delete();

    await restaurar(AlcanceRestauracion.todo);

    expect(File(rutaPrincipal).existsSync(), isTrue);
    expect(await File(rutaPrincipal).readAsBytes(), equals(bytesV2));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('orden_producto'), 'nombre');
  });

  test('un backup en formato 2, con libros, todavia se restaura', () async {
    // v2 ya traía libros, pero cifraba TODO como un solo bloque y guardaba el
    // magic DENTRO del cifrado. Un lector que busque el magic en los primeros
    // bytes del archivo ve la sal aleatoria y lo confunde con v1.
    //
    // Esta prueba faltaba y el fallo salió recién probando en la app real:
    // ningún caso cubría "escribir con un formato y leer con el siguiente".
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    final bytesPrincipal = await File(rutaPrincipal).readAsBytes();
    final bytesLibro =
        await File(p.join(dir.path, 'ventas-2026-01-01.db')).readAsBytes();

    await File(rutaBackup).writeAsBytes(
      await _cifrarFormato2(
        nombrePrincipal: nombrePrincipal,
        principal: bytesPrincipal,
        libros: {libros.first: bytesLibro},
        prefs: utf8.encode('{"acento_tinte":"cobre"}'),
      ),
      flush: true,
    );

    for (final entrada in dir.listSync()) {
      if (entrada.path != rutaBackup) entrada.deleteSync();
    }

    await restaurar(AlcanceRestauracion.todo);

    expect(await totalVendido(), closeTo(5000, 0.01));
    expect(await nombresDeProducto(), equals(['Café']));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('acento_tinte'), 'cobre');
  });

  test('la contrasena equivocada no escribe nada', () async {
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    await exportar(libros);
    File(p.join(dir.path, 'ventas-2026-01-01.db')).deleteSync();

    await expectLater(
      restaurar(AlcanceRestauracion.todo, clave: 'clave-incorrecta'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );

    expect(File(p.join(dir.path, 'ventas-2026-01-01.db')).existsSync(), isFalse,
        reason: 'una contraseña mala no puede dejar el dispositivo a medio restaurar');
  });

  test('un backup cortado por la mitad no restaura nada', () async {
    // El riesgo que aparece al partir el backup en marcos: si cada marco lleva
    // su propio sello y nada mas, cortar el archivo da un backup donde TODOS
    // los marcos que quedan verifican bien. Restaurarías medio año de ventas
    // creyendo que están todas, sin ningún aviso.
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    await exportar(libros);

    final entero = await File(rutaBackup).readAsBytes();
    await File(rutaBackup).writeAsBytes(
      entero.sublist(0, entero.length ~/ 2),
      flush: true,
    );

    await expectLater(restaurar(AlcanceRestauracion.todo), throwsA(anything));

    // Y lo que había sigue en su lugar, no a medio reemplazar.
    expect(await totalVendido(), closeTo(5000, 0.01));
    expect(await nombresDeProducto(), equals(['Café']));
  });

  test('un backup con los marcos alterados no restaura nada', () async {
    // El otro riesgo del troceado: mover o tocar un marco. Sin el número de
    // marco dentro de lo que el sello protege, cada pieza seguiría verificando
    // por separado y la contabilidad restaurada quedaría mezclada, con el
    // archivo pareciendo íntegro.
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    await exportar(libros);

    final bytes = await File(rutaBackup).readAsBytes();
    // Un byte del último marco, bien lejos de la cabecera.
    bytes[bytes.length - 40] ^= 0xFF;
    await File(rutaBackup).writeAsBytes(bytes, flush: true);

    await expectLater(restaurar(AlcanceRestauracion.todo), throwsA(anything));
    expect(await totalVendido(), closeTo(5000, 0.01));
  });

  test('restaurar no deja carpeta de paso ni cuando falla', () async {
    final libros = await sembrar(
      productos: ['Café'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    await exportar(libros);

    await restaurar(AlcanceRestauracion.todo);
    expect(Directory(p.join(dir.path, '.restaurando')).existsSync(), isFalse);

    await expectLater(
      restaurar(AlcanceRestauracion.todo, clave: 'mala'),
      throwsA(anything),
    );
    expect(Directory(p.join(dir.path, '.restaurando')).existsSync(), isFalse,
        reason: 'una carpeta de paso huérfana ocuparía el doble de disco '
            'y confundiría al siguiente intento');
  });

  test('el backup no deja el contenido en claro', () async {
    final libros = await sembrar(
      productos: ['Marcador-Legible'],
      ventasPorLibro: {'ventas-2026-01-01.db': 5000},
    );
    await exportar(libros);

    final crudo = await File(rutaBackup).readAsBytes();
    expect(
      utf8.decode(crudo, allowMalformed: true).contains('Marcador-Legible'),
      isFalse,
    );
  });
}

/// Reproduce el formato 2: magic + version + manifiesto + piezas, todo cifrado
/// como un solo bloque. Es como escribía la app entre la 0025 y el troceado.
Future<List<int>> _cifrarFormato2({
  required String nombrePrincipal,
  required List<int> principal,
  required Map<String, List<int>> libros,
  required List<int> prefs,
}) async {
  final manifiesto = utf8.encode(jsonEncode([
    {'tipo': 'principal', 'nombre': nombrePrincipal, 'largo': principal.length},
    for (final e in libros.entries)
      {'tipo': 'libro', 'nombre': e.key, 'largo': e.value.length},
    {'tipo': 'preferencias', 'nombre': '', 'largo': prefs.length},
  ]));

  final bundle = BytesBuilder()
    ..add(utf8.encode('VTBK'))
    ..add((ByteData(2)..setUint16(0, 2, Endian.big)).buffer.asUint8List())
    ..add(_u32(manifiesto.length))
    ..add(manifiesto)
    ..add(principal);
  for (final bytes in libros.values) {
    bundle.add(bytes);
  }
  bundle.add(prefs);

  return _envolver(bundle.takeBytes());
}

/// Reproduce el formato 1 tal como lo escribía la app antes de la 0025.
Future<List<int>> _cifrarFormato1(List<int> db, List<int> prefs) {
  final bundle = BytesBuilder()
    ..add(_u32(db.length))
    ..add(db)
    ..add(_u32(prefs.length))
    ..add(prefs);
  return _envolver(bundle.takeBytes());
}

/// La envoltura común de los formatos 1 y 2: `salt|nonce|cipherText|mac`, con
/// TODO el bundle cifrado de una vez.
Future<List<int>> _envolver(List<int> bundle) async {
  final clave = await Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  ).deriveKeyFromPassword(
    password: 'clave-correcta',
    nonce: List<int>.generate(16, (i) => i),
  );

  final caja = await AesGcm.with256bits().encrypt(
    bundle,
    secretKey: clave,
    nonce: List<int>.generate(12, (i) => i),
  );

  return (BytesBuilder()
        ..add(List<int>.generate(16, (i) => i))
        ..add(caja.nonce)
        ..add(caja.cipherText)
        ..add(caja.mac.bytes))
      .takeBytes();
}

List<int> _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();
