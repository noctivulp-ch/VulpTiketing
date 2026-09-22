import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';

/// Libros de ventas rodantes — decisión 0025.
///
/// Las ventas no viven en la base principal: viven en **libros**, archivos
/// SQLite fechados. Un libro recibe ventas hasta acumular
/// [diasPorLibro] días CON ENTRADAS (no días de calendario: si el negocio
/// cierra dos meses, esos días no gastan el libro). Al día siguiente se cierra y
/// la próxima venta abre uno nuevo.
///
/// La propiedad que hace valioso el modelo: **ningún dato se mueve ni se borra
/// jamás**. Cerrar un libro es dejar de escribirle. No hay copia-y-borrado, que
/// era el paso peligroso del diseño anterior.
///
/// El libro abierto se adjunta con `ATTACH` bajo el alias [aliasLibro]. Como
/// `venta` y `linea_venta` NO existen en la base principal, SQLite resuelve los
/// nombres sin calificar contra la base adjunta — así que `VentaDao`, los
/// reportes y el resto del código consultan `venta` como siempre y las
/// escrituras aterrizan en el archivo del libro. Verificado, incluidos los
/// INSERT y los JOIN contra el catálogo de la base principal.
class LibroVentas {
  const LibroVentas({
    required this.id,
    required this.archivo,
    required this.fechaInicio,
    required this.fechaFin,
    required this.diasConVentas,
    required this.ultimoDia,
    required this.cerrado,
  });

  final String id;
  final String archivo;
  final DateTime fechaInicio;

  /// Solo en libros cerrados: la fecha de su última entrada.
  final DateTime? fechaFin;

  final int diasConVentas;

  /// Último día con al menos una venta. Es lo que permite contar días
  /// DISTINTOS sin recorrer la tabla.
  final DateTime? ultimoDia;

  final bool cerrado;

  static LibroVentas deFila(Map<String, Object?> f) => LibroVentas(
    id: f['id'] as String,
    archivo: f['archivo'] as String,
    fechaInicio: DateTime.parse(f['fecha_inicio'] as String),
    fechaFin: f['fecha_fin'] == null ? null : DateTime.parse(f['fecha_fin'] as String),
    diasConVentas: f['dias_con_ventas'] as int,
    ultimoDia: f['ultimo_dia'] == null ? null : DateTime.parse(f['ultimo_dia'] as String),
    cerrado: (f['cerrado'] as int) == 1,
  );
}

const _uuid = Uuid();

/// Alias con el que se adjunta el libro abierto.
const aliasLibro = 'libro';

/// Días con ventas que caben en un libro antes de cerrarlo.
const diasPorLibro = 365;

/// Esquema de un libro: solo las tablas de ventas, con los mismos índices que
/// tenía la base principal. Se reutiliza tal cual para cada libro nuevo.
const esquemaLibro = [
  '''
    CREATE TABLE IF NOT EXISTS venta (
      id                TEXT PRIMARY KEY,
      fecha_hora        TEXT NOT NULL,
      detalle           TEXT,
      estado            TEXT NOT NULL DEFAULT 'activa'
                         CHECK (estado IN ('activa', 'revertida')),
      motivo_reversion  TEXT,
      metodo_pago       TEXT NOT NULL DEFAULT 'efectivo'
                         CHECK (metodo_pago IN ('efectivo', 'sinpe')),
      referencia_pago   TEXT,
      updated_at        TEXT NOT NULL
    );
  ''',
  '''
    CREATE TABLE IF NOT EXISTS linea_venta (
      id               TEXT PRIMARY KEY,
      venta_id         TEXT NOT NULL,
      producto_id      TEXT,
      nombre_libre     TEXT,
      precio_aplicado  REAL NOT NULL,
      cantidad         INTEGER NOT NULL DEFAULT 1,
      nota             TEXT,
      variante         TEXT,
      updated_at       TEXT NOT NULL,
      CHECK (
        (producto_id IS NOT NULL AND nombre_libre IS NULL) OR
        (producto_id IS NULL AND nombre_libre IS NOT NULL)
      )
    );
  ''',
  ..._tablasNuevasDelLibro,
  'CREATE INDEX IF NOT EXISTS idx_linea_venta_venta ON linea_venta(venta_id);',
  'CREATE INDEX IF NOT EXISTS idx_venta_estado_fecha ON venta(estado, fecha_hora);',
  'CREATE INDEX IF NOT EXISTS idx_venta_fecha ON venta(fecha_hora);',
  'CREATE INDEX IF NOT EXISTS idx_linea_venta_producto ON linea_venta(producto_id);',
];

