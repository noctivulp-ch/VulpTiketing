import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';

const _keyOrdenProducto = 'orden_producto';
const _keyAcentoTinte = 'acento_tinte';

/// Qué se reemplaza al restaurar.
///
/// Restaurar SIEMPRE reemplaza ([decisión 0017](../../../docs/decisiones/0017-restaurar-backup-reemplazo-total.md));
/// el alcance solo dice qué. No existe modo fusionar: para el menú esa vía ya
/// existe por otro camino (`.tiketdata` en modo fusionar), y para las ventas
/// mezclar dos contabilidades por fecha da un híbrido que nadie pidió.
enum AlcanceRestauracion {
  /// Base principal, todos los libros y las preferencias.
  todo,

  /// Catálogo y categorías. No toca ninguna venta.
  soloMenu,

  /// Los libros y su índice. No toca el catálogo.
  soloVentas,
}

/// Una pieza del backup: un archivo, o el JSON de preferencias.
enum _TipoPieza { principal, libro, preferencias }

class _EntradaManifiesto {
  _EntradaManifiesto(this.tipo, this.nombre, this.largo);

  factory _EntradaManifiesto.deJson(Map<String, dynamic> j) => _EntradaManifiesto(
        _TipoPieza.values.byName(j['tipo'] as String),
        j['nombre'] as String,
        j['largo'] as int,
      );

  final _TipoPieza tipo;

  /// Nombre del archivo; vacío para las preferencias.
  final String nombre;
  final int largo;

  Map<String, Object?> aJson() =>
      {'tipo': tipo.name, 'nombre': nombre, 'largo': largo};
}

/// Exportar/restaurar el backup completo cifrado (.tiketback — decisiones
/// 0006/0017/0025).
///
/// Incluye la base principal, **todos los libros de ventas** y las preferencias
/// de UI no sensibles (orden de productos, acento). **No incluye** rol,
/// contraseña ni `device_id`: esos viven en almacenamiento seguro nativo, son
/// específicos de este dispositivo, y se quedan ahí a propósito aunque el
/// archivo ya vaya cifrado — defensa en profundidad (minimizar qué sale del
/// storage seguro, no depender solo del cifrado del backup).
class TiketbackService {
  static const _saltLength = 16;
  static const _macLength = 16;

  /// El nonce de AES-GCM son 12 bytes: 8 aleatorios por backup y 4 con el
  /// número de marco. La clave es distinta en cada backup (el salt es
  /// aleatorio), así que un contador nunca repite el par (clave, nonce) — que
  /// es lo único que GCM no perdona.
  static const _nonceBaseLength = 8;

  static const _magic = 'VTBK';

  /// v1: `[u32][db][u32][prefs]`, sin marca ninguna. Anterior a la 0025.
  /// v2: magic + manifiesto, todo cifrado como UN solo bloque.
  /// v3: marcos independientes, para no cargar el backup entero en memoria.
  static const _versionFormato = 3;

  /// Cuánto texto en claro entra en cada marco.
  ///
  /// Hay DOS razones para este valor, y la segunda no es obvia:
  ///
  /// 1. **Memoria.** El pico queda en este orden sin importar si la base pesa
  ///    300 MB o 3 GB, y el costo de los sellos es despreciable (90 marcos para
  ///    360 MB son 1,4 KB de sellos).
  ///
  /// 2. **Es lo que habilita el cifrado por hardware.** En Android,
  ///    `cryptography_flutter` manda al cifrado del sistema solo lo que mide
  ///    entre 2 KB y **20 MB** — el paquete pone ese techo porque observó
  ///    cuelgues con cargas mayores. Todo lo que se pase de ahí vuelve en
  ///    silencio a AES en Dart puro.
  ///
  /// Medido en un Kirin 710 (perfil AOT), cifrando 4 MB: **85,1 MB/s por
  /// hardware contra 3,6 MB/s en Dart puro — 24 veces**. Con un trozo de 32 MB,
  /// que para memoria sería igual de razonable, las dos vías dan 3,6 MB/s: el
  /// camino nativo no se usa y nada lo avisa.
  ///
  /// Por eso: **subir este valor por encima de 20 MB tiraría el cifrado por
  /// hardware sin ningún error visible.**
  static const _tamanoTrozo = 4 * 1024 * 1024;

