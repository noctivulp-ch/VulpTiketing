import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/caja/corte_caja_dao.dart';
import 'package:vulp_tiketing/features/caja/corte_caja_model.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Los cortes de caja, con el flujo real de la soda como referencia:
///
/// 1. Antes de abrir se anota el monto con el que arranca la caja.
/// 2. A media jornada se cuenta, se guarda la mayor parte del efectivo y se
///    deja una cantidad para vueltos.
/// 3. Al cerrar se cuenta otra vez.
///
/// De ahí las dos cosas que estas pruebas vigilan, porque son las que hacen que
/// el número sirva para contar la caja:
///
/// - **El efectivo se cuenta desde el último corte**, no desde que abrió el día.
///   Si contara el día entero, después de guardar la plata del cambio de turno
///   el esperado quedaría por encima de lo que hay en el cajón para siempre.
/// - **El SINPE no entra.** Una transferencia no cae en la caja, así que sumarla
///   daría un esperado que no puede coincidir con ningún conteo.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final hoy = DateTime(2026, 8, 10);

  Future<Database> abrirDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    // Las ventas viven en los libros (0025); acá se aplican sobre la misma base
    // en memoria, que es donde SQLite las resuelve igual que en producción.
    await aplicarEsquemaLibro(db);
    return db;
  }

  Future<void> sembrarVenta(
    Database db,
    int hora,
    double monto, {
    String metodo = 'efectivo',
  }) async {
    final fecha = DateTime(hoy.year, hoy.month, hoy.day, hora, 30);
    final id = 'v-$hora-${monto.toInt()}-$metodo';
    await db.insert('venta', {
      'id': id,
      'fecha_hora': fecha.toIso8601String(),
      'estado': 'activa',
      'metodo_pago': metodo,
      'updated_at': fecha.toIso8601String(),
    });
    await db.insert('linea_venta', {
      'id': 'l-$id',
      'venta_id': id,
      'nombre_libre': 'algo',
      'precio_aplicado': monto,
      'cantidad': 1,
      'updated_at': fecha.toIso8601String(),
    });
  }

  Future<void> anotar(Database db, MomentoCorte momento, double monto, int hora) {
    final cuando = DateTime(hoy.year, hoy.month, hoy.day, hora);
    return CorteCajaDao(db).insertar(
      CorteCaja(
        id: 'c-${momento.name}',
        dia: diaDe(hoy),
        momento: momento,
        monto: monto,
        fechaHora: cuando,
        updatedAt: cuando,
      ),
    );
  }

  group('el orden lo manda el corte anterior, no el reloj', () {
    test('sin nada anotado, toca la apertura', () {
      expect(siguienteMomento(const {}), MomentoCorte.apertura);
    });

    test('con la apertura hecha, toca el medio día', () {
      expect(siguienteMomento({MomentoCorte.apertura}), MomentoCorte.medioDia);
    });

    test('con apertura y medio día, toca el cierre', () {
      expect(siguienteMomento({MomentoCorte.apertura, MomentoCorte.medioDia}), MomentoCorte.cierre);
    });

    test('con los tres, ya no toca ninguno', () {
      expect(siguienteMomento(MomentoCorte.values.toSet()), isNull);
    });

    test('no se puede saltar la apertura', () {
      // El cambio de turno cae entre las 12 y las 2:30 según el día, así que la
      // regla NO puede ser horaria. Lo que habilita el medio día es tener la
      // apertura anotada — y sin ella, lo que toca sigue siendo la apertura por
      // muy tarde que sea.
      expect(siguienteMomento({MomentoCorte.medioDia}), MomentoCorte.apertura);
      expect(siguienteMomento({MomentoCorte.cierre}), MomentoCorte.apertura);
    });
  });

  group('la caja esperada', () {
    test('sin cortes, es todo el efectivo del día', () async {
      final db = await abrirDb();
      await sembrarVenta(db, 9, 3000);
      await sembrarVenta(db, 10, 2000);

      final dao = CorteCajaDao(db);
      expect(await dao.efectivoEntre(hoy, hoy.add(const Duration(days: 1))), 5000);
      await db.close();
    });

    test('el SINPE no cuenta: no cae en el cajón', () async {
      final db = await abrirDb();
      await sembrarVenta(db, 9, 3000);
      await sembrarVenta(db, 10, 7000, metodo: 'sinpe');

      final dao = CorteCajaDao(db);
      expect(await dao.efectivoEntre(hoy, hoy.add(const Duration(days: 1))), 3000);
      await db.close();
    });

    test('tras el corte de medio día solo cuenta lo cobrado después', () async {
      // El caso que define la función. Mañana: 40 000 en efectivo. A las 13:00
      // se cuenta, se guardan 35 000 y quedan 15 000 para vueltos. Por la tarde
      // entran 20 000 más.
      //
      // Lo esperado en el cajón es 15 000 + 20 000 = 35 000. Si se contara el
      // día entero saldría 75 000, y el cajón nunca podría cuadrar con eso.
      final db = await abrirDb();
      await sembrarVenta(db, 9, 40000);
      await anotar(db, MomentoCorte.apertura, 20000, 7);
      await anotar(db, MomentoCorte.medioDia, 15000, 13);
      await sembrarVenta(db, 16, 20000);

      final dao = CorteCajaDao(db);
      final cortes = await dao.listarDelDia(diaDe(hoy));
      final ultimo = cortes.last;

      expect(ultimo.momento, MomentoCorte.medioDia);
      expect(ultimo.monto, 15000, reason: 'lo que QUEDA, no lo que se contó');

      final efectivo = await dao.efectivoEntre(ultimo.fechaHora, hoy.add(const Duration(days: 1)));
      expect(efectivo, 20000, reason: 'la mañana ya se guardó');
      expect(ultimo.monto + efectivo, 35000);
      await db.close();
    });

    test('una venta revertida no infla el esperado', () async {
      // Si contara las revertidas, el cajón saldría corto y parecería un
      // faltante de dinero.
      final db = await abrirDb();
      await sembrarVenta(db, 9, 3000);
      await db.update(
        'venta',
        {'estado': 'revertida'},
        where: 'id = ?',
        whereArgs: ['v-9-3000-efectivo'],
      );

      final dao = CorteCajaDao(db);
      expect(await dao.efectivoEntre(hoy, hoy.add(const Duration(days: 1))), 0);
      await db.close();
    });
  });

  test('los cortes se leen en orden y solo los del día pedido', () async {
    final db = await abrirDb();
    await anotar(db, MomentoCorte.medioDia, 15000, 13);
    await anotar(db, MomentoCorte.apertura, 20000, 7);
    await CorteCajaDao(db).insertar(
      CorteCaja(
        id: 'c-ayer',
        dia: '2026-08-09',
        momento: MomentoCorte.cierre,
        monto: 999,
        fechaHora: DateTime(2026, 8, 9, 21),
        updatedAt: DateTime(2026, 8, 9, 21),
      ),
    );

    final cortes = await CorteCajaDao(db).listarDelDia(diaDe(hoy));

    expect(cortes.map((c) => c.momento), [MomentoCorte.apertura, MomentoCorte.medioDia]);
    await db.close();
  });

  group('rehacer el último corte', () {
    test('cambia el monto sin duplicar la fila ni mover su hora', () async {
      // El caso real que lo motivó: un cierre anotado con un 5 y quince ceros.
      // Sin corrección, el día quedaba en ₡5 000 000 000 000 000 y no había
      // salida desde la app.
      final db = await abrirDb();
      await anotar(db, MomentoCorte.apertura, 5000000000000000, 7);

      final dao = CorteCajaDao(db);
      final antes = (await dao.listarDelDia(diaDe(hoy))).single;
      await dao.corregirMonto(antes.id, 20000, DateTime(2026, 8, 10, 7, 2));

      final despues = await dao.listarDelDia(diaDe(hoy));
      expect(despues, hasLength(1), reason: 'corregir no crea un corte nuevo');
      expect(despues.single.monto, 20000);
      expect(despues.single.id, antes.id, reason: 'el mismo id, o el otro teléfono vería dos');
      expect(
        despues.single.fechaHora,
        antes.fechaHora,
        reason: 'la hora es la frontera del tramo: moverla saca ventas que sí ocurrieron dentro',
      );
      await db.close();
    });

    test('el updated_at sí avanza, para que la corrección gane el LWW', () async {
      // Si no avanzara, el otro teléfono tendría el monto viejo con la misma
      // marca de tiempo y la corrección no viajaría — o peor, volvería el
      // número equivocado en la ronda siguiente.
      final db = await abrirDb();
      await anotar(db, MomentoCorte.apertura, 999, 7);

      final dao = CorteCajaDao(db);
      final antes = (await dao.listarDelDia(diaDe(hoy))).single;
      final corregido = DateTime(2026, 8, 10, 7, 2);
      await dao.corregirMonto(antes.id, 20000, corregido);

      expect((await dao.listarDelDia(diaDe(hoy))).single.updatedAt, corregido);
      expect(corregido.isAfter(antes.updatedAt), isTrue);
      await db.close();
    });

    test('corregir el último no cambia qué corte toca', () async {
      // Rehacer la apertura no puede hacer que "toque" la apertura otra vez: el
      // día sigue en el mismo punto.
      final db = await abrirDb();
      await anotar(db, MomentoCorte.apertura, 999, 7);

      final dao = CorteCajaDao(db);
      final corte = (await dao.listarDelDia(diaDe(hoy))).single;
      await dao.corregirMonto(corte.id, 20000, DateTime(2026, 8, 10, 7, 2));

      final momentos = (await dao.listarDelDia(diaDe(hoy))).map((c) => c.momento).toSet();
      expect(siguienteMomento(momentos), MomentoCorte.medioDia);
      await db.close();
    });

    test('con el día cerrado sigue habiendo un último que corregir', () async {
      // Es justo el estado en que apareció el problema: los tres anotados, nada
      // que "toque", y un número imposible en pantalla.
      final db = await abrirDb();
      await anotar(db, MomentoCorte.apertura, 20000, 7);
      await anotar(db, MomentoCorte.medioDia, 15000, 13);
      await anotar(db, MomentoCorte.cierre, 5000000000000000, 21);

      final cortes = await CorteCajaDao(db).listarDelDia(diaDe(hoy));
      expect(siguienteMomento(cortes.map((c) => c.momento).toSet()), isNull);
      expect(cortes.last.momento, MomentoCorte.cierre, reason: 'el cierre es el corregible');
      await db.close();
    });
  });

  test('la clave de día lleva ceros: se compara como texto', () async {
    // `dia` se compara con `=` en SQL, así que "2026-8-9" y "2026-08-09" serían
    // dos días distintos y los cortes del 9 no aparecerían.
    expect(diaDe(DateTime(2026, 8, 9)), '2026-08-09');
    expect(diaDe(DateTime(2026, 12, 31)), '2026-12-31');
  });
}
