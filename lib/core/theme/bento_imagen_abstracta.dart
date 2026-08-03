import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bento_theme.dart';

/// Una figura abstracta, distinta para cada producto y siempre la misma.
///
/// Reemplaza al icono de "sin imagen" repetido cientos de veces: en una lista de
/// treinta y nueve productos, treinta y nueve iconos idénticos no ayudan a
/// encontrar nada — son ruido con forma de dato. Una figura propia por producto
/// sí: se reconoce por el rabillo del ojo antes de leer el nombre, que es como
/// se busca en una lista larga.
///
/// **Se dibuja, no se guarda.** No hay archivo, ni asset, ni nada que
/// sincronizar o respaldar: la figura sale de la [semilla] —el id del producto—
/// así que es la misma en todos los aparatos sin que nadie la copie. Un icono
/// vectorial por producto habría sido lo mismo con archivos de por medio.
///
/// Los colores salen de la laca del tema, así que sigue al modo claro/oscuro y
/// al acento elegido sin repintar nada.
class BentoImagenAbstracta extends StatelessWidget {
  const BentoImagenAbstracta({super.key, required this.semilla, this.apagada = false});

  /// Lo que decide la figura. El id del producto, no su nombre: renombrar un
  /// producto no debería cambiarle la cara.
  final String semilla;

  /// Para lo que está fuera de la carta: la misma figura, sin fuerza.
  final bool apagada;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final acento = Theme.of(context).colorScheme.primary;

    return CustomPaint(
      painter: _PintorAbstracto(
        semilla: semilla.hashCode,
        fondo: laca.pozoContacto,
        trazo: apagada ? laca.textoAtenuadoEnBandeja : acento,
        opacidad: apagada ? 0.35 : 0.85,
      ),
      // Ocupa lo que le den: la miniatura del catálogo y la vista previa del
      // formulario son la misma figura a distinto tamaño.
      child: const SizedBox.expand(),
    );
  }
}

class _PintorAbstracto extends CustomPainter {
  const _PintorAbstracto({
    required this.semilla,
    required this.fondo,
    required this.trazo,
    required this.opacidad,
  });

  final int semilla;
  final Color fondo;
  final Color trazo;
  final double opacidad;

  @override
  void paint(Canvas canvas, Size size) {
    // `Random` con semilla: mismo producto, misma figura, siempre. Sin esto la
    // lista cambiaría de cara en cada scroll.
    final rng = math.Random(semilla);
    final lado = math.min(size.width, size.height);

    canvas.drawRect(Offset.zero & size, Paint()..color = fondo);

    // Tres formas y no una: con una sola, dos productos con semillas parecidas
    // se ven casi igual. Con tres, la combinación separa.
    final formas = 3;
    for (var i = 0; i < formas; i++) {
      final pincel = Paint()
        ..color = trazo.withValues(alpha: opacidad * (0.35 + 0.25 * i))
        ..style = rng.nextBool() ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = lado * 0.06;

      final centro = Offset(
        size.width * (0.25 + rng.nextDouble() * 0.5),
        size.height * (0.25 + rng.nextDouble() * 0.5),
      );
      final radio = lado * (0.14 + rng.nextDouble() * 0.18);

      switch (rng.nextInt(3)) {
        case 0:
          canvas.drawCircle(centro, radio, pincel);
        case 1:
          // Rectángulo con las esquinas del sistema: la figura tiene que
          // pertenecer a la misma familia visual que los pozos.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: centro, width: radio * 2, height: radio * 1.6),
              Radius.circular(lado * 0.08),
            ),
            pincel,
          );
        default:
          final camino = Path()
            ..moveTo(centro.dx, centro.dy - radio)
            ..lineTo(centro.dx + radio, centro.dy + radio)
            ..lineTo(centro.dx - radio, centro.dy + radio)
            ..close();
          canvas.drawPath(camino, pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_PintorAbstracto anterior) =>
      anterior.semilla != semilla ||
      anterior.fondo != fondo ||
      anterior.trazo != trazo ||
      anterior.opacidad != opacidad;
}