/// Tablas que se sumaron al libro después de que hubiera libros escritos.
/// Forman parte de [esquemaLibro] y además se crean donde falten al adjuntar
/// un libro viejo. Solo lo NUEVO va acá: replicar el esquema entero sobre un
/// libro viejo tropieza con índices de columnas que ese libro no tiene.
const _tablasNuevasDelLibro = [
  // Compras de insumos (decisión 0041): lo que ENTRA, en el mismo libro que
  // lo que sale. `insumo_id` sin REFERENCES, como todo lo demás del libro.
  '''
    CREATE TABLE IF NOT EXISTS compra_insumo (
      id             TEXT PRIMARY KEY,
      insumo_id      TEXT NOT NULL,
      fecha          TEXT NOT NULL,
      presentaciones REAL NOT NULL DEFAULT 1,
      contenido      REAL NOT NULL,
      pagado         REAL NOT NULL,
      notas          TEXT,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT
    );
  ''',
  'CREATE INDEX IF NOT EXISTS idx_compra_insumo_fecha ON compra_insumo(fecha);',
  'CREATE INDEX IF NOT EXISTS idx_compra_insumo_insumo ON compra_insumo(insumo_id);',
];

/// Columnas que se agregaron a las tablas del libro después de que hubiera
/// libros escritos, por tabla.
///
/// Un libro es un archivo suelto que puede venir de otro aparato o de un backup
/// viejo, así que su esquema se pone al día **al adjuntarlo**, no en la
/// migración de la base principal: esa solo ve el libro abierto de este
/// dispositivo y no los cerrados de años anteriores.
///
/// `ADD COLUMN` con `DEFAULT` no reescribe las filas existentes en SQLite —
/// solo toca la cabecera de la tabla—, así que aplicarlo sobre un libro con
/// 100.000 ventas es instantáneo.
const _columnasNuevasDelLibro = {
  'venta': {
    'metodo_pago': "ALTER TABLE venta ADD COLUMN metodo_pago TEXT NOT NULL DEFAULT 'efectivo'",
    'referencia_pago': 'ALTER TABLE venta ADD COLUMN referencia_pago TEXT',
  },
  // Qué variante se vendió, por su NOMBRE: foto del día, como el precio
  // (decisión 0039). NULL en toda línea anterior a las variantes, y en toda
  // línea de un producto que no las tiene.
  'linea_venta': {'variante': 'ALTER TABLE linea_venta ADD COLUMN variante TEXT'},
};

/// Pone al día el esquema de un libro ya escrito.
///
/// Se consulta qué columnas tiene en vez de llevar un número de versión por
/// libro: los libros no tienen tabla de metadatos propia y agregarle una para
/// esto sería más frágil que preguntar. `PRAGMA table_info` cuesta lo mismo que
/// un `SELECT` de una fila.
Future<void> ponerAlDiaEsquemaDeLibro(DatabaseExecutor db, {String? alias}) async {
  final prefijo = alias == null ? '' : '$alias.';

  // Tablas que se sumaron al libro después de que hubiera libros escritos
  // (compra_insumo, 0041): se crean donde falten. Solo si el libro ya tiene
  // `venta`: un archivo sin tablas es uno que todavía no se creó, y ese lo
  // crea `_crear` entero.
  final tieneVenta = (await db.rawQuery('PRAGMA ${prefijo}table_info(venta)')).isNotEmpty;
  if (tieneVenta) {
    for (final sentencia in _tablasNuevasDelLibro) {
      await db.execute(_calificar(sentencia, prefijo));
    }
  }

  for (final tabla in _columnasNuevasDelLibro.entries) {
    final columnas = await db.rawQuery('PRAGMA ${prefijo}table_info(${tabla.key})');
    if (columnas.isEmpty) continue; // El libro todavía no tiene esta tabla.

    final presentes = {for (final c in columnas) c['name'] as String};
    for (final columna in tabla.value.entries) {
      if (presentes.contains(columna.key)) continue;
      // El `ALTER` está escrito sin calificar; se califica acá para que el
      // mismo texto sirva para el libro adjunto y para uno abierto suelto.
      await db.execute(columna.value.replaceFirst('TABLE ${tabla.key}', 'TABLE $prefijo${tabla.key}'));
    }
  }
}

