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

/// Una pieza del bundle: un archivo, o el JSON de preferencias.
enum _TipoPieza { principal, libro, preferencias }

class _Pieza {
  _Pieza(this.tipo, this.nombre, this.bytes);

  final _TipoPieza tipo;

  /// Nombre del archivo para los libros; vacío para el resto.
  final String nombre;
  final Uint8List bytes;
}

/// Exportar/restaurar el backup completo cifrado (.tiketback — decisiones
/// 0006/0017/0025).
///
/// El bundle incluye la base principal, **todos los libros de ventas** y las
/// preferencias de UI no sensibles (orden de productos, acento). **No incluye**
/// rol, contraseña ni `device_id`: esos viven en almacenamiento seguro nativo,
/// son específicos de este dispositivo, y se quedan ahí a propósito aunque el
/// archivo ya vaya cifrado — defensa en profundidad (minimizar qué sale del
/// storage seguro, no depender solo del cifrado del backup).
class TiketbackService {
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;

  /// Marca del bundle. Antes de la 0025 no había ninguna: un `.tiketback` de
  /// entonces empieza directamente con el largo de la base. Se distinguen por
  /// estos 4 bytes, así que los backups viejos siguen siendo legibles.
  static const _magic = 'VTBK';
  static const _versionFormato = 2;

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
  Future<void> exportar({
    required String contrasenaExportacion,
    required String directorioDatos,
    required String nombreBasePrincipal,
    required List<String> archivosDeLibro,
    required String rutaDestino,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final preferenciasJson = jsonEncode({
      _keyOrdenProducto: prefs.getString(_keyOrdenProducto),
      _keyAcentoTinte: prefs.getString(_keyAcentoTinte),
    });

    final piezas = <_Pieza>[
      _Pieza(
        _TipoPieza.principal,
        nombreBasePrincipal,
        await File(p.join(directorioDatos, nombreBasePrincipal)).readAsBytes(),
      ),
    ];
    for (final archivo in archivosDeLibro) {
      final f = File(p.join(directorioDatos, archivo));
      // Un libro registrado en el índice cuyo archivo no está es un estado
      // roto, pero no es razón para dejar al usuario sin backup del resto.
      if (!f.existsSync()) continue;
      piezas.add(_Pieza(_TipoPieza.libro, archivo, await f.readAsBytes()));
    }
    piezas.add(_Pieza(
      _TipoPieza.preferencias,
      '',
      Uint8List.fromList(utf8.encode(preferenciasJson)),
    ));

    final bundle = _empaquetar(piezas);

    final salt = _bytesAleatorios(_saltLength);
    final clave = await _derivarClave(contrasenaExportacion, salt);
    final secretBox = await _algoritmoCifrado.encrypt(
      bundle,
      secretKey: clave,
      nonce: _bytesAleatorios(_nonceLength),
    );

    // OJO: esto era un literal con spreads (`[...salt, ...cipherText, ...]`) y
    // costaba GIGABYTES. Un literal así construye una `List<int>` genérica, y en
    // Dart cada elemento de una `List<int>` ocupa 8 bytes en el arreglo interno,
    // no 1 — mas el realojado al crecer. Medido con una base de 360 MB: el pico
    // de RSS era de +6.343 MB (17,6x el tamaño de la base) y exportar tardaba
    // 44 s.
    //
    // `BytesBuilder` acumula en `Uint8List`, o sea un byte por byte.
    final salida = BytesBuilder(copy: false)
      ..add(salt)
      ..add(secretBox.nonce)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);
    await File(rutaDestino).writeAsBytes(salida.takeBytes(), flush: true);
  }

  /// Lanza [SecretBoxAuthenticationError] (de package:cryptography) si la
  /// contraseña es incorrecta — quien llama debe distinguir ese caso.
  ///
  /// Nada se escribe hasta que el descifrado terminó: una contraseña mala no
  /// puede dejar el dispositivo a medio restaurar.
  Future<void> restaurar({
    required String contrasenaExportacion,
    required String directorioDatos,
    required String nombreBasePrincipal,
    required String rutaOrigen,
    required AlcanceRestauracion alcance,
  }) async {
    final contenido = await File(rutaOrigen).readAsBytes();
    final salt = contenido.sublist(0, _saltLength);
    final nonce = contenido.sublist(_saltLength, _saltLength + _nonceLength);
    final resto = contenido.sublist(_saltLength + _nonceLength);
    final mac = resto.sublist(resto.length - _macLength);
    final cipherText = resto.sublist(0, resto.length - _macLength);

    final clave = await _derivarClave(contrasenaExportacion, salt);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    final bundle = Uint8List.fromList(
      await _algoritmoCifrado.decrypt(secretBox, secretKey: clave),
    );

    final piezas = _desempaquetar(bundle);
    final principal = piezas.firstWhere((x) => x.tipo == _TipoPieza.principal);
    final libros = piezas.where((x) => x.tipo == _TipoPieza.libro).toList();

    await AppDatabase.close();
    // Este servicio abre bases por su cuenta (el archivo restaurado y un
    // temporal), y en escritorio eso exige el factory FFI. Si la app se abre y
    // lo primero que hace el usuario es restaurar, nadie lo inicializó todavía.
    AppDatabase.inicializarFactory();
    final rutaPrincipal = p.join(directorioDatos, nombreBasePrincipal);

    switch (alcance) {
      case AlcanceRestauracion.todo:
        await File(rutaPrincipal).writeAsBytes(principal.bytes, flush: true);
        await _escribirLibros(directorioDatos, libros);
        await _borrarLibrosFueraDelIndice(directorioDatos, rutaPrincipal);
        await _restaurarPreferencias(piezas);

      case AlcanceRestauracion.soloMenu:
        // No se puede reemplazar el archivo: `categoria`/`producto` comparten
        // `vulp_tiketing.db` con `libro_ventas`, y pisarlo dejaría los libros
        // locales fuera del índice — las ventas seguirían en disco pero la app
        // dejaría de verlas, que para el usuario es lo mismo que perderlas.
        await _reemplazarTablas(
          rutaPrincipal,
          principal.bytes,
          // Categorías primero: `producto.categoria_id` las referencia.
          const ['categoria', 'producto'],
        );

      case AlcanceRestauracion.soloVentas:
        await _escribirLibros(directorioDatos, libros);
        await _reemplazarTablas(
          rutaPrincipal,
          principal.bytes,
          const ['libro_ventas'],
        );
        await _borrarLibrosFueraDelIndice(directorioDatos, rutaPrincipal);
    }
  }

