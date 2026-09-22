import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'libro_ventas.dart';

/// Lectura de ventas a través de TODOS los libros, cerrados incluidos.
///
/// Los reportes consultaban `venta` sin calificar, que resuelve solo contra el
/// libro adjunto —el abierto—. Tras el primer año con ventas, el libro anterior
/// se cierra y Reportes habría dicho "sin ventas" de un año entero que está
/// intacto en su archivo. La 0025 daba por hecha la "lectura en caliente"
/// porque `ATTACH` la permite; nunca se cableó a una pantalla.
///
/// Acá se cablea: cada consulta recibe el **esquema** contra el que leer
/// (`libro` para el abierto, un alias propio para cada cerrado) y se ejecuta
/// una vez por cada libro que cruce el rango. Un día entero cae siempre en un
/// solo libro —la rotación ocurre al cambiar de día—, pero una semana, un mes
/// o un año pueden cruzar dos, y quien llama funde los resultados.
///
/// Los cerrados se adjuntan **a la misma conexión** y se quedan adjuntos: un
/// libro cerrado nunca cambia, adjuntar cuesta nada, y así el `JOIN` con
/// `main.producto` sigue funcionando sin abrir otra conexión. SQLite admite
/// diez adjuntos por defecto; pasado el tope se sueltan los que no se usan.
class LectorDeLibros {
  /// [servicio] se resuelve solo cuando hace falta adjuntar un libro cerrado:
  /// resolverlo siempre obligaría a toda prueba de reportes a montar
  /// `path_provider`, cuando la mayoría no tiene ni un libro.
  LectorDeLibros(this._db, this._servicio);

  final Database _db;
  final Future<LibroVentasService> Function() _servicio;

  /// Un `ATTACH`/`DETACH` a la vez por conexión: dos reportes concurrentes
  /// sobre el mismo año no pueden pisarse el alias.
  static Future<void> _cola = Future.value();

  /// Cuántos libros cerrados se dejan adjuntos como máximo, aparte del
  /// abierto y de `main`. Por debajo del tope de diez de SQLite, con margen
  /// para el respaldo, que también adjunta.
  static const _maxHistoricos = 6;

  static String aliasDe(LibroVentas libro) => 'h_${libro.id.replaceAll('-', '')}';

