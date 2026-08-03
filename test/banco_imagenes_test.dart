import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_icono_producto.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/producto/banco_imagenes.dart';
import 'package:vulp_tiketing/features/producto/ui/banco_imagenes_dialog.dart';
import 'package:vulp_tiketing/features/producto/ui/imagen_del_banco_vista.dart';

/// El banco de imágenes: iconos de la casa que no pesan, más las fotos que se
/// agreguen desde la galería o la cámara.
///
/// Lo que se guarda en `producto.imagen` es una **referencia de texto**, y de
/// ese texto sale si es icono o foto. Sin columna nueva, sin tabla nueva: el
/// esquema, el sync y el backup quedan como estaban.
void main() {
  const banco = BancoDeImagenes();

  group('la referencia dice qué es', () {
    test('con prefijo es un icono', () {
      final imagen = ImagenDelBanco.de('ico:cafe');

      expect(imagen, isA<IconoDelBanco>());
      expect((imagen! as IconoDelBanco).clave, 'cafe');
      expect(imagen.referencia, 'ico:cafe');
    });

    test('sin prefijo es una foto del banco', () {
      final imagen = ImagenDelBanco.de('a1b2c3.jpg');

      expect(imagen, isA<FotoDelBanco>());
      expect((imagen! as FotoDelBanco).archivo, 'a1b2c3.jpg');
    });

    test('vacío o nulo es "sin imagen"', () {
      // Se distinguen de una referencia rota a propósito: "sin imagen" es una
      // elección del usuario, y en Venta Rápida decide si se reserva el hueco.
      expect(ImagenDelBanco.de(null), isNull);
      expect(ImagenDelBanco.de(''), isNull);
    });

    test('ida y vuelta: lo guardado se vuelve a leer igual', () {
      for (final original in ['ico:cafe', 'foto.png', 'ico:postre']) {
        expect(ImagenDelBanco.de(original)!.referencia, original);
      }
    });

    test('las referencias de las figuras viejas se siguen entendiendo', () {
      // El aparato ya tiene productos guardados con `abs:`. Dejar de leerlo les
      // borraría la imagen a todos de golpe, que es justo lo que no puede pasar
      // al cambiar de figuras a iconos.
      final imagen = ImagenDelBanco.de('abs:figura-3');

      expect(imagen, isA<IconoDelBanco>());
      expect((imagen! as IconoDelBanco).clave, 'figura-3');
    });

    test('pero lo que se escribe es siempre el prefijo nuevo', () {
      expect(const IconoDelBanco('cafe').referencia, startsWith(IconoDelBanco.prefijo));
    });
  });

  group('los iconos de la casa', () {
    test('están siempre, sin que nadie agregue nada', () {
      expect(banco.iconos(), hasLength(banco.iconosDeFabrica));
      expect(banco.iconos(), isNotEmpty);
    });

    test('son estables entre llamadas', () {
      // Si cambiaran de orden, un producto que eligió "café" pasaría a tener
      // otra cara sin que nadie lo tocara.
      expect(banco.iconos().map((i) => i.referencia), banco.iconos().map((i) => i.referencia));
    });

    test('cada clave es distinta de las demás', () {
      expect(banco.iconos().map((i) => i.clave).toSet(), hasLength(banco.iconosDeFabrica));
    });

    test('cada uno tiene etiqueta y dibujo propios', () {
      // Sin etiqueta, veinte iconos juntos en el diálogo se parecen entre sí
      // más de lo que uno cree; con el mismo dibujo repetido no distinguirían
      // nada en la carta.
      final dibujos = <IconData>{};
      for (final icono in banco.iconos()) {
        final definicion = iconoDeProductoDe(icono.clave);
        expect(definicion.etiqueta, isNotEmpty);
        dibujos.add(definicion.icono);
      }
      expect(dibujos, hasLength(banco.iconosDeFabrica));
    });

    test('una clave desconocida cae al neutro, no revienta', () {
      expect(iconoDeProductoDe('lo-que-sea').clave, iconoDeProductoPorDefecto.clave);
    });

    test('las figuras viejas se reparten por el catálogo, no se amontonan', () {
      // Conservar que sean DISTINTAS entre sí es lo que daban aquellas figuras;
      // mandarlas todas al icono neutro se vería como que se perdió lo elegido.
      final repartidas = {for (var i = 0; i < 12; i++) iconoDeProductoDe('figura-$i').clave};

      expect(repartidas.length, greaterThan(1));
      expect(repartidas, isNot(contains(iconoDeProductoPorDefecto.clave)));
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
                child: ImagenDelBancoVista(referencia: referencia, ventana: null),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('un icono elegido dibuja ESE icono', (tester) async {
      await montar(tester, 'ico:cafe');

      expect(tester.widget<BentoIconoProducto>(find.byType(BentoIconoProducto)).clave, 'cafe');
      expect(find.byIcon(iconoDeProductoDe('cafe').icono), findsOneWidget);
    });

    testWidgets('sin imagen dibuja el icono neutro', (tester) async {
      await montar(tester, null);

      expect(find.byIcon(iconoDeProductoPorDefecto.icono), findsOneWidget);
    });

    testWidgets('una foto que no está cae al icono, no a un hueco', (tester) async {
      // Pasa de verdad: una base traída por sincronización o restaurada de un
      // backup referencia fotos que este aparato no tiene. Un cuadro en blanco
      // se leería como que algo se rompió.
      await montar(tester, 'no-existe.jpg');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BentoIconoProducto), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el icono no toca los bordes del hueco', (tester) async {
      // Pegado al borde deja de leerse como algo puesto DENTRO del
      // compartimento y pasa a parecer un botón.
      await montar(tester, 'ico:cafe');

      expect(tester.getSize(find.byIcon(iconoDeProductoDe('cafe').icono)).width, lessThan(100));
    });
  });

  group('el diálogo del banco', () {
    Future<void> abrir(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildBentoTheme(AcentoTinte.oro),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => elegirDelBanco(context),
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
    }

    testWidgets('muestra los iconos de la casa sin que haya nada agregado', (tester) async {
      // Un banco vacío del que no se pueda elegir nada sería una pantalla que
      // solo sabe decir "no hay".
      await abrir(tester);

      expect(find.text('Iconos'), findsOneWidget);
      expect(find.byType(ImagenDelBancoVista), findsNWidgets(banco.iconosDeFabrica));
    });

    testWidgets('cada icono viene con su nombre', (tester) async {
      await abrir(tester);

      expect(find.text(iconoDeProductoDe('cafe').etiqueta), findsOneWidget);
      expect(find.text(iconoDeProductoDe('casado').etiqueta), findsOneWidget);
    });

    testWidgets('ofrece cámara y galería', (tester) async {
      await abrir(tester);

      expect(find.text('Cámara'), findsOneWidget);
      expect(find.text('Galería'), findsOneWidget);
    });

    testWidgets('"Sin imagen" y "Cancelar" son cosas distintas', (tester) async {
      // Vaciar la imagen es una elección; cancelar no cambia nada. Si
      // devolvieran lo mismo, no se podría quitar una foto ya puesta.
      await abrir(tester);
      expect(find.text('Sin imagen'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Iconos'), findsNothing);
    });
  });
}
