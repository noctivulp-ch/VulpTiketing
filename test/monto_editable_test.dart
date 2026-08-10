import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/ui/monto_editable.dart';

/// Cómo se abre un campo de precio.
///
/// Lo pidió el dueño después de verlo en pantalla: el campo se abría con
/// `3000.00` y editar un precio se veía como borrar el punto y los dos ceros en
/// vez de cambiar el número. En la soda los precios son colones enteros.
void main() {
  test('un precio entero se abre sin decimales', () {
    expect(montoParaEditar(3000), '3000');
  });

  test('cero también', () {
    expect(montoParaEditar(0), '0');
  });

  test('con decimales de verdad, se conservan', () {
    // Acá el punto sí lleva información y quitarlo cambiaría el precio.
    expect(montoParaEditar(3000.5), '3000.5');
    expect(montoParaEditar(1250.25), '1250.25');
  });

  test('lo que sale se puede volver a leer como número', () {
    // Es lo único que el formulario exige de verdad: el validador hace
    // `double.tryParse`, así que un texto que no parsee bloquea el guardado.
    for (final monto in [0.0, 3000.0, 3000.5, 1250.25, 999999.0]) {
      expect(double.tryParse(montoParaEditar(monto)), monto, reason: '$monto');
    }
  });
}
