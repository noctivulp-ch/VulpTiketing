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

  @override
  Rol? build() => null; // null = sin sesion activa, la UI muestra Login

  Future<bool> iniciarSesion(Rol rol, String contrasena) async {
    final credenciales = CredencialesService(storage: _storage);
    final valida = await credenciales.verificar(contrasena);
    if (!valida) return false;
    state = rol;
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
