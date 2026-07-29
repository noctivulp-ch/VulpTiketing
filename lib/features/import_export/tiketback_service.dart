import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/db/app_database.dart';

const _keyOrdenProducto = 'orden_producto';
const _keyAcentoTinte = 'acento_tinte';

/// Exportar/restaurar el backup completo cifrado (.tiketback — decisiones
/// 0006/0017).
///
/// El bundle incluye la base de datos SQLite completa + preferencias de UI
/// no sensibles (orden de productos, acento). **No incluye** rol,
/// contraseña ni `device_id`: esos viven en almacenamiento seguro nativo,
/// son específicos de este dispositivo, y se quedan ahí a propósito aunque
/// el archivo ya vaya cifrado — defensa en profundidad (minimizar qué sale
/// del storage seguro, no depender solo del cifrado del backup).
///
/// Restaurar es SIEMPRE reemplazo total (0017) — no existe modo fusionar
/// para este archivo.
class TiketbackService {
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;

  // Mismos parametros que CredencialesService (0011) — un solo lugar de
  // referencia para "que tan caro es derivar una clave" en este proyecto.
  static final _algoritmoClave = Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  );
  static final _algoritmoCifrado = AesGcm.with256bits();

  Future<void> exportar({
    required String contrasenaExportacion,
    required String rutaBaseDeDatos,
    required String rutaDestino,
  }) async {
    final dbBytes = await File(rutaBaseDeDatos).readAsBytes();
    final prefs = await SharedPreferences.getInstance();
    final preferenciasJson = jsonEncode({
      _keyOrdenProducto: prefs.getString(_keyOrdenProducto),
      _keyAcentoTinte: prefs.getString(_keyAcentoTinte),
    });

    final bundle = _empaquetar(dbBytes, utf8.encode(preferenciasJson));

    final salt = _bytesAleatorios(_saltLength);
    final clave = await _derivarClave(contrasenaExportacion, salt);
    final secretBox = await _algoritmoCifrado.encrypt(
      bundle,
      secretKey: clave,
      nonce: _bytesAleatorios(_nonceLength),
    );

    await File(rutaDestino).writeAsBytes([
      ...salt,
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  /// Lanza [SecretBoxAuthenticationError] (de package:cryptography) si la
  /// contraseña es incorrecta — quien llama debe distinguir ese caso.
  Future<void> restaurar({
    required String contrasenaExportacion,
    required String rutaBaseDeDatos,
    required String rutaOrigen,
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

    final (dbBytes, preferenciasBytes) = _desempaquetar(bundle);

    await AppDatabase.close();
    await File(rutaBaseDeDatos).writeAsBytes(dbBytes, flush: true);

    final preferencias = jsonDecode(utf8.decode(preferenciasBytes)) as Map<String, dynamic>;
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

  /// Formato simple: [4 bytes: largo de db][db][4 bytes: largo de
  /// preferencias][preferencias]. No se usa un formato de archivo/ZIP
  /// existente porque el bundle solo tiene estas dos partes — una
  /// abstraccion de archivo comprimido sería más de lo que este caso
  /// necesita.
  Uint8List _empaquetar(List<int> dbBytes, List<int> preferenciasBytes) {
    final builder = BytesBuilder();
    builder.add(_uint32Bytes(dbBytes.length));
    builder.add(dbBytes);
    builder.add(_uint32Bytes(preferenciasBytes.length));
    builder.add(preferenciasBytes);
    return builder.toBytes();
  }

  (Uint8List, Uint8List) _desempaquetar(Uint8List bundle) {
    final data = ByteData.sublistView(bundle);
    var offset = 0;
    final dbLength = data.getUint32(offset, Endian.big);
    offset += 4;
    final dbBytes = bundle.sublist(offset, offset + dbLength);
    offset += dbLength;
    final prefsLength = data.getUint32(offset, Endian.big);
    offset += 4;
    final prefsBytes = bundle.sublist(offset, offset + prefsLength);
    return (dbBytes, prefsBytes);
  }

  Uint8List _uint32Bytes(int value) {
    return (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();
  }
}
