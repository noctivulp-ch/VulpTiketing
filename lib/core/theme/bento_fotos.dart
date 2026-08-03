/// En qué pantallas se dibujan las fotos de los productos.
///
/// Se puede apagar **por ventana** y no de una vez para toda la app porque no
/// cuestan lo mismo ni sirven para lo mismo: en Venta Rápida hay una cuadrícula
/// entera de fotos que se desplaza con el pulgar —el sitio donde un teléfono
/// lento se nota—, mientras que en Inventario se ven de a pocas y son
/// justamente lo que se está administrando. Quien atiende la caja puede querer
/// la carta sin fotos y el inventario con ellas.
///
/// Apagarlas **no deja el hueco vacío**: en su lugar va el icono de la casa que
/// le toca al producto por su categoría. Lo que se ahorra es decodificar y
/// escalar un JPEG por celda; un glifo de la fuente que ya está cargada no
/// cuesta nada. Así la pantalla sigue diciendo qué es cada cosa.
enum VentanaConFotos {
  ventaRapida,
  venta,
  inventario;

  String get etiqueta => switch (this) {
    VentanaConFotos.ventaRapida => 'Fotos en Venta Rápida',
    VentanaConFotos.venta => 'Fotos en Venta',
    VentanaConFotos.inventario => 'Fotos en Inventario',
  };

  String get explicacion => switch (this) {
    VentanaConFotos.ventaRapida =>
      'La cuadrícula de la carta. Es donde más se nota: son muchas fotos a la '
          'vez y se desplazan con el pulgar. Apagadas se ve el icono de la categoría.',
    VentanaConFotos.venta =>
      'Las miniaturas del carrito. Son pocas y pequeñas, así que apagarlas '
          'alivia poco.',
    VentanaConFotos.inventario =>
      'La lista de productos y el formulario. Acá las fotos son lo que se está '
          'administrando, así que conviene dejarlas.',
  };
}
