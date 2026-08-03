import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// El token que hace falta para manejar la app desde fuera (el harness del MCP,
/// `test_driver/` + `scripts/mcp-driver/`).
///
/// **Aleatorio, no derivado de la contraseña.** Derivarlo era la idea inicial y
/// tiene dos problemas que la hunden: la contraseña de la app son cuatro
/// dígitos —diez mil posibilidades, con el algoritmo a la vista en el repo— y,
/// al revés, un token filtrado permitiría recuperar la contraseña por fuerza
/// bruta. Acabaría debilitando la contraseña para proteger el harness.
///
/// La contraseña protege igual, pero en el sitio correcto: hace falta para
/// **ver** el token, no para calcularlo. Y como no lo determina, rotarlo es
/// gratis — si se le dio a alguien y hay que cortarle el acceso, se genera otro
/// sin tocar la contraseña.
///
/// Vive en el almacenamiento seguro, junto al `device_id` y los hashes de
/// contraseña (0011, 0019). No entra en el backup: es una llave de este
/// aparato, no un dato del negocio.
class TokenMcpService {
  TokenMcpService({FlutterSecureStorage? storage, Random? aleatorio})
    : _storage = storage ?? const FlutterSecureStorage(),
      _aleatorio = aleatorio ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _aleatorio;

  static const _key = 'token_mcp';

  /// 32 bytes. Un token que alguien va a copiar a mano querría ser corto, pero
  /// esto lo copia una máquina: no hay razón para acercarse a lo adivinable.
  static const _bytes = 32;

  /// El token de este aparato, o `null` si nunca se generó.
  ///
  /// Que empiece sin existir es deliberado: mientras nadie lo pida, no hay
  /// llave que robar y el harness no puede conectarse de ninguna manera.
  Future<String?> leer() => _storage.read(key: _key);

  /// Genera uno nuevo, descartando el anterior. Es también el botón de "revocar
  /// el acceso que le di a alguien".
  Future<String> generar() async {
    final crudo = List<int>.generate(_bytes, (_) => _aleatorio.nextInt(256));
    // Base64 URL-safe: el token viaja como argumento de línea de comandos y
    // como cabecera HTTP, y ahí `+` y `/` obligan a escapar.
    final token = base64UrlEncode(crudo).replaceAll('=', '');
    await _storage.write(key: _key, value: token);
    return token;
  }

  /// Deja el aparato sin token: el harness no puede conectarse hasta que se
  /// genere otro.
  Future<void> revocar() => _storage.delete(key: _key);

  /// Si un token presentado por alguien de fuera es el de este aparato.
  ///
  /// Sin token generado devuelve `false` siempre — ni siquiera para una cadena
  /// vacía, que es lo que llega cuando el otro lado no manda nada.
  Future<bool> verificar(String? presentado) async {
    if (presentado == null || presentado.isEmpty) return false;
    final guardado = await leer();
    if (guardado == null) return false;
    return _iguales(guardado, presentado);
  }

  /// Comparación de tiempo constante.
  ///
  /// Un `==` normal corta en el primer byte distinto, y la diferencia de tiempo
  /// deja adivinar el token carácter a carácter. Acá el atacante es local y el
  /// canal ruidoso, así que la fuga es más teórica que práctica — pero esto
  /// cuesta cuatro líneas y no hace falta volver a pensarlo nunca.
  static bool _iguales(String a, String b) {
    if (a.length != b.length) return false;
    var diferencia = 0;
    for (var i = 0; i < a.length; i++) {
      diferencia |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diferencia == 0;
  }
}

final tokenMcpServiceProvider = Provider<TokenMcpService>((ref) => TokenMcpService());

/// El token actual, o `null` si no hay. Se invalida al generar o revocar.
final tokenMcpProvider = FutureProvider<String?>(
  (ref) => ref.watch(tokenMcpServiceProvider).leer(),
);