  Future<void> _escribirLibros(String directorio, List<_Pieza> libros) async {
    for (final libro in libros) {
      await File(p.join(directorio, libro.nombre))
          .writeAsBytes(libro.bytes, flush: true);
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
  /// del archivo. El backup se materializa en un temporal y se adjunta, que es
  /// más simple y más rápido que traer las filas a Dart y reinsertarlas.
  Future<void> _reemplazarTablas(
    String rutaPrincipal,
    Uint8List bytesDelBackup,
    List<String> tablas,
  ) async {
    final temporal = File('$rutaPrincipal.restaurando');
    await temporal.writeAsBytes(bytesDelBackup, flush: true);

    final db = await databaseFactory.openDatabase(
      rutaPrincipal,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await db.execute("ATTACH DATABASE '${temporal.path}' AS respaldo");
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
      if (temporal.existsSync()) temporal.deleteSync();
    }
  }

  Future<void> _restaurarPreferencias(List<_Pieza> piezas) async {
    final pieza = piezas.where((x) => x.tipo == _TipoPieza.preferencias);
    if (pieza.isEmpty) return;

    final preferencias =
        jsonDecode(utf8.decode(pieza.first.bytes)) as Map<String, dynamic>;
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

  /// Bundle v2, autodescriptivo:
  ///
  /// ```
  /// "VTBK"      4 bytes
  /// u16         version del formato
  /// u32         largo del manifiesto
  /// manifiesto  JSON UTF-8: [{tipo, nombre, largo}, ...]
  /// piezas      concatenadas, en el orden del manifiesto
  /// ```
  ///
  /// El manifiesto reemplaza al par de largos fijos del formato 1, que solo
  /// admitía dos piezas. El largo va en el JSON y no en un `u32`, que topaba en
  /// 4 GiB — alcanzable con libros de varios años.
  Uint8List _empaquetar(List<_Pieza> piezas) {
    final manifiesto = utf8.encode(jsonEncode([
      for (final pieza in piezas)
        {'tipo': pieza.tipo.name, 'nombre': pieza.nombre, 'largo': pieza.bytes.length},
    ]));

    final builder = BytesBuilder(copy: false);
    builder.add(utf8.encode(_magic));
    builder.add(_uint16Bytes(_versionFormato));
    builder.add(_uint32Bytes(manifiesto.length));
    builder.add(manifiesto);
    for (final pieza in piezas) {
      builder.add(pieza.bytes);
    }
    return builder.takeBytes();
  }

  List<_Pieza> _desempaquetar(Uint8List bundle) {
    if (!_tieneMagic(bundle)) return _desempaquetarFormato1(bundle);

    final data = ByteData.sublistView(bundle);
    var offset = _magic.length;
    final version = data.getUint16(offset, Endian.big);
    if (version != _versionFormato) {
      throw FormatException('Backup de formato $version, esta app lee $_versionFormato');
    }
    offset += 2;
    final largoManifiesto = data.getUint32(offset, Endian.big);
    offset += 4;
    final manifiesto = jsonDecode(
      utf8.decode(bundle.sublist(offset, offset + largoManifiesto)),
    ) as List<dynamic>;
    offset += largoManifiesto;

    final piezas = <_Pieza>[];
    for (final entrada in manifiesto.cast<Map<String, dynamic>>()) {
      final largo = entrada['largo'] as int;
      piezas.add(_Pieza(
        _TipoPieza.values.byName(entrada['tipo'] as String),
        entrada['nombre'] as String,
        bundle.sublist(offset, offset + largo),
      ));
      offset += largo;
    }
    return piezas;
  }

  bool _tieneMagic(Uint8List bundle) {
    final esperado = utf8.encode(_magic);
    if (bundle.length < esperado.length) return false;
    for (var i = 0; i < esperado.length; i++) {
      if (bundle[i] != esperado[i]) return false;
    }
    return true;
  }

  /// Formato anterior a la 0025: `[u32 largo][db][u32 largo][preferencias]`.
  /// Un backup así no tiene libros — cuando se hizo, las ventas vivían dentro
  /// de la base principal.
  List<_Pieza> _desempaquetarFormato1(Uint8List bundle) {
    final data = ByteData.sublistView(bundle);
    var offset = 0;
    final dbLength = data.getUint32(offset, Endian.big);
    offset += 4;
    final dbBytes = bundle.sublist(offset, offset + dbLength);
    offset += dbLength;
    final prefsLength = data.getUint32(offset, Endian.big);
    offset += 4;
    final prefsBytes = bundle.sublist(offset, offset + prefsLength);
    return [
      _Pieza(_TipoPieza.principal, '', dbBytes),
      _Pieza(_TipoPieza.preferencias, '', prefsBytes),
    ];
  }

  Uint8List _uint16Bytes(int value) {
    return (ByteData(2)..setUint16(0, value, Endian.big)).buffer.asUint8List();
  }

  Uint8List _uint32Bytes(int value) {
    return (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();
  }
}
