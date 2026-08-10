/// Cómo se escribe un monto DENTRO de un campo que se va a editar.
///
/// Los precios de la soda son colones enteros: un casado vale 3000, no 3000.00.
/// Abrir el campo con `3000.00` obliga a borrar el punto y los dos ceros cada
/// vez que se cambia un precio, y en pantalla se lee como si editar fuera
/// borrar el formato en lugar de cambiar el número. Con decimales de verdad
/// —3000.50— se conservan, porque ahí sí llevan información.
///
/// Es solo para campos editables. Lo que se MUESTRA sigue con dos decimales
/// fijos: en una columna de totales, `3000` y `2999.50` uno debajo del otro sin
/// alinear la coma se leen peor.
String montoParaEditar(double monto) {
  return monto == monto.roundToDouble() ? monto.toStringAsFixed(0) : monto.toString();
}