/// `CREATE TABLE x` / `CREATE INDEX i ON x` con el esquema delante, para
/// aplicar el DDL del libro sobre uno adjunto. SQLite exige el índice en el
/// mismo esquema que su tabla, y lo resuelve por el nombre de la tabla, así
/// que el índice va calificado por su NOMBRE y la tabla sin calificar.
String _calificar(String sentencia, String prefijo) {
  if (prefijo.isEmpty) return sentencia;
  // `replaceFirstMapped`, no `replaceFirst`: el reemplazo con `$1` de Dart no
  // expande grupos.
  return sentencia
      .replaceFirstMapped(
        RegExp(r'CREATE TABLE IF NOT EXISTS (\w+)'),
        (m) => 'CREATE TABLE IF NOT EXISTS $prefijo${m[1]}',
      )
      .replaceFirstMapped(
        RegExp(r'CREATE INDEX IF NOT EXISTS (\w+) ON (\w+)'),
        (m) => 'CREATE INDEX IF NOT EXISTS $prefijo${m[1]} ON ${m[2]}',
      );
}

/// `linea_venta.producto_id` NO lleva REFERENCES a `producto`: el catálogo vive
/// en otra base. Un libro tiene que poder abrirse y leerse por su cuenta —
/// incluso restaurado suelto desde un backup— sin depender de la base
/// principal. La integridad de esa referencia la sostiene la app, no el motor.
///
/// Gestiona qué libro está abierto, lo adjunta, y lo rota cuando corresponde.
class LibroVentasService {
  LibroVentasService({required this.directorio});

  /// Carpeta donde viven los libros. Es la misma de la base principal.
  final String directorio;

  String rutaDe(String archivo) => p.join(directorio, archivo);

  static String _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _nombreAbierto(DateTime inicio) =>
      'ventas-${inicio.toIso8601String().split("T").first}.db';

  static String _nombreCerrado(DateTime inicio, DateTime fin) =>
      'ventas-${inicio.toIso8601String().split("T").first}'
      '_${fin.toIso8601String().split("T").first}.db';

  Future<LibroVentas?> libroAbierto(DatabaseExecutor db) async {
    final filas = await db.query('libro_ventas', where: 'cerrado = 0', limit: 1);
    return filas.isEmpty ? null : LibroVentas.deFila(filas.first);
  }

  Future<List<LibroVentas>> todos(DatabaseExecutor db) async {
    final filas = await db.query('libro_ventas', orderBy: 'fecha_inicio');
    return filas.map(LibroVentas.deFila).toList();
  }

  /// Crea el archivo de un libro con su esquema y lo registra en el índice.
  Future<LibroVentas> _crear(DatabaseExecutor db, DateTime primeraFecha) async {
    final archivo = _nombreAbierto(primeraFecha);
    final ruta = rutaDe(archivo);

    // El archivo se crea abriéndolo aparte: no se puede aplicar DDL sobre una
    // base que todavía no está adjunta.
    final nuevo = await databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    for (final sentencia in esquemaLibro) {
      await nuevo.execute(sentencia);
    }
    await nuevo.close();

    final libro = LibroVentas(
      id: _uuid.v4(),
      archivo: archivo,
      fechaInicio: primeraFecha,
      fechaFin: null,
      diasConVentas: 1,
      ultimoDia: primeraFecha,
      cerrado: false,
    );
    await db.insert('libro_ventas', {
      'id': libro.id,
      'archivo': libro.archivo,
      'fecha_inicio': _soloFecha(primeraFecha),
      'fecha_fin': null,
      'dias_con_ventas': 1,
      'ultimo_dia': _soloFecha(primeraFecha),
      'cerrado': 0,
    });
    return libro;
  }

  /// Adjunta el libro abierto. Si no hay ninguno, no adjunta nada: el primero
  /// se crea recién con la primera venta, así una instalación sin ventas no
  /// tiene archivos de libro sueltos.
  /// Deja SIEMPRE un libro adjunto, creándolo si todavía no existe.
  ///
  /// Antes se salía sin hacer nada cuando no había libro, y eso rompía la app
  /// recién instalada: el libro nacía con la primera venta, así que hasta
  /// entonces `SELECT ... FROM linea_venta` no resolvía contra nada y Reportes
  /// —o cualquier pantalla que consultara ventas— moría con
  /// `no such table: linea_venta`. Un negocio que abre la app antes de cobrar
  /// nada es el caso NORMAL del primer día, no un borde.
  ///
  /// Crear el libro vacío no adelanta ninguna decisión: es el mismo archivo que
  /// habría creado la primera venta, con las mismas tablas y sin filas.
  Future<void> adjuntarAbierto(Database db) async {
    final libro = await libroAbierto(db) ?? await _crear(db, DateTime.now());
    await _adjuntar(db, libro.archivo);
  }

