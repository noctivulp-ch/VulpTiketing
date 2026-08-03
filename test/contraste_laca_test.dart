import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';

/// Blinda los numeros de contraste de DESIGN.md contra una edicion futura que
/// "mejore" un color y degrade la legibilidad sin que nadie lo note. Recalcula
/// la formula WCAG sobre el tema REALMENTE construido (no sobre constantes
/// sueltas), en los 3 acabados de laca x los 2 modos.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final alto = la > lb ? la : lb;
  final bajo = la > lb ? lb : la;
  return (alto + 0.05) / (bajo + 0.05);
}

void main() {
  for (final acento in AcentoTinte.values) {
    for (final brillo in Brightness.values) {
      final etiqueta = '${acento.name} / ${brillo.name}';

      test('contraste de texto cumple AA en $etiqueta', () {
        final tema = buildBentoTheme(acento, brightness: brillo);
        final scheme = tema.colorScheme;
        final laca = tema.extension<BentoLaca>()!;

        final paresDeTexto = {
          'texto principal en pozo': (scheme.onSurface, scheme.surface),
          'texto secundario en pozo': (scheme.onSurfaceVariant, scheme.surface),
          'texto sobre acento': (scheme.onPrimary, scheme.primary),
          'texto sobre bandeja': (laca.textoEnBandeja, laca.bandeja),
          'texto atenuado sobre bandeja': (laca.textoAtenuadoEnBandeja, laca.bandeja),
          'texto sobre error': (scheme.onError, scheme.error),
        };

        paresDeTexto.forEach((nombre, par) {
          final ratio = _contraste(par.$1, par.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$nombre en $etiqueta: ${ratio.toStringAsFixed(2)}:1',
          );
        });
      });

      test('el ribete esta apagado respecto al acento en $etiqueta', () {
        // El ribete es el metal apagado: nunca el acento a plena fuerza, porque
        // entonces la seleccion no tendria con que destacar.
        final tema = buildBentoTheme(acento, brightness: brillo);
        final laca = tema.extension<BentoLaca>()!;
        expect(
          laca.paredCresta,
          isNot(equals(tema.colorScheme.primary)),
          reason: 'el ribete no puede ser el acento a plena fuerza en $etiqueta',
        );
      });

      test('la cresta de pared cumple 3:1 contra su bandeja en $etiqueta', () {
        // Senal PRIMARIA de tallado (DESIGN.md, regla 1): es lo unico que
        // funciona en modo oscuro, donde bandeja/pozo no puede llegar a 3:1.
        // Umbral 3:1 = WCAG 1.4.11, contraste de elementos no textuales.
        final tema = buildBentoTheme(acento, brightness: brillo);
        final laca = tema.extension<BentoLaca>()!;

        final ratio = _contraste(laca.paredCresta, laca.bandeja);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: 'cresta vs bandeja en $etiqueta: ${ratio.toStringAsFixed(2)}:1',
        );
      });

      test('el pozo nunca es mas oscuro que la bandeja en $etiqueta', () {
        // Un hueco tallado se lee como hueco, no como una tarjeta encima: el
        // pozo se distingue del marco, y la escalera de contenedores de M3
        // queda aplanada para que ningun widget derive hacia "mas claro =
        // mas elevado" (DESIGN.md, regla 5).
        final tema = buildBentoTheme(acento, brightness: brillo);
        final laca = tema.extension<BentoLaca>()!;
        final scheme = tema.colorScheme;

        expect(laca.pozo, equals(scheme.surface));
        expect(scheme.surfaceContainerHighest, equals(scheme.surface));
        expect(scheme.surfaceContainerLow, equals(scheme.surface));
        expect(
          _contraste(laca.pozo, laca.bandeja),
          greaterThan(1.2),
          reason: 'bandeja y pozo tienen que distinguirse en $etiqueta',
        );
      });
    }
  }

  // La propiedad que motivo este cambio: elegir otro metal tiene que cambiar el
  // ribete de TODOS los pozos, no solo el del elemento seleccionado. Con un
  // borde de tono fijo, elegir peltre dejaba el resto leyendose dorado.
  for (final brillo in Brightness.values) {
    test('cambiar de metal cambia el ribete de los pozos en ${brillo.name}', () {
      final ribetes = {
        for (final acento in AcentoTinte.values)
          acento: buildBentoTheme(acento, brightness: brillo).extension<BentoLaca>()!.paredCresta,
      };

      expect(
        ribetes.values.toSet().length,
        equals(AcentoTinte.values.length),
        reason: 'cada metal debe dar un ribete distinto en ${brillo.name}: $ribetes',
      );
    });
  }

  // Que cada acento dé un ribete DISTINTO no basta: cobre y oro daban dos
  // colores distintos que a simple vista eran el mismo marrón anaranjado, o sea
  // que el ajuste ofrecía tres opciones y entregaba dos. Por eso cobre pasó a
  // jade, y por eso esto se mide en vez de confiar en el ojo.
  for (final brillo in Brightness.values) {
    test('los acentos se distinguen entre sí en ${brillo.name}', () {
      final acentos = {
        for (final acento in AcentoTinte.values)
          acento: buildBentoTheme(acento, brightness: brillo).colorScheme.primary,
      };

      for (final a in AcentoTinte.values) {
        for (final b in AcentoTinte.values) {
          if (a.index >= b.index) continue;
          expect(
            _distanciaPercibida(acentos[a]!, acentos[b]!),
            greaterThan(40),
            reason: '${a.name} y ${b.name} se parecen demasiado en ${brillo.name}',
          );
        }
      }
    });
  }
}

/// Distancia de color "redmean": la aproximación barata a la percepción humana
/// que pondera el verde por encima del azul. Suficiente para lo que se pregunta
/// acá —¿son dos colores o el mismo dos veces?— sin traerse una conversión a
/// CIELAB.
double _distanciaPercibida(Color x, Color y) {
  final rx = (x.r * 255).round();
  final ry = (y.r * 255).round();
  final rMedia = (rx + ry) / 2;
  final dr = rx - ry;
  final dg = (x.g - y.g) * 255;
  final db = (x.b - y.b) * 255;
  return math.sqrt(
    (2 + rMedia / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rMedia) / 256) * db * db,
  );
}
