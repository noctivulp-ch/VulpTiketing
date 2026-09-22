/// Formatos de la ventana de costeo. Colones sin decimales para lo que se
/// cobra; con dos para los costos por unidad, que salen de dividir y son
/// fracciones de verdad (el gramo de harina cuesta 4,64).
String colones(double v, {int decimales = 0}) => v.isNaN ? '—' : '₡${v.toStringAsFixed(decimales)}';

String porcentaje(double? v) => v == null || v.isNaN ? '—' : '${(v * 100).toStringAsFixed(v.abs() < 0.1 ? 1 : 0)} %';

/// Un número para un campo de edición: sin ceros de más.
String numero(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Un porcentaje (0..1) para editarlo como 0..100.
String porcentajeParaEditar(double v) => numero(v * 100);

double? parsearNumero(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));

/// De 0..100 escrito a 0..1 guardado.
double? parsearPorcentaje(String texto) {
  final n = parsearNumero(texto);
  return n == null ? null : n / 100;
}
