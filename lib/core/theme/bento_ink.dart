import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bento_theme.dart';

/// Cómo se dibuja el material del toque.
///
/// [grano] fue la primera versión: puntos dispersos que crecen. El usuario la
/// descartó por parecerse al ripple de Android Lollipop —esferas
/// dispersándose, lenguaje frutiger aero—, que no es el de una pieza de laca.
enum BentoToqueTextura {
  /// Puntos dispersos, como papel rugoso.
  grano,

  /// Tinta que se absorbe: relleno continuo que se disuelve hacia el borde.
  /// Es lo que se parece a laca — la superficie se humedece, no se salpica.
  mancha,

  /// Vetas radiales tenues, como el pincelado del barniz.
  veta,
}

/// Los parámetros ajustables del toque, juntos.
///
/// Existen como objeto —y no como constantes sueltas— para que el laboratorio
/// de `test_driver/lab_toque.dart` pueda probar variantes en vivo sin tocar
/// nada de producción: arma temas al vuelo con recetas distintas.
class BentoToqueReceta {
  const BentoToqueReceta({
    this.textura = BentoToqueTextura.mancha,
    this.duracion = bentoFeedbackTactilDuracion,
    this.opacidad = 0.5,
    this.fusion = 0.6,
    this.borde = 0.22,
    this.separacion = 0.22,
  });

  final BentoToqueTextura textura;

  /// Cuánto tarda la onda en cubrir el elemento. El desvanecido dura lo mismo
  /// y sostiene la opacidad durante su primer tercio.
  final Duration duracion;

  /// Opacidad máxima del relleno.
  final double opacidad;

  /// Qué parte del radio ocupa el degradado del borde. 0 deja un canto duro;
  /// 1 disuelve la mancha entera.
  final double fusion;

  /// Cuánta cresta lleva el frente de la onda. Es una diferencia de tono
  /// SUTIL, no un anillo dibujado: el borde tiene que dar impresión de fusión
  /// con el material, no de contorno.
  final double borde;

  /// Cuánto se aleja el tono del toque del color de reposo del elemento.
  /// 0 lo deja igual (invisible); 1 lo lleva al blanco puro sobre material
  /// oscuro y al negro puro sobre material claro.
  final double separacion;

  BentoToqueReceta copyWith({
    BentoToqueTextura? textura,
    Duration? duracion,
    double? opacidad,
    double? fusion,
    double? borde,
    double? separacion,
  }) => BentoToqueReceta(
    textura: textura ?? this.textura,
    duracion: duracion ?? this.duracion,
    opacidad: opacidad ?? this.opacidad,
    fusion: fusion ?? this.fusion,
    borde: borde ?? this.borde,
    separacion: separacion ?? this.separacion,
  );

  @override
  String toString() =>
      'BentoToqueReceta(textura: BentoToqueTextura.${textura.name}, '
      'duracion: Duration(milliseconds: ${duracion.inMilliseconds}), '
      'opacidad: ${opacidad.toStringAsFixed(2)}, '
      'fusion: ${fusion.toStringAsFixed(2)}, '
      'borde: ${borde.toStringAsFixed(2)}, '
      'separacion: ${separacion.toStringAsFixed(2)})';
}

