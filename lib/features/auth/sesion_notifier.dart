import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credenciales_service.dart';

enum Rol { gerente, registradora }

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

  final _storage = const FlutterSecureStorage();
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
    String? guardado;
    try {
      // Con límite: esta lectura es la PUERTA del arranque, y si el almacén
      // seguro no contesta —falta libsecret, el canal nativo no responde— la
      // app se quedaría en blanco para siempre. Mejor pedir la contraseña que
      // no abrir.
      guardado = await _storage
          .read(key: _keyRolActivo)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (_) {
      // Sin almacén seguro disponible no hay sesión que recuperar. Pedir
      // credenciales es el fallback correcto: nunca dar acceso por no poder
      // comprobar.
      return;
    }
    if (guardado == null) return;
    for (final rol in Rol.values) {
      if (rol.name == guardado) {
        state = rol;
        return;
      }
    }
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
  }
}

final sesionNotifierProvider =
    NotifierProvider<SesionNotifier, Rol?>(SesionNotifier.new);

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
