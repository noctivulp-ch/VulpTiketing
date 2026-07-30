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
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$nombre en $etiqueta: ${ratio.toStringAsFixed(2)}:1');
        });
      });

      test('la cresta de pared cumple 3:1 contra su bandeja en $etiqueta', () {
        // Senal PRIMARIA de tallado (DESIGN.md, regla 1): es lo unico que
        // funciona en modo oscuro, donde bandeja/pozo no puede llegar a 3:1.
        // Umbral 3:1 = WCAG 1.4.11, contraste de elementos no textuales.
        final tema = buildBentoTheme(acento, brightness: brillo);
        final laca = tema.extension<BentoLaca>()!;

        final ratio = _contraste(laca.paredCresta, laca.bandeja);
        expect(ratio, greaterThanOrEqualTo(3.0), reason: 'cresta vs bandeja en $etiqueta: ${ratio.toStringAsFixed(2)}:1');
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
}
