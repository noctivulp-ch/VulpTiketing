import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El espacio de la barra de navegación del sistema se reserva **una sola vez**.
///
/// Desde Android 15 el modo `edge-to-edge` es obligatorio: la app se dibuja por
/// debajo de las barras del sistema y tiene que apartarse ella misma. Ahí el
/// inset inferior es un número real, no cero.
///
/// El fallo: una barra inferior de pantalla —el buscador de Venta Rápida, el de
/// Inventario— lleva su propio `SafeArea`, y la banda de navegación del shell
/// también. Como son hermanas y no una descendiente de la otra, las dos ven el
/// mismo inset y las dos lo reservan, dejando una franja muerta entre el
/// buscador y las pestañas. Se pierden 48 dp de contenido.
///
/// En Android 10 no se ve —la barra del sistema vive fuera de la app y el inset
/// es 0—, así que hizo falta el teléfono de la soda para que saliera.
///
/// ## Por qué esto no es una prueba de comportamiento
///
/// Se intentó, y **no se pudo**: `flutter_test` no reproduce la condición.
/// Poniendo `tester.view.padding` y `viewPadding` a 48, un `Scaffold` intermedio
/// consume el inset y las pantallas ven 0 igualmente — la distancia entre el
/// buscador y las pestañas sale idéntica con y sin el arreglo. Tres versiones de
/// esa prueba pasaron en los dos casos, o sea no probaban nada.
///
/// Dejar una prueba que no distingue es peor que no tener ninguna: da confianza
/// sin respaldarla. Así que queda lo honesto — una comprobación **estructural**
/// de que el arreglo sigue en su sitio, más la verificación real, que se hizo en
/// el aparato comparando dos capturas: con el arreglo desaparece la franja y
/// asoma una fila más de productos.
///
/// Para volver a comprobarlo de verdad: instalar en un Android 15 y mirar el
/// hueco entre el buscador y las pestañas.
void main() {
  final raiz = Directory.current.path;
  final shell = File('$raiz/lib/features/dashboard/dashboard_shell.dart').readAsStringSync();

  test('el shell no le pasa el inset inferior a las pantallas', () {
    // Quien toca el borde de abajo es la banda de navegación, y es la única que
    // debe reservar ese espacio. Si esta línea desaparece en un refactor, vuelve
    // la franja muerta en Android 15 y no se nota hasta abrir la app en un
    // teléfono moderno.
    expect(
      shell,
      contains('removeBottom: true'),
      reason: 'el shell volvió a pasarle el inset inferior a las pantallas',
    );
  });

  test('la banda de navegación sí lo reserva', () {
    // La otra mitad: quitar la reserva de más no puede llevarse también la que
    // hace falta. Las pestañas son lo último de la columna y tienen que quedar
    // por encima de la barra de gestos, o no se pueden tocar.
    expect(shell, contains('SafeArea('));
    expect(shell, contains('top: false'));
  });
}
