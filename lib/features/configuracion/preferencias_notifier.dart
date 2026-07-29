import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/bento_theme.dart';

enum OrdenProducto { alfabetico, precio, categoria }

/// `sistema` sigue el brillo del SO — default, ver `lib/app.dart`.
enum ModoTema { claro, oscuro, sistema }

const _keyOrden = 'orden_producto';
const _keyAcento = 'acento_tinte';
const _keyModoTema = 'modo_tema';

class Preferencias {
  const Preferencias({
    this.ordenProducto = OrdenProducto.alfabetico,
    this.acento = AcentoTinte.grisAzulado,
    this.modoTema = ModoTema.sistema,
  });

  final OrdenProducto ordenProducto;
  final AcentoTinte acento;
  final ModoTema modoTema;

  Preferencias copyWith({
    OrdenProducto? ordenProducto,
    AcentoTinte? acento,
    ModoTema? modoTema,
  }) {
    return Preferencias(
      ordenProducto: ordenProducto ?? this.ordenProducto,
      acento: acento ?? this.acento,
      modoTema: modoTema ?? this.modoTema,
    );
  }
}

/// Preferencias de UI locales, no sensibles (decision 0018) — nunca vive en
/// el almacenamiento seguro que usa CredencialesService (0011, 0019).
class PreferenciasNotifier extends AsyncNotifier<Preferencias> {
  @override
  Future<Preferencias> build() async {
    final prefs = await SharedPreferences.getInstance();
    final orden = OrdenProducto.values.firstWhere(
      (o) => o.name == prefs.getString(_keyOrden),
      orElse: () => OrdenProducto.alfabetico,
    );
    final acento = AcentoTinte.values.firstWhere(
      (a) => a.name == prefs.getString(_keyAcento),
      orElse: () => AcentoTinte.grisAzulado,
    );
    final modoTema = ModoTema.values.firstWhere(
      (m) => m.name == prefs.getString(_keyModoTema),
      orElse: () => ModoTema.sistema,
    );
    return Preferencias(ordenProducto: orden, acento: acento, modoTema: modoTema);
  }

  Future<void> cambiarOrden(OrdenProducto orden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOrden, orden.name);
    state = AsyncData(
      (state.valueOrNull ?? const Preferencias()).copyWith(ordenProducto: orden),
    );
  }

  /// Acento desaturado (docs/pantallas/iconografia.md) — configurable a
  /// pedido explicito del usuario, sin reemplazar el lenguaje de grises.
  Future<void> cambiarAcento(AcentoTinte acento) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAcento, acento.name);
    state = AsyncData(
      (state.valueOrNull ?? const Preferencias()).copyWith(acento: acento),
    );
  }

  Future<void> cambiarModoTema(ModoTema modo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModoTema, modo.name);
    state = AsyncData(
      (state.valueOrNull ?? const Preferencias()).copyWith(modoTema: modo),
    );
  }
}

final preferenciasNotifierProvider =
    AsyncNotifierProvider<PreferenciasNotifier, Preferencias>(
  PreferenciasNotifier.new,
);
