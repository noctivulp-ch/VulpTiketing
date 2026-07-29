import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credenciales_service.dart';

enum Rol { gerente, registradora }

/// Rol activo, login/logout (decision 0019) — lo que la UI consulta para
/// renderizar condicionalmente (Authentication.feature). No sabe como se
/// verifica una contrasena (CredencialesService) ni el device_id
/// (DeviceIdentityService).
class SesionNotifier extends Notifier<Rol?> {
  final _storage = const FlutterSecureStorage();
  late final _credenciales = CredencialesService(storage: _storage);

  @override
  Rol? build() => null; // null = sin sesion activa, la UI muestra Login

  Future<bool> iniciarSesion(Rol rol, String contrasena) async {
    final valida = await _credenciales.verificar(rol, contrasena);
    if (!valida) return false;
    state = rol;
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
  void cerrarSesion() {
    state = null;
  }
}

final sesionNotifierProvider =
    NotifierProvider<SesionNotifier, Rol?>(SesionNotifier.new);