/// Onda de toque de la app — ver docs/pantallas/prototipos-ascii.md#feedback-tactil.
///
/// Nace en el punto exacto de la presión, crece hasta cubrir el elemento y
/// desaparece. La duración es fija para cualquier tap de la app: es una señal
/// de contacto, no un indicador de progreso.
///
/// Pinta con el material del elemento, nunca con blanco: el relleno es el tono
/// del pozo separado de su reposo y el frente lleva un rastro de la cresta.
class BentoGrainSplash extends InteractiveInkFeature {
  BentoGrainSplash({
    required MaterialInkController controller,
    required super.referenceBox,
    required Offset position,
    required super.color,
    required this.colorCresta,
    required this.receta,
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
       super(controller: controller) {
    _radioControlador = AnimationController(duration: receta.duracion, vsync: controller.vsync)
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
    _alfaControlador = AnimationController(duration: receta.duracion, vsync: controller.vsync)
      ..addStatusListener(_alTerminarFade);
    // `Interval`: el primer tercio del desvanecido mantiene la opacidad. Es la
    // PAUSA que pidió el usuario — el elemento tocado termina de llenarse y se
    // deja ver lleno antes de apagarse. Sin ella el toque parecía un parpadeo.
    // Curva primero y tween después, siempre (ver el comentario del radio).
    _alfa = _alfaControlador.drive(
      Tween<double>(
        begin: receta.opacidad,
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

  final BentoToqueReceta receta;

  final Offset _position;
  final BorderRadius _borderRadius;
  final TextDirection _textDirection;
  final RectCallback? _clipCallback;
  final double _targetRadius;

  late final AnimationController _radioControlador;
  late final Animation<double> _radio;
  late final AnimationController _alfaControlador;
  late final Animation<double> _alfa;

  /// La fábrica lleva los colores y la receta porque `create` no recibe un
  /// `BuildContext` y la laca vive en una extensión de tema. Se arma una vez,
  /// al construir el tema, donde la laca sí está a mano.
  static InteractiveInkFeatureFactory factoriaDe({
    required Color relleno,
    required Color cresta,
    BentoToqueReceta receta = const BentoToqueReceta(),
  }) => _BentoGrainSplashFactory(relleno: relleno, cresta: cresta, receta: receta);

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
    final opacidad = _alfa.value;
    if (radio <= 0 || opacidad <= 0) return;

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

    final area = Rect.fromCircle(center: _position, radius: radio);
    canvas.save();
    canvas.clipPath(Path()..addOval(area));

    switch (receta.textura) {
      case BentoToqueTextura.grano:
        _pintarGrano(canvas, radio, opacidad);
      case BentoToqueTextura.mancha:
        _pintarMancha(canvas, area, opacidad);
      case BentoToqueTextura.veta:
        _pintarVeta(canvas, area, radio, opacidad);
    }
    _pintarFrente(canvas, area, opacidad);

    canvas.restore();
    canvas.restore();
  }

  /// El frente NO es un anillo dibujado: es un rastro de cresta que aparece
  /// solo en la última franja del radio y se disuelve hacia dentro. Un stroke
  /// de 1px opaco leía como contorno, y lo que se busca es fusión con el
  /// material.
  void _pintarFrente(Canvas canvas, Rect area, double opacidad) {
    if (receta.borde <= 0) return;
    canvas.drawCircle(
      area.center,
      area.width / 2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colorCresta.withValues(alpha: 0),
            colorCresta.withValues(alpha: opacidad * receta.borde),
          ],
          stops: const [0.82, 1],
        ).createShader(area),
    );
  }

  void _pintarMancha(Canvas canvas, Rect area, double opacidad) {
    canvas.drawCircle(
      area.center,
      area.width / 2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacidad),
            color.withValues(alpha: opacidad),
            color.withValues(alpha: 0),
          ],
          stops: [0, (1 - receta.fusion).clamp(0.0, 1.0), 1],
        ).createShader(area),
    );
  }

  void _pintarVeta(Canvas canvas, Rect area, double radio, double opacidad) {
    _pintarMancha(canvas, area, opacidad * 0.7);
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, radio * 0.05)
      ..color = color.withValues(alpha: opacidad * 0.35);
    for (final angulo in _vetas) {
      final direccion = Offset(math.cos(angulo), math.sin(angulo));
      canvas.drawLine(
        area.center + direccion * (radio * 0.15),
        area.center + direccion * radio,
        pincel,
      );
    }
  }

  void _pintarGrano(Canvas canvas, double radio, double opacidad) {
    canvas.drawCircle(_position, radio, Paint()..color = color.withValues(alpha: opacidad * 0.35));
    final granoPaint = Paint();
    for (final grano in _granos) {
      final centro = _position + Offset(grano.dx, grano.dy) * radio;
      granoPaint.color = color.withValues(alpha: opacidad * grano.intensidad);
      canvas.drawCircle(centro, grano.tamano * radio, granoPaint);
    }
  }

  /// Precalculados una sola vez para toda la app (no por instancia), con
  /// semilla fija: la textura tiene que ser la misma en cada ejecución, no
  /// aleatoria en cada tap.
  static final List<_Grano> _granos = _generarGranos(math.Random(20260728), 140);
  static final List<double> _vetas = _generarVetas(math.Random(20260730), 14);

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

  static List<double> _generarVetas(math.Random rng, int cantidad) =>
      List.generate(cantidad, (_) => rng.nextDouble() * 2 * math.pi);
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
  const _BentoGrainSplashFactory({
    required this.relleno,
    required this.cresta,
    required this.receta,
  });

  final Color relleno;
  final Color cresta;
  final BentoToqueReceta receta;

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
      receta: receta,
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
