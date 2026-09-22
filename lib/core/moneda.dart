import 'package:flutter/widgets.dart';

/// Con qué se escribe el dinero (decisión 0043). Colones enteros de fábrica
/// —los precios de la calle no llevan centavos— y opcional: símbolo y
/// decimales, para un negocio que cobra en dólares o donde los centavos
/// existen.
///
/// Es de PRESENTACIÓN y captura: la base guarda `REAL` sin moneda (0012) y
/// no se convierte nada. Cambiar de moneda no reescribe una sola venta; solo
/// cambia cómo se leen los números que ya están.
@immutable
class Moneda {
  const Moneda({required this.simbolo, required this.decimales});

  static const colon = Moneda(simbolo: '₡', decimales: 0);

  final String simbolo;

  /// Con cuántos decimales se muestran y se capturan los montos.
  final int decimales;

  /// "₡3000" o "$12.50" según la moneda. [decimales] fuerza otros: los costos
  /// por gramo del costeo se leen con dos aunque la moneda vaya en enteros.
  String formatear(double monto, {int? decimales}) => '$simbolo${monto.toStringAsFixed(decimales ?? this.decimales)}';

  /// Para una etiqueta de campo: "Precio (₡)".
  String get entreParentesis => '($simbolo)';

  /// La moneda vigente en este punto del árbol; colones si nadie la puso
  /// (pruebas de widget sueltas).
  static Moneda de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MonedaScope>()?.moneda ?? colon;

  @override
  bool operator ==(Object other) => other is Moneda && other.simbolo == simbolo && other.decimales == decimales;

  @override
  int get hashCode => Object.hash(simbolo, decimales);
}

/// Pone la moneda al alcance de todo widget, incluidos los que no leen
/// providers: es lo que hace que un `Text` con un monto no necesite `ref`.
class MonedaScope extends InheritedWidget {
  const MonedaScope({super.key, required this.moneda, required super.child});

  final Moneda moneda;

  @override
  bool updateShouldNotify(MonedaScope viejo) => viejo.moneda != moneda;
}