  /// Si el alias del libro ya está adjunto en esta conexión.
  ///
  /// `PRAGMA database_list` lista los esquemas realmente montados. Es la única
  /// forma de saberlo: preguntar por la tabla `venta` no distingue entre "no
  /// hay libro" y "el libro está adjunto pero vacío".
  Future<bool> estaAdjunto(DatabaseExecutor db) async {
    final esquemas = await db.rawQuery('PRAGMA database_list');
    return esquemas.any((e) => e['name'] == aliasLibro);
  }

  /// Idempotente, y tolerante a que dos llamadas corran a la vez.
  ///
  /// Sin esto, un segundo ATTACH sobre la misma conexión muere con
  /// `database libro is already in use` y deja la app entera inutilizable —
  /// toda pantalla que consulte ventas revienta. Ocurría de verdad: sqflite
  /// abre por defecto en modo `singleInstance`, así que dos aperturas
  /// concurrentes devuelven LA MISMA conexión, y la segunda volvía a adjuntar.
  ///
  /// Comprobar antes NO alcanza: entre la comprobación y el ATTACH hay un
  /// `await`, y varios llamadores pueden ver "no adjunto" a la vez. Por eso el
  /// fallo se acepta solo si, al mirar de nuevo, el libro quedó adjunto — o
  /// sea, si perdimos una carrera contra alguien que hizo el mismo trabajo.
  /// Cualquier otro error sigue subiendo.
  Future<void> _adjuntar(Database db, String archivo) async {
    if (await estaAdjunto(db)) await desadjuntar(db);
    try {
      await db.execute("ATTACH DATABASE '${rutaDe(archivo)}' AS $aliasLibro");
    } catch (_) {
      if (!await estaAdjunto(db)) rethrow;
    }
    // Al adjuntar, y no antes: un libro puede venir de otro aparato o de un
    // backup viejo, y el esquema se pone al día donde se lo encuentra.
    await ponerAlDiaEsquemaDeLibro(db, alias: aliasLibro);
  }

  /// Suelta el libro adjunto, si lo hay. Público porque cerrar la base también
  /// tiene que soltarlo (ver `AppDatabase.close`).
  Future<void> desadjuntar(Database db) async {
    // Falla si no hay nada adjunto; se ignora a propósito para que el llamador
    // no tenga que llevar la cuenta.
    try {
      await db.execute('DETACH DATABASE $aliasLibro');
    } catch (_) {}
  }

  /// Se llama ANTES de guardar una venta con fecha [fecha]. Deja adjunto el
  /// libro que debe recibirla, rotando si corresponde.
  ///
  /// Devuelve el libro que quedó abierto.
  Future<LibroVentas> prepararPara(Database db, DateTime fecha) async {
    final actual = await libroAbierto(db);

    if (actual == null) {
      final libro = await _crear(db, fecha);
      await _adjuntar(db, libro.archivo);
      return libro;
    }

    // Mismo día que la última venta: nada que hacer.
    if (actual.ultimoDia != null && _mismoDia(actual.ultimoDia!, fecha)) {
      return actual;
    }

    // Día nuevo. Si el libro ya está lleno, esta venta abre uno nuevo — es
    // exactamente "al llegar al 365+1, la primera entrada del +1 va a otro
    // archivo".
    if (actual.diasConVentas >= diasPorLibro) {
      await _cerrar(db, actual);
      final libro = await _crear(db, fecha);
      await _adjuntar(db, libro.archivo);
      return libro;
    }

    await db.update(
      'libro_ventas',
      {'dias_con_ventas': actual.diasConVentas + 1, 'ultimo_dia': _soloFecha(fecha)},
      where: 'id = ?',
      whereArgs: [actual.id],
    );
    return LibroVentas(
      id: actual.id,
      archivo: actual.archivo,
      fechaInicio: actual.fechaInicio,
      fechaFin: null,
      diasConVentas: actual.diasConVentas + 1,
      ultimoDia: fecha,
      cerrado: false,
    );
  }

