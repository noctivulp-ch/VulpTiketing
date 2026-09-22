import 'dart:io';

import 'package:path/path.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../features/venta/libro_ventas.dart';

/// Esquema completo en docs/arquitectura/esquema-db.md — cualquier cambio de
/// columna se hace ahi primero, no directo aqui.
class AppDatabase {
  AppDatabase._();

  static Database? _instance;

  /// La apertura en curso, para que N lectores concurrentes compartan UNA.
  ///
  /// `open()` tenía un `await` entre comprobar `_instance` y asignarlo, así que
  /// dos llamadas simultáneas pasaban las dos el chequeo de null. Y como
  /// sqflite abre en modo `singleInstance` por defecto, las dos recibían LA
  /// MISMA conexión y las dos le adjuntaban el libro: la segunda moría con
  /// `database libro is already in use` y dejaba la app sin poder consultar
  /// ventas en ninguna pantalla.
  ///
  /// Es fácil de disparar: al entrar, el Dashboard monta las cinco pantallas de
  /// una y ocho providers distintos piden la base en el mismo frame.
  static Future<Database>? _aperturaEnCurso;

  /// Ruta del archivo fisico — usada por TiketbackService para
  /// leer/reemplazar el archivo directo en exportar/restaurar (0006).
  static Future<String> ruta() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, 'vulp_tiketing.db');
  }

  /// Cierra la conexion activa, si hay una. Necesario antes de reemplazar
  /// el archivo fisico al restaurar un .tiketback — sqflite no permite
  /// sobreescribir un archivo con una conexion abierta de forma segura.
  static Future<void> close() async {
    _aperturaEnCurso = null;
    final db = _instance;
    _instance = null;
    if (db == null) return;
    // Soltar el libro ANTES de cerrar: si la conexión sobreviviera al cierre
    // —sqflite la comparte entre aperturas del mismo archivo— volvería con el
    // alias todavía tomado y el siguiente ATTACH fallaría.
    await LibroVentasService(directorio: p.dirname(await ruta())).desadjuntar(db);
    await db.close();
  }

  /// Deja `databaseFactory` utilizable en esta plataforma.
  ///
  /// Es publico y separado de [open] porque hay codigo que abre bases SIN pasar
  /// por la conexion principal: `TiketbackService` abre el archivo restaurado y
  /// un temporal, y `LibroVentasService` abre cada libro para crearle su
  /// esquema. Cuando esto vivia solo dentro de [open], restaurar un backup en
  /// una app recien abierta —antes de que nadie hubiera tocado la base— moria
  /// con `databaseFactory not initialized`.
  ///
  /// Idempotente: llamarlo de mas no cuesta nada.
  static void inicializarFactory() {
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  /// Comparte una sola apertura entre todos los que la pidan a la vez.
  static Future<Database> open() async {
    final abierta = _instance;
    if (abierta != null) return abierta;

    final enCurso = _aperturaEnCurso ??= _abrir();
    try {
      return await enCurso;
    } finally {
      // Se limpia pase lo que pase: si la apertura falló, el siguiente intento
      // tiene que poder reintentar en vez de quedarse pegado a un futuro roto.
      if (identical(_aperturaEnCurso, enCurso)) _aperturaEnCurso = null;
    }
  }

  static Future<Database> _abrir() async {
    inicializarFactory();

    final db = await openDatabase(
      await ruta(),
      version: version,
      onCreate: (db, version) => crearEsquema(db),
      onUpgrade: (db, viejo, nuevo) async {
        // v1 -> v2: solo agrega indices. No toca columnas ni datos, asi que es
        // segura de aplicar sobre una base existente y no necesita migrar
        // filas.
        if (viejo < 2) await crearIndicesLegacyV2(db);

        // v2 -> v3: las ventas se mudan de la base principal a su primer libro
        // (decision 0025). Es la UNICA vez que se mueven datos: de aca en
        // adelante las ventas nacen ya en su libro.
        if (viejo < 3) {
          await migrarVentasALibro(db, p.dirname(await ruta()));
        }

        // v3 -> v4: la categoria puede llevar su icono elegido a mano. La
        // columna es NULLABLE y sin DEFAULT a proposito: `NULL` significa "el
        // que salga del nombre", que es lo que hacian todas hasta ahora, asi
        // que las filas existentes quedan exactamente como estaban sin tener
        // que reescribir ninguna.
        if (viejo < 4) await agregarIconoDeCategoria(db);

        // v4 -> v5: los cortes de caja. Tabla nueva y vacia: no hay nada que
        // migrar, y una base sin cortes se comporta como el dia en que todavia
        // no se ha anotado la apertura.
        if (viejo < 5) await crearCorteCaja(db);

        // v5 -> v6: las variantes de un producto, como JSON en su fila
        // (decision 0039). Nullable y sin DEFAULT como el icono: NULL es "sin
        // variantes", que es lo que eran todos hasta ahora.
        if (viejo < 6) await agregarVariantesDeProducto(db);

        // v6 -> v7: las tablas del costeo (decision 0040). Nuevas y vacias:
        // no hay nada que migrar. Se sincronizan como el catalogo.
        if (viejo < 7) await crearTablasDeCosteo(db);

        // v7 -> v8: impuestos y comisiones por medio (decision 0042).
        if (viejo < 8) await agregarImpuestos(db);

        // v8 -> v9: tipo de negocio (produccion / servicios), punto 6 de la idea 5.
        if (viejo < 9) await agregarTipoDeNegocio(db);
      },
    );

    // El libro abierto se adjunta aca: desde este momento `SELECT * FROM venta`
    // resuelve contra el, sin que el resto del codigo tenga que calificar nada.
    await LibroVentasService(directorio: p.dirname(await ruta())).adjuntarAbierto(db);

    // `_instance` se asigna al FINAL, con la base ya usable. Asignarla antes
    // dejaba una ventana donde otro lector se la llevaba a medio preparar, sin
    // el libro adjunto.
    _instance = db;
    return db;
  }

  static const version = 9;

  /// v8 -> v9. `config_costeo.tipo_negocio`: 'produccion' (de fabrica) o
  /// 'servicios', donde una receta vacia es lo normal y no un olvido.
  static Future<void> agregarTipoDeNegocio(DatabaseExecutor db) async {
    final columnas = await db.rawQuery('PRAGMA table_info(config_costeo)');
    if (columnas.any((c) => c['name'] == 'tipo_negocio')) return;
    await db.execute("ALTER TABLE config_costeo ADD COLUMN tipo_negocio TEXT NOT NULL DEFAULT 'produccion'");
  }

  /// v7 -> v8: impuestos y comisiones por medio (decision 0042). `producto`
  /// gana `tasa_iva` (NULL = la tasa por defecto de Ajustes) y
  /// `config_costeo` gana el regimen, sus factores y una comision por medio
  /// de pago. La comision unica de antes se copia a la de SINPE: era lo que
  /// significaba en la practica (efectivo no cobra comision).
  static Future<void> agregarImpuestos(DatabaseExecutor db) async {
    Future<void> columna(String tabla, String nombre, String ddl) async {
      final columnas = await db.rawQuery('PRAGMA table_info($tabla)');
      if (columnas.any((c) => c['name'] == nombre)) return;
      await db.execute('ALTER TABLE $tabla ADD COLUMN $ddl');
    }

    await columna('producto', 'tasa_iva', 'tasa_iva REAL');
    await columna('config_costeo', 'regimen', "regimen TEXT NOT NULL DEFAULT 'simplificado'");
    await columna('config_costeo', 'factor_iva_compras', 'factor_iva_compras REAL NOT NULL DEFAULT 0.03');
    await columna('config_costeo', 'factor_renta_compras', 'factor_renta_compras REAL NOT NULL DEFAULT 0.025');
    await columna('config_costeo', 'tasa_iva_por_defecto', 'tasa_iva_por_defecto REAL NOT NULL DEFAULT 0.13');
    await columna('config_costeo', 'comision_efectivo', 'comision_efectivo REAL NOT NULL DEFAULT 0');
    final columnas = await db.rawQuery('PRAGMA table_info(config_costeo)');
    if (!columnas.any((c) => c['name'] == 'comision_sinpe')) {
      await db.execute('ALTER TABLE config_costeo ADD COLUMN comision_sinpe REAL NOT NULL DEFAULT 0');
      await db.execute('UPDATE config_costeo SET comision_sinpe = comision_medios_pago');
    }
  }

  /// v6 -> v7. Publica por lo mismo que las anteriores.
  static Future<void> crearTablasDeCosteo(DatabaseExecutor db) async {
    for (final sentencia in esquemaCosteo) {
      await db.execute(sentencia);
    }
  }

  /// v5 -> v6. Publica por lo mismo que las anteriores: que la prueba de
  /// migracion la aplique sobre una base vieja de verdad.
  static Future<void> agregarVariantesDeProducto(DatabaseExecutor db) async {
    final columnas = await db.rawQuery('PRAGMA table_info(producto)');
    if (columnas.any((c) => c['name'] == 'variantes')) return;
    await db.execute('ALTER TABLE producto ADD COLUMN variantes TEXT');
  }

  /// v4 -> v5. Publica por el mismo motivo que la anterior: que las pruebas
  /// suban una base vieja de verdad.
  static Future<void> crearCorteCaja(DatabaseExecutor db) async {
    await db.execute(_createCorteCaja);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_corte_caja_dia ON corte_caja(dia);');
  }

  /// v3 -> v4. Publica para que las pruebas de migracion la apliquen sobre una
  /// base vieja de verdad en vez de recrear el esquema nuevo y dar por sentado
  /// que el camino de actualizacion funciona.
  static Future<void> agregarIconoDeCategoria(Database db) async {
    final columnas = await db.rawQuery('PRAGMA table_info(categoria)');
    if (columnas.any((c) => c['name'] == 'icono')) return;
    await db.execute('ALTER TABLE categoria ADD COLUMN icono TEXT');
  }

  /// El esquema como lista ordenada de sentencias, publico a proposito: las
  /// pruebas lo aplican en bases en memoria en vez de duplicar el DDL a mano.
  /// Duplicarlo hacia que el esquema de las pruebas pudiera divergir del real
  /// en silencio — y una prueba contra un esquema que ya no existe no prueba
  /// nada.
  ///
  /// `venta` y `linea_venta` NO estan aca desde v3: viven en los libros
  /// (decision 0025). Que no existan en la base principal no es un descuido, es
  /// lo que hace que funcione — SQLite resuelve los nombres sin calificar
  /// contra las bases adjuntas, asi que `SELECT * FROM venta` va solo al libro
  /// abierto y el resto del codigo no tuvo que cambiar.
  static const esquema = [
    _createCategoria,
    _createProducto,
    _createLibroVentas,
    _createCorteCaja,
    ...esquemaCosteo,
  ];

  /// Las tablas del costeo (decision 0040), en una lista propia para que la
  /// migracion v7 y `onCreate` apliquen exactamente lo mismo.
  ///
  /// Sin REFERENCES al catalogo, como todo lo demas: la integridad la sostiene
  /// la app, y una receta que apunte a un insumo borrado se ve como alerta, no
  /// como fallo de la base.
  static const esquemaCosteo = [
    '''
    CREATE TABLE IF NOT EXISTS insumo (
      id                    TEXT PRIMARY KEY,
      nombre                TEXT NOT NULL,
      unidad_base           TEXT NOT NULL DEFAULT 'gramo',
      contenido_por_compra  REAL NOT NULL DEFAULT 1,
      precio_compra         REAL NOT NULL DEFAULT 0,
      merma                 REAL,
      proveedor             TEXT,
      notas                 TEXT,
      updated_at            TEXT NOT NULL,
      deleted_at            TEXT
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS costo_fijo (
      id             TEXT PRIMARY KEY,
      concepto       TEXT NOT NULL,
      monto_mensual  REAL NOT NULL DEFAULT 0,
      notas          TEXT,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT
    );
    ''',
    // Una sola fila, id 'unica'. Es una tabla y no preferencias para que viaje
    // por el sync: el margen objetivo es del negocio, no del aparato.
    '''
    CREATE TABLE IF NOT EXISTS config_costeo (
      id                      TEXT PRIMARY KEY,
      dias_abiertos_mes       INTEGER NOT NULL DEFAULT 26,
      margen_objetivo         REAL NOT NULL DEFAULT 0.6,
      comision_medios_pago    REAL NOT NULL DEFAULT 0.03,
      merma_por_defecto       REAL NOT NULL DEFAULT 0.05,
      tarifa_mano_obra_hora   REAL NOT NULL DEFAULT 0,
      redondeo_precio         REAL NOT NULL DEFAULT 50,
      metodo_reparto          TEXT NOT NULL DEFAULT 'unidad',
      regimen                 TEXT NOT NULL DEFAULT 'simplificado',
      factor_iva_compras      REAL NOT NULL DEFAULT 0.03,
      factor_renta_compras    REAL NOT NULL DEFAULT 0.025,
      tasa_iva_por_defecto    REAL NOT NULL DEFAULT 0.13,
      comision_efectivo       REAL NOT NULL DEFAULT 0,
      comision_sinpe          REAL NOT NULL DEFAULT 0,
      tipo_negocio            TEXT NOT NULL DEFAULT 'produccion',
      updated_at              TEXT NOT NULL
    );
    ''',
    // Lo que la hoja anade a un producto o a una de sus variantes. La clave
    // es (producto_id, variante_id) con variante_id '' para el producto sin
    // variantes: una fila por cosa que se vende como "una unidad".
    '''
    CREATE TABLE IF NOT EXISTS articulo_costeo (
      id                      TEXT PRIMARY KEY,
      producto_id             TEXT NOT NULL,
      variante_id             TEXT NOT NULL DEFAULT '',
      unidades_por_lote       INTEGER NOT NULL DEFAULT 1,
      otros_costos_directos   REAL NOT NULL DEFAULT 0,
      minutos_lote            REAL NOT NULL DEFAULT 0,
      unidades_estimadas_mes  INTEGER NOT NULL DEFAULT 0,
      margen_objetivo         REAL,
      ajuste_precio           REAL NOT NULL DEFAULT 0,
      updated_at              TEXT NOT NULL,
      deleted_at              TEXT,
      UNIQUE (producto_id, variante_id)
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS linea_receta (
      id                 TEXT PRIMARY KEY,
      articulo_id        TEXT NOT NULL,
      insumo_id          TEXT NOT NULL,
      cantidad_por_lote  REAL NOT NULL DEFAULT 0,
      notas              TEXT,
      updated_at         TEXT NOT NULL,
      deleted_at         TEXT,
      UNIQUE (articulo_id, insumo_id)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_linea_receta_articulo ON linea_receta(articulo_id);',
  ];

  /// Indices de la base principal. Desde v3 los de `venta`/`linea_venta` no
  /// estan aca: se aplican a cada libro (ver `esquemaLibro`), porque es ahi
  /// donde viven esas tablas.
  static const indices = [
    // Agrupar productos por categoria, que es uno de los ordenes de la
    // Ventana 1 (decision 0018).
    'CREATE INDEX IF NOT EXISTS idx_producto_categoria ON producto(categoria_id);',
    // Los cortes se leen siempre por dia, y es la consulta que corre cada vez
    // que se abre Reportes.
    'CREATE INDEX IF NOT EXISTS idx_corte_caja_dia ON corte_caja(dia);',
  ];

  /// Indices que tenia la base principal en v2, cuando `venta` y `linea_venta`
  /// todavia vivian ahi. Se conservan SOLO para el camino de actualizacion
  /// v1 -> v2: una base v1 pasa por ese estado intermedio antes de que la
  /// migracion v3 mude las ventas a su libro.
  ///
  /// Un esquema nuevo no los usa nunca — sus equivalentes estan en
  /// `esquemaLibro`.
  static const indicesLegacyV2 = [
    'CREATE INDEX IF NOT EXISTS idx_linea_venta_venta ON linea_venta(venta_id);',
    'CREATE INDEX IF NOT EXISTS idx_venta_estado_fecha ON venta(estado, fecha_hora);',
    'CREATE INDEX IF NOT EXISTS idx_venta_fecha ON venta(fecha_hora);',
    'CREATE INDEX IF NOT EXISTS idx_linea_venta_producto ON linea_venta(producto_id);',
  ];

  /// Crea la base principal completa: catalogo, indice de libros e indices.
  ///
  /// OJO: esto NO crea `venta` ni `linea_venta` — esas viven en los libros. Una
  /// prueba que necesite ventas tiene que aplicar ademas `esquemaLibro`
  /// (`aplicarEsquemaLibro`), igual que hace la app al abrir un libro.
  static Future<void> crearEsquema(DatabaseExecutor db) async {
    for (final sentencia in esquema) {
      await db.execute(sentencia);
    }
    await crearIndices(db);
  }

  static Future<void> crearIndices(DatabaseExecutor db) async {
    for (final sentencia in indices) {
      await db.execute(sentencia);
    }
  }

  static Future<void> crearIndicesLegacyV2(DatabaseExecutor db) async {
    for (final sentencia in indicesLegacyV2) {
      await db.execute(sentencia);
    }
  }

  /// Migracion v2 -> v3: mueve `venta` y `linea_venta` de la base principal al
  /// primer libro, crea el indice y las quita de la principal.
  ///
  /// Se escribio como una mudanza real y no como un `DROP` aunque el proyecto
  /// todavia no esta en uso comercial: una migracion que descarta ventas queda
  /// en el codigo para siempre y podria correr en la maquina de alguien. El
  /// costo de hacerla bien era bajo.
  ///
  /// Es la unica vez en la vida del proyecto que las ventas se mueven de
  /// archivo: de aca en adelante nacen ya en su libro (decision 0025).
  static Future<void> migrarVentasALibro(Database db, String directorio) async {
    await db.execute(_createLibroVentas);

    final ventas = await db.query('venta', orderBy: 'fecha_hora');
    if (ventas.isEmpty) {
      // Sin ventas no hace falta libro: el primero se crea con la primera
      // venta real, asi una instalacion nueva no arranca con archivos sueltos.
      await db.execute('DROP TABLE IF EXISTS linea_venta');
      await db.execute('DROP TABLE IF EXISTS venta');
      return;
    }

    final lineas = await db.query('linea_venta');
    final primera = DateTime.parse(ventas.first['fecha_hora'] as String);
    final ultima = DateTime.parse(ventas.last['fecha_hora'] as String);

    final servicio = LibroVentasService(directorio: directorio);
    final archivo = 'ventas-${primera.toIso8601String().split("T").first}.db';
    final libro = await databaseFactory.openDatabase(
      servicio.rutaDe(archivo),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    for (final sentencia in esquemaLibro) {
      await libro.execute(sentencia);
    }
    await libro.transaction((txn) async {
      for (final fila in ventas) {
        await txn.insert('venta', fila);
      }
      for (final fila in lineas) {
        await txn.insert('linea_venta', fila);
      }
    });

    // Verificacion antes de soltar el original: si la copia no cuadra, no se
    // borra nada y la migracion falla ruidosamente.
    final copiadas = (await libro.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'] as int;
    final copiadasLineas =
        (await libro.rawQuery('SELECT COUNT(*) c FROM linea_venta')).first['c'] as int;
    await libro.close();
    if (copiadas != ventas.length || copiadasLineas != lineas.length) {
      throw StateError(
        'migracion v3: el libro quedo con $copiadas/${ventas.length} ventas y '
        '$copiadasLineas/${lineas.length} lineas — no se borra nada',
      );
    }

    // Dias distintos con ventas, que es la unidad con la que se mide un libro.
    final dias = ventas.map((v) => (v['fecha_hora'] as String).split('T').first).toSet().length;

    await db.insert('libro_ventas', {
      'id': const Uuid().v4(),
      'archivo': archivo,
      'fecha_inicio': DateTime(primera.year, primera.month, primera.day).toIso8601String(),
      'fecha_fin': null,
      'dias_con_ventas': dias,
      'ultimo_dia': DateTime(ultima.year, ultima.month, ultima.day).toIso8601String(),
      'cerrado': 0,
    });

    await db.execute('DROP TABLE linea_venta');
    await db.execute('DROP TABLE venta');
  }

  /// Los conteos de caja del dia: apertura, medio dia y cierre.
  ///
  /// Vive en la base principal y no en el libro de ventas aunque sea un dato
  /// diario: son tres filas al dia —mil al ano— y el libro existe para lo que
  /// crece sin techo (decision 0025). Meterlas ahi obligaria a abrir libros
  /// viejos para leer un numero de hoy.
  ///
  /// `dia` guarda la fecha suelta (`2026-08-10`) ademas de `fecha_hora`. Es
  /// redundante a proposito: la regla de orden —no se puede anotar el medio dia
  /// sin haber anotado la apertura— es POR DIA, y comparar una fecha suelta es
  /// mas barato y mucho menos delicado que recortar un instante con zona
  /// horaria en cada consulta.
  ///
  /// `monto` es lo que QUEDA en la caja, no lo que se conto: en el cambio de
  /// turno se guarda la mayor parte del efectivo y se deja una cantidad para
  /// vueltos, asi que este numero es la caja inicial del tramo siguiente.
  static const _createCorteCaja = '''
    CREATE TABLE corte_caja (
      id            TEXT PRIMARY KEY,
      dia           TEXT NOT NULL,
      momento       TEXT NOT NULL,
      monto         REAL NOT NULL,
      fecha_hora    TEXT NOT NULL,
      updated_at    TEXT NOT NULL,
      deleted_at    TEXT
    );
  ''';

  static const _createCategoria = '''
    CREATE TABLE categoria (
      id            TEXT PRIMARY KEY,
      nombre        TEXT NOT NULL,
      -- Clave del icono elegido a mano. NULL = el que salga del nombre, que es
      -- el caso normal: el acierto automatico funciona para casi todas y solo
      -- se toca cuando falla.
      icono         TEXT,
      updated_at    TEXT NOT NULL,
      deleted_at    TEXT
    );
  ''';

  static const _createProducto = '''
    CREATE TABLE producto (
      id            TEXT PRIMARY KEY,
      nombre        TEXT NOT NULL,
      imagen        TEXT,
      categoria_id  TEXT REFERENCES categoria(id),
      precio_base   REAL NOT NULL,
      variantes     TEXT,
      tasa_iva      REAL,
      updated_at    TEXT NOT NULL,
      deleted_at    TEXT
    );
  ''';

  /// Indice de libros de ventas (decision 0025). El nombre del archivo
  /// (`inicio_final.db`) es para que una persona entienda la carpeta de un
  /// vistazo; ESTA TABLA es la fuente de verdad de la app. Depender de parsear
  /// nombres de archivo la dejaria sin saber que tiene ante un renombrado
  /// interrumpido o un archivo movido a mano.
  static const _createLibroVentas = '''
    CREATE TABLE libro_ventas (
      id               TEXT PRIMARY KEY,
      archivo          TEXT NOT NULL,
      fecha_inicio     TEXT NOT NULL,
      fecha_fin        TEXT,
      dias_con_ventas  INTEGER NOT NULL DEFAULT 0,
      ultimo_dia       TEXT,
      cerrado          INTEGER NOT NULL DEFAULT 0
    );
  ''';
}
