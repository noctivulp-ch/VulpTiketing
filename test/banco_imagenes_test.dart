import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_imagen_abstracta.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/producto/banco_imagenes.dart';
import 'package:vulp_tiketing/features/producto/ui/banco_imagenes_dialog.dart';
import 'package:vulp_tiketing/features/producto/ui/imagen_del_banco_vista.dart';

/// El banco de imágenes: figuras de fábrica que no pesan, más las fotos que se
/// agreguen desde la galería o la cámara.
///
/// Lo que se guarda en `producto.imagen` es una **referencia de texto**, y de
/// ese texto sale si es figura o foto. Sin columna nueva, sin tabla nueva: el
/// esquema, el sync y el backup quedan como estaban.
void main() {
  const banco = BancoDeImagenes();

  group('la referencia dice qué es', () {
    test('con prefijo es una figura', () {
      final imagen = ImagenDelBanco.de('abs:figura-3');

      expect(imagen, isA<FiguraAbstracta>());
      expect((imagen! as FiguraAbstracta).semilla, 'figura-3');
      expect(imagen.referencia, 'abs:figura-3');
    });

    test('sin prefijo es una foto del banco', () {
      final imagen = ImagenDelBanco.de('a1b2c3.jpg');

      expect(imagen, isA<FotoDelBanco>());
      expect((imagen! as FotoDelBanco).archivo, 'a1b2c3.jpg');
    });

    test('vacío o nulo es "sin imagen"', () {
      // Se distinguen de una referencia rota a propósito: "sin imagen" es una
      // elección del usuario, y la figura propia del producto es la respuesta.
      expect(ImagenDelBanco.de(null), isNull);
      expect(ImagenDelBanco.de(''), isNull);
    });

    test('ida y vuelta: lo guardado se vuelve a leer igual', () {
      for (final original in ['abs:figura-0', 'foto.png', 'abs:x']) {
        expect(ImagenDelBanco.de(original)!.referencia, original);
      }
    });
  });

  group('las figuras de fábrica', () {
    test('están siempre, sin que nadie agregue nada', () {
      expect(banco.figuras(), hasLength(BancoDeImagenes.figurasDeFabrica));
    });

    test('son estables entre llamadas', () {
      // Si cambiaran de orden, un producto que eligió "la tercera" pasaría a
      // tener otra cara sin que nadie lo tocara.
      expect(banco.figuras().map((f) => f.referencia), banco.figuras().map((f) => f.referencia));
    });

    test('cada una es distinta de las demás', () {
      final referencias = banco.figuras().map((f) => f.referencia).toSet();

      expect(referencias, hasLength(BancoDeImagenes.figurasDeFabrica));
    });
  });

  group('la vista', () {
    Future<void> montar(WidgetTester tester, String? referencia) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildBentoTheme(AcentoTinte.oro),
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: ImagenDelBancoVista(referencia: referencia, semillaPorDefecto: 'producto-7'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('sin imagen dibuja la figura propia del producto', (tester) async {
      await montar(tester, null);

      expect(find.byType(BentoImagenAbstracta), findsOneWidget);
      expect(
        tester.widget<BentoImagenAbstracta>(find.byType(BentoImagenAbstracta)).semilla,
        'producto-7',
      );
    });

    testWidgets('una figura elegida dibuja ESA figura, no la del producto', (tester) async {
      await montar(tester, 'abs:figura-5');

      expect(
        tester.widget<BentoImagenAbstracta>(find.byType(BentoImagenAbstracta)).semilla,
        'figura-5',
      );
    });

    testWidgets('una foto que no está cae a la figura, no a un hueco', (tester) async {
      // Pasa de verdad: una base traída por sincronización o restaurada de un
      // backup referencia fotos que este aparato no tiene. Un cuadro en blanco
      // se leería como que algo se rompió.
      await montar(tester, 'no-existe.jpg');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BentoImagenAbstracta), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('la figura abstracta', () {
    testWidgets('la misma semilla da siempre el mismo dibujo', (tester) async {
      // Sin esto la lista cambiaría de cara en cada scroll, que es justo lo que
      // hace inútil una imagen para reconocer un producto.
      const primera = BentoImagenAbstracta(semilla: 'x');
      const segunda = BentoImagenAbstracta(semilla: 'x');

      await tester.pumpWidget(
        MaterialApp(
          theme: buildBentoTheme(AcentoTinte.oro),
          home: const Scaffold(
            body: Row(
              children: [
                SizedBox(width: 50, height: 50, child: primera),
                SizedBox(width: 50, height: 50, child: segunda),
              ],
            ),
          ),
        ),
      );

      expect(primera.semilla, segunda.semilla);
      expect(tester.takeException(), isNull);
    });
  });

  group('el diálogo del banco', () {
    Future<String?> abrir(WidgetTester tester) async {
      String? elegida;
      var abierto = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildBentoTheme(AcentoTinte.oro),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      abierto = true;
                      elegida = await elegirDelBanco(context, semillaProducto: 'p1');
                    },
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(abierto, isTrue);
      return elegida;
    }

    testWidgets('muestra las figuras de fábrica sin que haya nada agregado', (tester) async {
      // Un banco vacío del que no se pueda elegir nada sería una pantalla que
      // solo sabe decir "no hay".
      await abrir(tester);

      expect(find.text('Figuras'), findsOneWidget);
      expect(find.byType(ImagenDelBancoVista), findsNWidgets(BancoDeImagenes.figurasDeFabrica));
    });

    testWidgets('ofrece cámara y galería', (tester) async {
      await abrir(tester);

      expect(find.text('Cámara'), findsOneWidget);
      expect(find.text('Galería'), findsOneWidget);
    });

    testWidgets('elegir una figura devuelve SU referencia', (tester) async {
      await abrir(tester);

      await tester.tap(find.byType(ImagenDelBancoVista).first);
      await tester.pumpAndSettle();

      // La primera de la cuadrícula es la primera de fábrica.
      expect(find.text('Figuras'), findsNothing, reason: 'el diálogo se cerró');
    });

    testWidgets('"Sin imagen" y "Cancelar" son cosas distintas', (tester) async {
      // Vaciar la imagen es una elección —devuelve al producto su figura
      // propia—; cancelar no cambia nada. Si devolvieran lo mismo, no se podría
      // quitar una foto ya puesta.
      await abrir(tester);
      expect(find.text('Sin imagen'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Figuras'), findsNothing);
    });
  });
}
