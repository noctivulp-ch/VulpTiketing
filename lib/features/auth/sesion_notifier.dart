import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credenciales_service.dart';

enum Rol { gerente, registradora }

/// El almacén seguro, por provider y no construido a mano dentro del notifier.
///
/// Es lo que permite probar qué hace el arranque cuando el almacén NO contesta,
/// que es el caso que rompía la sesión y el que ninguna prueba podía montar: el
/// canal nativo del paquete no es interceptable desde un test.
final almacenSeguroProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

/// Rol activo, login/logout (decision 0019) — lo que la UI consulta para
/// renderizar condicionalmente (Authentication.feature). No sabe como se
/// verifica una contrasena (CredencialesService) ni el device_id
/// (DeviceIdentityService).
class SesionNotifier extends Notifier<Rol?> {
  /// Rol activo, guardado entre arranques.
  ///
  /// Va al almacenamiento seguro y no a las preferencias por lo mismo que las
  /// contraseñas: es un artefacto de autenticación, y `.tiketback` no lo
  /// respalda a propósito — la sesión es de ESTE dispositivo.
  static const _keyRolActivo = 'rol_activo';

  /// Pista de arranque: el mismo rol, en las preferencias simples.
  ///
  /// No sustituye al almacén seguro, que sigue siendo la VERDAD — sirve para
  /// no dejar la app en blanco mientras el almacén se abre. Medido en el
  /// teléfono del negocio: abrir el almacén cifrado cuesta 1104 ms la primera
  /// vez del proceso (1 ms la segunda), y leer las preferencias, 0. Ese
  /// segundo largo ERA el arranque lento; no era la base de datos, que abre en
  /// 0 ms, ni el catálogo, que carga en 7.
  static const _keyRolPista = 'rol_activo_pista';

  /// Cuánto se espera al almacén seguro antes de seguir sin él.
  ///
  /// Ocho segundos y no tres: abrir el Keystore cuesta 1104–1573 ms medidos en
  /// el teléfono del negocio, y eso con la app tranquila. Compitiendo con el
  /// arranque —base, catálogo, primer frame— pasaba de tres, y de ahí salía el
  /// "el login no se mantiene". El límite existe para el almacén ROTO, no para
  /// el lento.
  ///
  /// Ajustable solo desde las pruebas, para no dejarlas esperando de verdad.
  @visibleForTesting
  static Duration limiteAlmacenSeguro = const Duration(seconds: 8);

  late final _storage = ref.read(almacenSeguroProvider);
  late final _credenciales = CredencialesService(storage: _storage);

  @override
  Rol? build() => null; // null = sin sesion activa, la UI muestra Login

  /// Recupera la sesión guardada. La llama `sesionRestauradaProvider` una vez
  /// al arrancar.
  ///
  /// Sin esto la app pedía contraseña en CADA apertura, que es exactamente lo
  /// que `docs/pantallas/flujo-descripcion.md` dice que no debe pasar: el Login
  /// se ve "solo la primera vez o después de cerrar sesión explícitamente".
  /// Cerrar sesión no es rutinario — es para cambiar de rol en un dispositivo
  /// compartido.
  Future<void> restaurar() async {
    // Arranque optimista: si hay pista, la app abre YA con ella y la
    // verificación contra el almacén seguro sigue por detrás. Si no coincide
    // —o si el almacén dice que no hay sesión— se corrige, y corregir puede
    // significar mandar al Login.
    //
    // El riesgo que se acepta: durante ~1 s alguien que hubiera manipulado las
    // preferencias de la app podría ver la pantalla de un rol que no le
    // corresponde. Quien puede escribir ahí ya puede leer y escribir la base
    // entera —ventas, precios, catálogo—, así que no abre una puerta nueva; y
    // la contraseña, que sí es un secreto, no se mueve del almacén seguro.
    //
    // Sin pista NO hay arranque optimista: se espera. Es lo que pasa la
    // primera vez tras actualizar desde una versión que no la escribía, y ahí
    // vale más un arranque lento que un parpadeo del Login.
    final prefs = await SharedPreferences.getInstance();
    final pista = _rolDe(prefs.getString(_keyRolPista));
    if (pista != null) {
      state = pista;
      unawaited(_verificarConAlmacenSeguro(prefs));
      return;
    }
    await _verificarConAlmacenSeguro(prefs);
  }