  /// Los libros que cruzan `[desde, hasta)`, del más viejo al más nuevo.
  ///
  /// Se mira lo que cada libro TIENE (su primera y su última venta), no lo
  /// que dice el índice: `fecha_inicio` es el día en que se creó el archivo,
  /// y una venta puede ser anterior —llega por sincronización de otro aparato,
  /// o se migró—. Con el índice, la prueba de un mes repartido en dos libros
  /// dejaba fuera al viejo. Es una consulta MIN/MAX sobre la columna indexada
  /// por libro: cuesta nada, y para un libro cerrado se recuerda porque no
  /// cambia jamás.
  Future<List<LibroVentas>> librosDelRango(DateTime desde, DateTime hasta) async {
    final conCobertura = <(DateTime, LibroVentas)>[];
    for (final libro in await _indice()) {
      final cobertura = await _cobertura(libro);
      if (cobertura == null) continue;
      final (primera, ultima) = cobertura;
      if (primera.isBefore(hasta) && !ultima.isBefore(desde)) conCobertura.add((primera, libro));
    }
    conCobertura.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, l) in conCobertura) l];
  }

  /// Primera y última venta activa del libro, o nulo si está vacío.
  static final _coberturaCerrados = <String, (DateTime, DateTime)?>{};

  Future<(DateTime, DateTime)?> _cobertura(LibroVentas libro) async {
    if (libro.cerrado && _coberturaCerrados.containsKey(libro.id)) return _coberturaCerrados[libro.id];
    final e = await esquemaDe(libro);
    final fila = (await _db.rawQuery("SELECT MIN(fecha_hora) a, MAX(fecha_hora) b FROM $e.venta WHERE estado = 'activa'")).first;
    final cobertura = fila['a'] == null
        ? null
        : (DateTime.parse(fila['a'] as String), DateTime.parse(fila['b'] as String));
    if (libro.cerrado) _coberturaCerrados[libro.id] = cobertura;
    return cobertura;
  }

  /// El índice de libros, o nada si la base ni siquiera tiene la tabla (una
  /// base de pruebas con solo las tablas de ventas).
  Future<List<LibroVentas>> _indice() async {
    try {
      final filas = await _db.query('libro_ventas', orderBy: 'fecha_inicio');
      return filas.map(LibroVentas.deFila).toList();
    } on DatabaseException catch (e) {
      if (e.toString().contains('no such table')) return const [];
      rethrow;
    }
  }

  /// Los esquemas contra los que consultar el rango, en orden cronológico,
  /// ya adjuntados. Es lo que usan las consultas.
  ///
  /// Sin ningún libro en el índice —una base de pruebas con las tablas de
  /// ventas en `main`, o una anterior a los libros— devuelve `main`, que es
  /// donde están las tablas en ese caso. Y si el abierto no está adjunto por
  /// el motivo que sea, también `main`: mejor consultar donde hay tablas que
  /// fallar con `no such table`.
  Future<List<String>> esquemasDelRango(DateTime desde, DateTime hasta) async {
    final libros = await librosDelRango(desde, hasta);
    if (libros.isNotEmpty) return [for (final l in libros) await esquemaDe(l)];
    // Sin libro que cubra el rango: `main` si tiene las tablas (pruebas), o
    // nada que consultar.
    final enMain = await _db.rawQuery("SELECT 1 FROM main.sqlite_master WHERE type='table' AND name='venta'");
    return enMain.isEmpty ? const [] : const ['main'];
  }

  /// Ejecuta [consultar] contra cada libro del rango, pasándole el esquema.
  /// Devuelve los resultados en el orden de los libros (cronológico).
  Future<List<T>> enCadaLibro<T>(
    DateTime desde,
    DateTime hasta,
    Future<T> Function(String esquema) consultar,
  ) async {
    final resultados = <T>[];
    for (final esquema in await esquemasDelRango(desde, hasta)) {
      resultados.add(await consultar(esquema));
    }
    return resultados;
  }

  /// El esquema con el que se consulta [libro]: `libro` si es el abierto, o
  /// su alias propio, adjuntándolo si todavía no lo está.
  Future<String> esquemaDe(LibroVentas libro) async {
    if (!libro.cerrado) {
      final adjuntos = await _db.rawQuery('PRAGMA database_list');
      return adjuntos.any((e) => e['name'] == aliasLibro) ? aliasLibro : 'main';
    }
    final alias = aliasDe(libro);
    final anterior = _cola;
    final completer = Completer<void>();
    _cola = completer.future;
    try {
      await anterior;
      final adjuntos = await _adjuntos();
      if (!adjuntos.contains(alias)) {
        await _soltarSiSobran(adjuntos);
        final libros = await _servicio();
        await _db.execute("ATTACH DATABASE '${libros.rutaDe(libro.archivo)}' AS $alias");
        // Un libro cerrado puede ser anterior a una columna nueva: se pone al
        // día como el abierto. Es lo mismo que hace `_adjuntar` en el servicio.
        await ponerAlDiaEsquemaDeLibro(_db, alias: alias);
      }
      return alias;
    } finally {
      completer.complete();
    }
  }

  Future<Set<String>> _adjuntos() async {
    final filas = await _db.rawQuery('PRAGMA database_list');
    return {for (final f in filas) f['name'] as String}..removeAll(['main', 'temp', aliasLibro]);
  }

  Future<void> _soltarSiSobran(Set<String> adjuntos) async {
    final historicos = adjuntos.where((a) => a.startsWith('h_')).toList();
    while (historicos.length >= _maxHistoricos) {
      final alias = historicos.removeAt(0);
      await _db.execute('DETACH DATABASE $alias');
    }
  }
}