  // Mismos parametros que CredencialesService (0011) — un solo lugar de
  // referencia para "que tan caro es derivar una clave" en este proyecto.
  static final _algoritmoClave = Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  );
  static final _algoritmoCifrado = AesGcm.with256bits();

  /// [archivosDeLibro] son nombres, no rutas: viven en [directorioDatos], la
  /// misma carpeta que la base principal.
  ///
  /// Nunca hay más de un trozo en memoria: se lee, se cifra y se escribe de a
  /// [_tamanoTrozo]. Antes se leía todo, se armaba el bundle, se cifraba entero
  /// y se armaba la salida — cuatro copias completas, medidas en +1.701 MB de
  /// RSS con una base de 360 MB.
  Future<void> exportar({
    required String contrasenaExportacion,
    required String directorioDatos,
    required String nombreBasePrincipal,
    required List<String> archivosDeLibro,
    required String rutaDestino,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final preferenciasJson = utf8.encode(jsonEncode({
      _keyOrdenProducto: prefs.getString(_keyOrdenProducto),
      _keyAcentoTinte: prefs.getString(_keyAcentoTinte),
    }));

    final principal = File(p.join(directorioDatos, nombreBasePrincipal));
    final libros = <File>[];
    for (final archivo in archivosDeLibro) {
      final f = File(p.join(directorioDatos, archivo));
      // Un libro registrado en el índice cuyo archivo no está es un estado
      // roto, pero no es razón para dejar al usuario sin backup del resto.
      if (f.existsSync()) libros.add(f);
    }

    final manifiesto = <_EntradaManifiesto>[
      _EntradaManifiesto(_TipoPieza.principal, nombreBasePrincipal, principal.lengthSync()),
      for (final f in libros)
        _EntradaManifiesto(_TipoPieza.libro, p.basename(f.path), f.lengthSync()),
      _EntradaManifiesto(_TipoPieza.preferencias, '', preferenciasJson.length),
    ];

    final salt = _bytesAleatorios(_saltLength);
    final nonceBase = _bytesAleatorios(_nonceBaseLength);
    final clave = await _derivarClave(contrasenaExportacion, salt);

    final destino = await File(rutaDestino).open(mode: FileMode.write);
    try {
      await destino.writeFrom(utf8.encode(_magic));
      await destino.writeFrom(_uint16(_versionFormato));
      await destino.writeFrom(_uint32(_tamanoTrozo));
      await destino.writeFrom(salt);
      await destino.writeFrom(nonceBase);

      // Marco 0: el manifiesto. Va cifrado como todo lo demás — los nombres de
      // archivo delatan en qué fechas hubo actividad.
      var indice = 0;
      final manifiestoBytes = utf8.encode(jsonEncode(
        [for (final e in manifiesto) e.aJson()],
      ));
      await _escribirMarco(destino, clave, nonceBase, indice++, manifiestoBytes,
          ultimo: false);

      // Marcos 1..N: las piezas, una tras otra, cortadas cada _tamanoTrozo.
      //
      // `copy: true` (el que trae por defecto) es OBLIGATORIO acá: `copy: false`
      // guarda una referencia a lo que se le pasa, y abajo se le pasa una vista
      // sobre `trozo`, que se reutiliza en cada lectura. Con `copy: false` los
      // bytes ya encolados se sobrescribían con los siguientes y el backup
      // salía corrupto — SQLite lo detectaba recién al restaurar, con
      // "database disk image is malformed".
      final buffer = BytesBuilder();
      Future<void> vaciar({required bool ultimo}) async {
        await _escribirMarco(
          destino, clave, nonceBase, indice++, buffer.takeBytes(),
          ultimo: ultimo,
        );
      }

      final trozo = Uint8List(_tamanoTrozo);
      for (final archivo in [principal, ...libros]) {
        final origen = await archivo.open(mode: FileMode.read);
        try {
          while (true) {
            final leidos = await origen.readInto(trozo);
            if (leidos == 0) break;
            buffer.add(Uint8List.sublistView(trozo, 0, leidos));
            if (buffer.length >= _tamanoTrozo) await vaciar(ultimo: false);
          }
        } finally {
          await origen.close();
        }
      }
      buffer.add(preferenciasJson);
      // El último marco lleva su marca dentro del sello: sin ella, cortar el
      // archivo por la mitad daría un backup que verifica y al que le faltan
      // meses de ventas.
      await vaciar(ultimo: true);
    } finally {
      await destino.close();
    }
  }

  /// Lanza [SecretBoxAuthenticationError] (de package:cryptography) si la
  /// contraseña es incorrecta — quien llama debe distinguir ese caso.
  ///
  /// Nada se mueve a su lugar definitivo hasta que TODOS los marcos
  /// verificaron: las piezas se descifran a una carpeta de paso y recién
  /// después se aplican. Ni una contraseña mala ni un archivo cortado pueden
  /// dejar el dispositivo a medio restaurar.
  Future<void> restaurar({
    required String contrasenaExportacion,
    required String directorioDatos,
    required String nombreBasePrincipal,
    required String rutaOrigen,
    required AlcanceRestauracion alcance,
  }) async {
    final paso = Directory(p.join(directorioDatos, '.restaurando'));
    if (paso.existsSync()) paso.deleteSync(recursive: true);
    paso.createSync(recursive: true);

    try {
      final piezas = await _descifrarA(paso, rutaOrigen, contrasenaExportacion);

      await AppDatabase.close();
      // Este servicio abre bases por su cuenta (el archivo restaurado y el de
      // paso), y en escritorio eso exige el factory FFI. Si la app se abre y lo
      // primero que hace el usuario es restaurar, nadie lo inicializó todavía.
      AppDatabase.inicializarFactory();

      final rutaPrincipal = p.join(directorioDatos, nombreBasePrincipal);
      final principalDePaso = piezas.rutaPrincipal;
      final librosDePaso = piezas.libros;

      switch (alcance) {
        case AlcanceRestauracion.todo:
          File(principalDePaso).renameSync(rutaPrincipal);
          _moverLibros(librosDePaso, directorioDatos);
          await _borrarLibrosFueraDelIndice(directorioDatos, rutaPrincipal);
          await _restaurarPreferencias(piezas.preferencias);

        case AlcanceRestauracion.soloMenu:
          // No se puede reemplazar el archivo: `categoria`/`producto` comparten
          // `vulp_tiketing.db` con `libro_ventas`, y pisarlo dejaría los libros
          // locales fuera del índice — las ventas seguirían en disco pero la app
          // dejaría de verlas, que para el usuario es lo mismo que perderlas.
          await _reemplazarTablas(
            rutaPrincipal,
            principalDePaso,
            // Categorías primero: `producto.categoria_id` las referencia.
            const ['categoria', 'producto'],
          );

        case AlcanceRestauracion.soloVentas:
          _moverLibros(librosDePaso, directorioDatos);
          await _reemplazarTablas(
            rutaPrincipal,
            principalDePaso,
            const ['libro_ventas'],
          );
          await _borrarLibrosFueraDelIndice(directorioDatos, rutaPrincipal);
      }
    } finally {
      if (paso.existsSync()) paso.deleteSync(recursive: true);
    }
  }

  void _moverLibros(List<String> desde, String directorio) {
    for (final ruta in desde) {
      File(ruta).renameSync(p.join(directorio, p.basename(ruta)));
    }
  }

  /// Borra los `ventas-*.db` que ya no figuran en `libro_ventas`.
  ///
  /// Sin esto, un libro que el backup no traía queda en la carpeta y, si su
  /// nombre coincidiera con uno futuro, aportaría ventas fantasma a los
  /// reportes. El índice manda: lo que no está en él no es un libro.
  Future<void> _borrarLibrosFueraDelIndice(
    String directorio,
    String rutaPrincipal,
  ) async {
    final db = await databaseFactory.openDatabase(
      rutaPrincipal,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    // Un backup de formato 1 trae una base v2, sin índice de libros todavía:
    // sus ventas están dentro del archivo principal y la migración a v3 las
    // moverá al abrir. No hay nada que barrer.
    final tieneIndice = (await db.rawQuery(
      "SELECT COUNT(*) c FROM sqlite_master WHERE type='table' AND name='libro_ventas'",
    )).first['c'] == 1;
    final filas = tieneIndice
        ? await db.query('libro_ventas', columns: ['archivo'])
        : const <Map<String, Object?>>[];
    await db.close();
    if (!tieneIndice) return;

    final vigentes = filas.map((f) => f['archivo'] as String).toSet();
    for (final entrada in Directory(directorio).listSync()) {
      final nombre = p.basename(entrada.path);
      if (entrada is File &&
          nombre.startsWith('ventas-') &&
          nombre.endsWith('.db') &&
          !vigentes.contains(nombre)) {
        entrada.deleteSync();
      }
    }
  }

  /// Reemplaza [tablas] en la base local por las del backup, sin tocar el resto
  /// del archivo. El backup ya está en disco (la carpeta de paso), así que se
  /// adjunta directo: traer las filas a Dart y reinsertarlas sería más lento y
  /// además volvería a cargar todo en memoria, que es justo lo que se evitó.
  Future<void> _reemplazarTablas(
    String rutaPrincipal,
    String rutaDelBackup,
    List<String> tablas,
  ) async {
    final db = await databaseFactory.openDatabase(
      rutaPrincipal,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await db.execute("ATTACH DATABASE '$rutaDelBackup' AS respaldo");
      await db.transaction((txn) async {
        // En orden inverso al de inserción, por las claves foráneas.
        for (final tabla in tablas.reversed) {
          await txn.delete(tabla);
        }
        for (final tabla in tablas) {
          await txn.execute('INSERT INTO $tabla SELECT * FROM respaldo.$tabla');
        }
      });
      await db.execute('DETACH DATABASE respaldo');
    } finally {
      await db.close();
    }
  }

  Future<void> _restaurarPreferencias(Uint8List? bytes) async {
    if (bytes == null) return;

    final preferencias = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    final orden = preferencias[_keyOrdenProducto] as String?;
    final acento = preferencias[_keyAcentoTinte] as String?;
    if (orden != null) await prefs.setString(_keyOrdenProducto, orden);
    if (acento != null) await prefs.setString(_keyAcentoTinte, acento);
  }

  Future<SecretKey> _derivarClave(String contrasena, List<int> salt) {
    return _algoritmoClave.deriveKeyFromPassword(password: contrasena, nonce: salt);
  }

  List<int> _bytesAleatorios(int longitud) {
    final random = Random.secure();
    return List<int>.generate(longitud, (_) => random.nextInt(256));
  }

  /// Un marco: `[u8 ultimo][u32 largo][cipherText][mac]`.
  ///
  /// La cabecera va en claro para poder leerla antes de descifrar, pero entra
  /// en los datos autenticados (AAD) junto con el número de marco. Eso cierra
  /// las dos manipulaciones que un troceado ingenuo habilita:
  ///
  /// - **reordenar** marcos — cada uno verificaría bien por separado y la
  ///   contabilidad restaurada quedaría mezclada, con el archivo pareciendo
  ///   íntegro;
  /// - **truncar** el archivo — restaurarías medio año creyendo que están todas
  ///   las ventas.
  ///
  /// Cambiar cualquiera de los dos bytes rompe el sello.
  Future<void> _escribirMarco(
    RandomAccessFile destino,
    SecretKey clave,
    List<int> nonceBase,
    int indice,
    Uint8List contenido, {
    required bool ultimo,
  }) async {
    final caja = await _algoritmoCifrado.encrypt(
      contenido,
      secretKey: clave,
      nonce: _nonceDe(nonceBase, indice),
      aad: _aad(indice, ultimo),
    );
    await destino.writeFrom([ultimo ? 1 : 0]);
    await destino.writeFrom(_uint32(caja.cipherText.length));
    await destino.writeFrom(caja.cipherText);
    await destino.writeFrom(caja.mac.bytes);
  }

  static List<int> _nonceDe(List<int> base, int indice) =>
      [...base, ..._uint32(indice)];

  static List<int> _aad(int indice, bool ultimo) =>
      [..._uint32(indice), ultimo ? 1 : 0];

  /// Descifra el backup a [paso], marco por marco, y devuelve dónde quedó cada
  /// pieza. En ningún momento hay más de un trozo en memoria.
  ///
  /// Cómo se reconoce cada formato, que no es obvio: **solo v3 tiene el magic
  /// en claro**. En v1 y v2 el archivo empieza con la sal aleatoria y el `VTBK`
  /// de v2 viajaba DENTRO del cifrado, así que los dos son indistinguibles
  /// hasta descifrarlos. De ahí que los formatos viejos compartan un camino: se
  /// descifra el bloque entero y recién entonces se mira si trae manifiesto.
  Future<_PiezasDePaso> _descifrarA(
    Directory paso,
    String rutaOrigen,
    String contrasena,
  ) async {
    // Nada que hacer de a marcos si no es v3: los formatos viejos se cifraban
    // como un solo bloque, que es el problema que v3 resuelve.
    if (!await _empiezaConMagic(rutaOrigen)) {
      return _formatoDeUnBloque(paso, rutaOrigen, contrasena);
    }

    final origen = await File(rutaOrigen).open(mode: FileMode.read);
    try {
      await _leerExacto(origen, _magic.length);
      final version = _leerUint16(await _leerExacto(origen, 2));
      if (version != _versionFormato) {
        throw FormatException(
          'Backup de formato $version, esta app lee hasta $_versionFormato',
        );
      }

      // El tamaño de trozo del encabezado no hace falta para leer: los marcos
      // declaran su propio largo y el manifiesto dice cuántos bytes lleva cada
      // pieza. Se salta, pero se conserva en el formato porque documenta con
      // qué se escribió el archivo.
      await _leerExacto(origen, 4);
      final salt = await _leerExacto(origen, _saltLength);
      final nonceBase = await _leerExacto(origen, _nonceBaseLength);
      final clave = await _derivarClave(contrasena, salt);

      var indice = 0;
      final manifiesto = (jsonDecode(utf8.decode(
        await _leerMarco(origen, clave, nonceBase, indice++),
      )) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(_EntradaManifiesto.deJson)
          .toList();

      // `await` explícito, no `return future`: con `return` el `finally` cierra
      // el archivo antes de que la lectura termine.
      return await _volcarPiezas(
        origen: origen,
        paso: paso,
        clave: clave,
        nonceBase: nonceBase,
        primerIndice: indice,
        manifiesto: manifiesto,
      );
    } finally {
      await origen.close();
    }
  }

  Future<bool> _empiezaConMagic(String ruta) async {
    final f = await File(ruta).open(mode: FileMode.read);
    try {
      final cabecera = await _leerExacto(f, _magic.length);
      return utf8.decode(cabecera, allowMalformed: true) == _magic;
    } finally {
      await f.close();
    }
  }

  /// Reparte el flujo de marcos entre los archivos de paso, siguiendo el
  /// manifiesto: cada pieza consume exactamente su largo declarado.
  Future<_PiezasDePaso> _volcarPiezas({
    required RandomAccessFile origen,
    required Directory paso,
    required SecretKey clave,
    required List<int> nonceBase,
    required int primerIndice,
    required List<_EntradaManifiesto> manifiesto,
  }) async {
    final piezas = _PiezasDePaso();
    var indice = primerIndice;
    var pendiente = Uint8List(0);
    var offset = 0;

    /// Trae bytes del siguiente marco cuando el actual se agotó.
    Future<void> rellenar() async {
      if (offset < pendiente.length) return;
      pendiente = await _leerMarco(origen, clave, nonceBase, indice++);
      offset = 0;
    }

    for (final entrada in manifiesto) {
      if (entrada.tipo == _TipoPieza.preferencias) {
        final buffer = BytesBuilder(copy: false);
        var restante = entrada.largo;
        while (restante > 0) {
          await rellenar();
          final toma = min(restante, pendiente.length - offset);
          buffer.add(Uint8List.sublistView(pendiente, offset, offset + toma));
          offset += toma;
          restante -= toma;
        }
        piezas.preferencias = buffer.takeBytes();
        continue;
      }

      final ruta = p.join(paso.path, entrada.nombre);
      final salida = await File(ruta).open(mode: FileMode.write);
      try {
        var restante = entrada.largo;
        while (restante > 0) {
          await rellenar();
          final toma = min(restante, pendiente.length - offset);
          await salida.writeFrom(pendiente, offset, offset + toma);
          offset += toma;
          restante -= toma;
        }
      } finally {
        await salida.close();
      }

      if (entrada.tipo == _TipoPieza.principal) {
        piezas.rutaPrincipal = ruta;
      } else {
        piezas.libros.add(ruta);
      }
    }
    return piezas;
  }

  Future<Uint8List> _leerMarco(
    RandomAccessFile origen,
    SecretKey clave,
    List<int> nonceBase,
    int indice,
  ) async {
    final ultimo = (await _leerExacto(origen, 1)).first == 1;
    final largo = _leerUint32(await _leerExacto(origen, 4));
    final cipherText = await _leerExacto(origen, largo);
    final mac = await _leerExacto(origen, _macLength);
    return Uint8List.fromList(await _algoritmoCifrado.decrypt(
      SecretBox(cipherText, nonce: _nonceDe(nonceBase, indice), mac: Mac(mac)),
      secretKey: clave,
      aad: _aad(indice, ultimo),
    ));
  }

  Future<Uint8List> _leerExacto(RandomAccessFile origen, int cuantos) async {
    final buffer = Uint8List(cuantos);
    var leidos = 0;
    while (leidos < cuantos) {
      final n = await origen.readInto(buffer, leidos, cuantos);
      if (n == 0) throw const FormatException('Backup incompleto o cortado');
      leidos += n;
    }
    return buffer;
  }

  /// Formatos 1 y 2, que se cifraban como UN bloque y por eso hay que
  /// descifrarlos enteros — el problema que v3 resuelve.
  ///
  /// Cuál de los dos es solo se sabe DESPUÉS de descifrar: en v2 el `VTBK` iba
  /// dentro del cifrado, no en el archivo.
  Future<_PiezasDePaso> _formatoDeUnBloque(
    Directory paso,
    String rutaOrigen,
    String contrasena,
  ) async {
    final bundle = await _descifrarBloqueEntero(rutaOrigen, contrasena, 12);
    if (utf8.decode(bundle.sublist(0, _magic.length), allowMalformed: true) !=
        _magic) {
      return _formatoUno(paso, bundle);
    }

    final data = ByteData.sublistView(bundle);
    var offset = _magic.length + 2;
    final largoManifiesto = data.getUint32(offset, Endian.big);
    offset += 4;
    final manifiesto = (jsonDecode(
      utf8.decode(bundle.sublist(offset, offset + largoManifiesto)),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(_EntradaManifiesto.deJson)
        .toList();
    offset += largoManifiesto;

    final piezas = _PiezasDePaso();
    for (final entrada in manifiesto) {
      final bytes = bundle.sublist(offset, offset + entrada.largo);
      offset += entrada.largo;

      if (entrada.tipo == _TipoPieza.preferencias) {
        piezas.preferencias = bytes;
        continue;
      }
      final ruta = p.join(paso.path, entrada.nombre);
      File(ruta).writeAsBytesSync(bytes, flush: true);
      if (entrada.tipo == _TipoPieza.principal) {
        piezas.rutaPrincipal = ruta;
      } else {
        piezas.libros.add(ruta);
      }
    }
    return piezas;
  }

  /// Formato 1: `[u32 largo][db][u32 largo][prefs]`, sin marca ninguna. Se
  /// generó cuando las ventas vivían dentro de la base principal, así que no
  /// trae libros.
  _PiezasDePaso _formatoUno(Directory paso, Uint8List bundle) {
    final data = ByteData.sublistView(bundle);

    final largoDb = data.getUint32(0, Endian.big);
    final largoPrefs = data.getUint32(4 + largoDb, Endian.big);

    final piezas = _PiezasDePaso()
      ..rutaPrincipal = p.join(paso.path, 'principal.db')
      ..preferencias = bundle.sublist(8 + largoDb, 8 + largoDb + largoPrefs);
    File(piezas.rutaPrincipal)
        .writeAsBytesSync(bundle.sublist(4, 4 + largoDb), flush: true);
    return piezas;
  }

  Future<Uint8List> _descifrarBloqueEntero(
    String rutaOrigen,
    String contrasena,
    int largoNonce,
  ) async {
    final contenido = await File(rutaOrigen).readAsBytes();
    final salt = contenido.sublist(0, _saltLength);
    final nonce = contenido.sublist(_saltLength, _saltLength + largoNonce);
    final resto = contenido.sublist(_saltLength + largoNonce);
    final clave = await _derivarClave(contrasena, salt);
    return Uint8List.fromList(await _algoritmoCifrado.decrypt(
      SecretBox(
        resto.sublist(0, resto.length - _macLength),
        nonce: nonce,
        mac: Mac(resto.sublist(resto.length - _macLength)),
      ),
      secretKey: clave,
    ));
  }

  static Uint8List _uint16(int v) =>
      (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();

  static Uint8List _uint32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();

  static int _leerUint16(Uint8List b) =>
      ByteData.sublistView(b).getUint16(0, Endian.big);

  static int _leerUint32(Uint8List b) =>
      ByteData.sublistView(b).getUint32(0, Endian.big);
}

/// Dónde quedó cada pieza tras descifrar, antes de aplicarla.
class _PiezasDePaso {
  late String rutaPrincipal;
  final List<String> libros = [];
  Uint8List? preferencias;
}
