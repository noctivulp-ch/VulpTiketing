import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/core/ui/bento_enlace.dart';

/// Un enlace se tiene que ver como un enlace.
///
/// Lo pidió el dueño después de ver la firma sin decoración: un texto que hace
/// algo al tocarlo y no lo anuncia no es discreto, es indescifrable — nadie va a
/// tocar un nombre a ver qué pasa.
///
/// Color del acento **y** subrayado, las dos cosas. El color solo no basta: quien
/// no distingue ese tono ve texto normal, y el subrayado es la pista que no
/// depende del color.
void main() {
  Future<void> montar(
    WidgetTester tester, {
    AcentoTinte acento = AcentoTinte.oro,
    Brightness brillo = Brightness.dark,
    Future<bool> Function()? onAbrir,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(acento, brightness: brillo),
        home: Scaffold(
          body: BentoEnlace(
            texto: 'Hecho por NoctiVulp',
            url: 'https://patreon.com/NoctiVulp',
            onAbrir: onAbrir ?? () async => true,
            descripcion: 'Hecho por NoctiVulp — abre la página del autor',
          ),
        ),
      ),
    );
    // `pumpAndSettle` y no `pump`: `MaterialApp` envuelve el tema en un
    // `AnimatedTheme`, así que un solo frame después de cambiar el tinte todavía
    // devuelve el color anterior. Costó una prueba que decía que el enlace no
    // seguía al acento.
    await tester.pumpAndSettle();
  }

  TextStyle estiloDelEnlace(WidgetTester tester) =>
      tester.widget<Text>(find.text('Hecho por NoctiVulp')).style!;

  testWidgets('va subrayado', (tester) async {
    await montar(tester);

    expect(estiloDelEnlace(tester).decoration, TextDecoration.underline);
  });

  testWidgets('va en el color del acento, y el subrayado en el mismo color', (tester) async {
    await montar(tester);

    final contexto = tester.element(find.text('Hecho por NoctiVulp'));
    final acento = Theme.of(contexto).colorScheme.primary;
    final estilo = estiloDelEnlace(tester);

    expect(estilo.color, acento);
    // Sin `decorationColor` explícito la línea sale del color por defecto y no
    // del texto: se ve una raya de otro tono debajo.
    expect(estilo.decorationColor, acento);
  });

  testWidgets('el color cambia con el tinte elegido', (tester) async {
    // El acento es una preferencia por aparato (0020): el enlace tiene que seguir
    // al tinte puesto, no llevar un color fijo.
    final colores = <Color?>[];
    for (final acento in AcentoTinte.values) {
      await montar(tester, acento: acento);
      colores.add(estiloDelEnlace(tester).color);
    }

    expect(colores.toSet(), hasLength(AcentoTinte.values.length));
  });

  testWidgets('el objetivo táctil llega a 48 dp', (tester) async {
    // Una línea de texto pequeño mide ~16 dp y eso no se acierta con el dedo.
    await montar(tester);

    expect(tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('se anuncia como enlace con lector de pantalla', (tester) async {
    final semantica = tester.ensureSemantics();
    await montar(tester);

    expect(find.bySemanticsLabel('Hecho por NoctiVulp — abre la página del autor'), findsOneWidget);
    semantica.dispose();
  });

  testWidgets('si no se puede abrir, la dirección queda copiada', (tester) async {
    // El toque tiene que servir para algo: un "no se pudo" a secas deja al
    // usuario sin nada que hacer.
    final portapapeles = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      llamada,
    ) async {
      if (llamada.method == 'Clipboard.setData') {
        portapapeles.add((llamada.arguments as Map)['text'] as String);
      }
      return null;
    });

    await montar(tester, onAbrir: () async => false);
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(portapapeles, ['https://patreon.com/NoctiVulp']);
  });

  testWidgets('si se abre bien, no se copia nada', (tester) async {
    final portapapeles = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      llamada,
    ) async {
      if (llamada.method == 'Clipboard.setData') portapapeles.add('algo');
      return null;
    });

    await montar(tester, onAbrir: () async => true);
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(portapapeles, isEmpty);
  });
}