  Future<void> _verificarConAlmacenSeguro(SharedPreferences prefs) async {
    String? guardado;
    try {
      // Con límite: esta lectura es la PUERTA del arranque, y si el almacén
      // seguro no contesta —falta libsecret, el canal nativo no responde— la
      // app se quedaría en blanco para siempre. Mejor pedir la contraseña que
      // no abrir.
      guardado = await _storage
          .read(key: _keyRolActivo)
          .timeout(limiteAlmacenSeguro, onTimeout: () => throw TimeoutException(null));
    } catch (_) {
      // NO se toca el estado ni se borra la pista. "No pude comprobar" no es
      // "no hay sesión": tratarlos igual era lo que expulsaba al Login a quien
      // sí tenía sesión, y encima borraba la pista, así que la vez siguiente
      // tampoco arrancaba abierta.
      //
      // Sin pista el estado ya es null y la app pide credenciales, que sigue
      // siendo el fallback correcto: nunca dar acceso por no poder comprobar.
      // Con pista, se sigue con ella — es lo mismo que ya se aceptó al arrancar
      // de forma optimista.
      return;
    }
    final real = _rolDe(guardado);
    // La verdad manda sobre la pista, incluso para cerrar la sesión: si el
    // almacén no tiene rol, es que no hay sesión, diga lo que diga la pista.
    if (real != state) state = real;
    if (real == null) {
      await prefs.remove(_keyRolPista);
    } else {
      await prefs.setString(_keyRolPista, real.name);
    }
  }

  Rol? _rolDe(String? nombre) {
    for (final rol in Rol.values) {
      if (rol.name == nombre) return rol;
    }
    return null;
  }

  Future<bool> iniciarSesion(Rol rol, String contrasena) async {
    final valida = await _credenciales.verificar(rol, contrasena);
    if (!valida) return false;
    state = rol;
    // Si el almacén falla, se entra igual: no poder recordar la sesión no es
    // razón para negar el acceso a quien ya dio la contraseña correcta.
    try {
      await _storage.write(key: _keyRolActivo, value: rol.name);
    } catch (_) {}
    // Con `await`: sin él, cerrar la app enseguida después de entrar dejaba la
    // pista sin escribir y el arranque siguiente volvía a ser el lento.
    await (await SharedPreferences.getInstance()).setString(_keyRolPista, rol.name);
    return true;
  }

  /// Solo desde Configuracion, ya logueado — nunca desde el Login (0002:
  /// la contrasena es de fabrica por defecto, no se "crea" al ingresar).
  Future<bool> cambiarContrasena(Rol rol, String actual, String nueva) async {
    final valida = await _credenciales.verificar(rol, actual);
    if (!valida) return false;
    await _credenciales.cambiarContrasena(rol, nueva);
    return true;
  }

  /// No es rutinario (no se dispara al cerrar la app) — es para cambio de
  /// rol en un dispositivo compartido. Ver docs/pantallas/flujo-descripcion.md
  /// y el addendum de la decision 0007.
  Future<void> cerrarSesion() async {
    state = null;
    // El borrado va DESPUÉS de bajar el estado: si el almacén fallara, la
    // sesión igual queda cerrada en esta ejecución. Al revés, un fallo dejaría
    // al usuario dentro después de pedir salir.
    try {
      await _storage.delete(key: _keyRolActivo);
    } catch (_) {}
    await (await SharedPreferences.getInstance()).remove(_keyRolPista);
  }
}

final sesionNotifierProvider = NotifierProvider<SesionNotifier, Rol?>(SesionNotifier.new);

/// Recupera la sesión guardada, una sola vez al arrancar.
///
/// Es un provider aparte y no parte del estado de sesión porque "todavía no sé
/// si hay sesión" solo importa durante el arranque. Mezclarlo en `Rol?` habría
/// obligado a que las diez pantallas que preguntan `== Rol.gerente` supieran de
/// un estado que nunca ven.
///
/// La app espera a esto antes de decidir qué mostrar: sin la espera, se vería
/// un parpadeo de la pantalla de Login en cada apertura, justo antes de saltar
/// al Dashboard.
final sesionRestauradaProvider = FutureProvider<void>((ref) async {
  await ref.read(sesionNotifierProvider.notifier).restaurar();
});
