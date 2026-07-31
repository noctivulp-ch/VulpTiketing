import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bento_theme.dart';

/// Ripple con textura granulada (simil papel rugoso) — ver
/// docs/pantallas/prototipos-ascii.md#feedback-tactil. El `InkWell` estandar
/// de Flutter (`InkSplash`/`InkRipple`) pinta un circulo liso; esta clase
/// pinta el mismo circulo creciente pero relleno de "granos" (puntos
/// pequenos de opacidad variable) en vez de un solido uniforme.
///
/// Nace en el punto exacto de la presion, crece hasta cubrir el elemento y
/// desaparece — duracion fija y corta ([bentoFeedbackTactilDuracion]), igual
/// para cualquier tap en toda la app (no depende de cuanto se mantenga
/// presionado: es una senal de contacto, no un indicador de progreso).
class BentoGrainSplash extends InteractiveInkFeature {
  BentoGrainSplash({
    required MaterialInkController controller,
    required super.referenceBox,
    required Offset position,
    required Color color,
    required this.colorCresta,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    super.customBorder,
    double? radius,
    super.onRemoved,
  }) : _position = position,
       _borderRadius = borderRadius ?? BorderRadius.zero,
       // ignore: prefer_initializing_formals
       _textDirection = textDirection,
       _clipCallback = containedInkWell
           ? (rectCallback ?? (() => Offset.zero & referenceBox.size))
           : null,
       _targetRadius =
           radius ?? _radioObjetivo(referenceBox, containedInkWell, rectCallback, position),
       super(controller: controller, color: color) {
    _radioControlador =
        AnimationController(duration: bentoFeedbackTactilDuracion, vsync: controller.vsync)
          ..addListener(controller.markNeedsPaint)
          ..forward();
    // `a.chain(b)` evalúa PRIMERO `b` y después `a`. Estaba al revés: el
    // `Tween` convertía el 0..1 del controlador en un radio en píxeles (274,
    // por ejemplo) y recién entonces se lo pasaba a la curva, que solo acepta
    // 0..1. Cada toque disparaba
    // `parametric value 274.0 is outside of [0, 1] range`, la excepción caía
    // DURANTE EL PINTADO y el frame se perdía: la pantalla entera quedaba en
    // blanco unos fotogramas. Ese era el parpadeo al seleccionar productos.
    //
    // El orden correcto es curva primero (0..1 → 0..1 con easing) y después el
    // tween al radio.
    _radio = _radioControlador.drive(
      Tween<double>(begin: 0, end: _targetRadius).chain(CurveTween(curve: Curves.easeOut)),
    );
    _alfaControlador = AnimationController(
      duration: bentoFeedbackTactilDuracion,
      vsync: controller.vsync,
    )..addStatusListener(_alTerminarFade);
    // `Interval`: el primer tercio del desvanecido mantiene la opacidad. Es la
    // PAUSA que pidió el usuario — el elemento tocado termina de llenarse y se
    // deja ver lleno antes de apagarse. Sin ella el toque parecía un parpadeo.
    // Curva primero y tween después, siempre (ver el comentario del radio).
    _alfa = _alfaControlador.drive(
      IntTween(
        begin: (color.a * 255.0).round(),
        end: 0,
      ).chain(CurveTween(curve: const Interval(0.35, 1, curve: Curves.easeIn))),
    );
    _radioControlador.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _alfaControlador
          ..addListener(controller.markNeedsPaint)
          ..forward();
      }
    });
    controller.addInkFeature(this);
  }

  /// El metal que ribetea el borde del elemento tocado.
  final Color colorCresta;

  final Offset _position;
  final BorderRadius _borderRadius;
  final TextDirection _textDirection;
  final RectCallback? _clipCallback;
  final double _targetRadius;

  late final AnimationController _radioControlador;
  late final Animation<double> _radio;
  late final AnimationController _alfaControlador;
  late final Animation<int> _alfa;

  /// La fábrica lleva los colores porque `create` no recibe un `BuildContext`
  /// y la laca vive en una extensión de tema. Se arma una vez, al construir el
  /// tema, donde la laca sí está a mano.
  static InteractiveInkFeatureFactory factoriaDe({required Color relleno, required Color cresta}) =>
      _BentoGrainSplashFactory(relleno: relleno, cresta: cresta);

  static double _radioObjetivo(
    RenderBox referenceBox,
    bool containedInkWell,
    RectCallback? rectCallback,
    Offset position,
  ) {
    if (!containedInkWell) return Material.defaultSplashRadius;
    final size = rectCallback != null ? rectCallback().size : referenceBox.size;
    final esquinas = [
      (position - Offset.zero).distance,
      (position - Offset(size.width, 0)).distance,
      (position - Offset(0, size.height)).distance,
      (position - Offset(size.width, size.height)).distance,
    ];
    return esquinas.reduce(math.max).ceilToDouble();
  }

  void _alTerminarFade(AnimationStatus status) {
    if (status == AnimationStatus.completed) dispose();
  }

  @override
  void confirm() {}

  @override
  void cancel() {}

  @override
  void dispose() {
    _radioControlador.dispose();
    _alfaControlador.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final radio = _radio.value;
    if (radio <= 0) return;

    final origenOffset = MatrixUtils.getAsTranslation(transform);
    canvas.save();
    if (origenOffset == null) {
      canvas.transform(transform.storage);
    } else {
      canvas.translate(origenOffset.dx, origenOffset.dy);
    }
    if (_clipCallback != null) {
      final rect = _clipCallback();
      if (customBorder != null) {
        canvas.clipPath(customBorder!.getOuterPath(rect, textDirection: _textDirection));
      } else if (_borderRadius != BorderRadius.zero) {
        canvas.clipRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: _borderRadius.topLeft,
            topRight: _borderRadius.topRight,
            bottomLeft: _borderRadius.bottomLeft,
            bottomRight: _borderRadius.bottomRight,
          ),
        );
      } else {
        canvas.clipRect(rect);
      }
    }

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: _position, radius: radio)));
    final colorConAlfa = color.withAlpha(_alfa.value);
    canvas.drawCircle(
      _position,
      radio,
      Paint()..color = colorConAlfa.withAlpha((_alfa.value * 0.35).round()),
    );
    final granoPaint = Paint()..color = colorConAlfa;
    for (final grano in _granos) {
      final centro = _position + Offset(grano.dx, grano.dy) * radio;
      granoPaint.color = colorConAlfa.withAlpha((_alfa.value * grano.intensidad).round());
      canvas.drawCircle(centro, grano.tamano * radio, granoPaint);
    }
    // El frente de la onda lleva LA CRESTA del elemento, el mismo metal que
    // ribetea su borde. Es lo que hace que el toque se lea como parte de la
    // pieza y no como una capa blanca encima.
    canvas.drawCircle(
      _position,
      radio,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colorCresta.withAlpha((_alfa.value * 0.9).round()),
    );
    canvas.restore();
    canvas.restore();
  }

  /// Granos precalculados una sola vez para toda la app (no por instancia de
  /// ripple): posicion dentro del circulo unitario, tamano relativo al radio
  /// y variacion de intensidad — es lo que da la textura de "papel rugoso"
  /// en vez de un circulo solido. Semilla fija: la textura debe ser
  /// consistente entre ejecuciones, no aleatoria en cada tap.
  static final List<_Grano> _granos = _generarGranos(math.Random(20260728), 140);

  static List<_Grano> _generarGranos(math.Random rng, int cantidad) {
    return List.generate(cantidad, (_) {
      final angulo = rng.nextDouble() * 2 * math.pi;
      // sqrt para distribucion uniforme en el area del circulo, no
      // concentrada en el centro.
      final distancia = math.sqrt(rng.nextDouble());
      return _Grano(
        dx: math.cos(angulo) * distancia,
        dy: math.sin(angulo) * distancia,
        tamano: 0.015 + rng.nextDouble() * 0.02,
        intensidad: 0.35 + rng.nextDouble() * 0.65,
      );
    });
  }
}

class _Grano {
  const _Grano({
    required this.dx,
    required this.dy,
    required this.tamano,
    required this.intensidad,
  });

  final double dx;
  final double dy;
  final double tamano;
  final double intensidad;
}

class _BentoGrainSplashFactory extends InteractiveInkFeatureFactory {
  const _BentoGrainSplashFactory({required this.relleno, required this.cresta});

  final Color relleno;
  final Color cresta;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return BentoGrainSplash(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      // El color del tema manda sobre el que pida cada widget: el toque es un
      // material de la app, no un detalle de cada botón.
      color: relleno,
      colorCresta: cresta,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }
}
