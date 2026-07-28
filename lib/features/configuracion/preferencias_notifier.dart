import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OrdenProducto { alfabetico, precio, categoria }

const _prefKeyOrden = 'orden_producto';

/// Preferencias de UI locales, no sensibles (decision 0018) — nunca vive en
/// el almacenamiento seguro que usa CredencialesService (0011, 0019).
class PreferenciasNotifier extends AsyncNotifier<OrdenProducto> {
  @override
  Future<OrdenProducto> build() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_prefKeyOrden);
    return OrdenProducto.values.firstWhere(
      (o) => o.name == guardado,
      orElse: () => OrdenProducto.alfabetico,
    );
  }

  Future<void> cambiarOrden(OrdenProducto orden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyOrden, orden.name);
    state = AsyncData(orden);
  }
}

final preferenciasNotifierProvider =
    AsyncNotifierProvider<PreferenciasNotifier, OrdenProducto>(
  PreferenciasNotifier.new,
);