  /// Recalcula `dias_con_ventas` y `ultimo_dia` del libro abierto a partir de
  /// lo que hay REALMENTE dentro.
  ///
  /// Hace falta porque `prepararPara` solo cuenta los días de las ventas que
  /// pasan por la caja de este dispositivo, y el sync mete ventas por otro
  /// camino: `RowUpserter` inserta directo en la tabla `venta` del libro
  /// adjunto. Un libro que reciba todo por sync no contaría un solo día y no
  /// rotaría nunca.
  ///
  /// Recalcula en vez de incrementar a propósito: incrementar acumularía error
  /// cada vez que llega una venta de un día que ya estaba contado, y el sync
  /// reenvía las mismas filas una y otra vez. Contar lo que hay es exacto y da
  /// igual cuántas veces se llame.
  Future<void> recontarDias(Database db) async {
    final libro = await libroAbierto(db);
    if (libro == null) return;

    final r = (await db.rawQuery(
      'SELECT COUNT(DISTINCT date(fecha_hora)) AS dias, MAX(fecha_hora) AS ultimo FROM venta',
    )).first;
    final dias = (r['dias'] as int?) ?? 0;
    if (dias == 0) return;

    final ultimo = r['ultimo'] as String?;
    await db.update(
      'libro_ventas',
      {
        'dias_con_ventas': dias,
        if (ultimo != null) 'ultimo_dia': _soloFecha(DateTime.parse(ultimo)),
      },
      where: 'id = ?',
      whereArgs: [libro.id],
    );
  }

  /// Cierra un libro: lo desadjunta, renombra el archivo a
  /// `inicio_final.db` y actualiza el índice.
  ///
  /// El nombre es para que una persona entienda la carpeta de un vistazo; la
  /// fuente de verdad de la app es el índice, no el nombre del archivo. Si el
  /// renombrado fallara, el índice conserva el nombre viejo y el libro sigue
  /// siendo legible.
  Future<void> _cerrar(Database db, LibroVentas libro) async {
    final fin = libro.ultimoDia ?? libro.fechaInicio;
    await desadjuntar(db);

    final nombreFinal = _nombreCerrado(libro.fechaInicio, fin);
    final origen = File(rutaDe(libro.archivo));
    var archivoRegistrado = libro.archivo;
    if (origen.existsSync()) {
      origen.renameSync(rutaDe(nombreFinal));
      archivoRegistrado = nombreFinal;
    }

    await db.update(
      'libro_ventas',
      {'archivo': archivoRegistrado, 'fecha_fin': _soloFecha(fin), 'cerrado': 1},
      where: 'id = ?',
      whereArgs: [libro.id],
    );
  }
}

/// Aplica el esquema de un libro a una base cualquiera.
///
/// En producción cada libro es su propio archivo, pero una prueba que solo
/// quiere ejercitar consultas de ventas puede aplicarlo sobre la misma base en
/// memoria: SQLite resuelve los nombres igual, así que la lógica bajo prueba es
/// la misma. Lo que cambia es dónde viven las tablas, no cómo se consultan.
Future<void> aplicarEsquemaLibro(DatabaseExecutor db) async {
  for (final sentencia in esquemaLibro) {
    await db.execute(sentencia);
  }
}

/// Provider del servicio: los libros viven en la misma carpeta que la base
/// principal.
///
/// Es un `FutureProvider` porque resolver esa carpeta es asincrono
/// (`path_provider`). Se resuelve solo, sin que cada entrypoint tenga que
/// inyectarlo — una prueba que necesite otra carpeta lo sobreescribe.
final libroVentasServiceProvider = FutureProvider<LibroVentasService>((ref) async {
  return LibroVentasService(directorio: p.dirname(await AppDatabase.ruta()));
});

/// Solo las tablas de un libro, sin sus índices.
///
/// Sirve para reconstruir el estado de una base v1, que tenía las tablas de
/// ventas sin ningún índice — usarlo en la prueba de migración evita duplicar
/// ese DDL viejo en el archivo de prueba, donde podría divergir en silencio.
Future<void> aplicarEsquemaLibroSinIndices(DatabaseExecutor db) async {
  for (final sentencia in esquemaLibro.where((s) => !s.contains('CREATE INDEX'))) {
    await db.execute(sentencia);
  }
}
