import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vulp_tiketing/core/theme/bento_fotos.dart';
import 'package:vulp_tiketing/core/theme/bento_icono_producto.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/configuracion/preferencias_notifier.dart';
import 'package:vulp_tiketing/features/producto/ui/imagen_del_banco_vista.dart';

/// Todo producto tiene cara, y la que le toca sale de su **categoría**.
///
/// Antes, un producto sin imagen elegida no mostraba nada —en Venta Rápida ni
/// siquiera se reservaba el hueco—, así que la cuadrícula quedaba con unas
/// celdas con dibujo y otras sin él. El icono por categoría lo resuelve sin
/// pedirle a nadie que elija imagen producto por producto: las categorías ya
/// están escritas ("Arroces", "Batidos en Leche") y de ahí sale el dibujo.
void main() {
  group('qué icono le toca a cada categoría', () {
    test('las categorías reales de la soda aciertan', () {
      // Son las del menú de la soda, tal como están escritas en la base.
      expect(iconoDeCategoria('Arroces').clave, 'casado');
      expect(iconoDeCategoria('Batidos en Leche').clave, 'batido');
      expect(iconoDeCategoria('Refrescos Naturales').clave, 'refresco');
      expect(iconoDeCategoria('Casados').clave, 'casado');
      expect(iconoDeCategoria('Desayunos').clave, 'desayuno');
      expect(iconoDeCategoria('Carnes').clave, 'carne');
    });

    test('da igual cómo esté escrito: mayúsculas y tildes', () {
      // El nombre lo escribe una persona a mano; el acento no puede decidir si
      // el producto tiene cara o no.
      expect(iconoDeCategoria('CAFÉ').clave, iconoDeCategoria('cafe').clave);
      expect(iconoDeCategoria('Repostería').clave, 'reposteria');
    });

    test('lo específico gana a lo general', () {
      // "Batidos en Leche" contiene las dos pistas; tiene que dar batido, que
      // es de lo que trata la categoría.
      expect(iconoDeCategoria('Batidos en Leche').clave, 'batido');
    });

    test('las genéricas también aciertan, sin pisar a las específicas', () {
      // "Bebidas" a secas es de las categorías más comunes de una soda y caía
      // al icono neutro — lo vi en el aparato al crear una. Pero la genérica no
      // puede ganarle a la específica: "Bebidas Naturales" sigue siendo
      // refresco, no un vaso cualquiera.
      expect(iconoDeCategoria('Bebidas').clave, 'refresco');
      expect(iconoDeCategoria('Comidas Rápidas').clave, 'hamburguesa');
      expect(iconoDeCategoria('Batidos en Leche').clave, 'batido');
      expect(iconoDeCategoria('Frappé').clave, 'batido');
    });

    test('una categoría que no dice nada cae al neutro, no revienta', () {
      expect(iconoDeCategoria('Varios surtidos').clave, iconoDeProductoPorDefecto.clave);
      expect(iconoDeCategoria(null).clave, iconoDeProductoPorDefecto.clave);
      expect(iconoDeCategoria('').clave, iconoDeProductoPorDefecto.clave);
    });
  });

  group('la vista', () {
    Future<void> montar(
      WidgetTester tester, {
      String? referencia,
      String? categoria,
      VentanaConFotos? ventana,
      Set<VentanaConFotos> sinFotos = const {},
    }) async {
      SharedPreferences.setMockInitialValues({
        'fotos_apagadas': sinFotos.map((v) => v.name).toList(),
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildBentoTheme(AcentoTinte.oro),
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: ImagenDelBancoVista(
                  referencia: referencia,
                  ventana: ventana,
                  categoria: categoria,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('sin imagen elegida se dibuja el icono de la categoría', (tester) async {
      await montar(tester, categoria: 'Arroces', ventana: VentanaConFotos.ventaRapida);

      expect(find.byIcon(iconoDeProductoDe('casado').icono), findsOneWidget);
    });

    testWidgets('lo que el producto tiene elegido manda sobre la categoría', (tester) async {
      // Si la categoría pisara la elección, cambiarle la categoría a un producto
      // le borraría la imagen que alguien le puso a mano.
      await montar(
        tester,
        referencia: 'ico:postre',
        categoria: 'Arroces',
        ventana: VentanaConFotos.ventaRapida,
      );

      expect(find.byIcon(iconoDeProductoDe('postre').icono), findsOneWidget);
      expect(find.byIcon(iconoDeProductoDe('casado').icono), findsNothing);
    });
  });

  group('apagar las fotos por ventana', () {
    Future<void> montarConFoto(
      WidgetTester tester,
      VentanaConFotos ventana, {
      required Set<VentanaConFotos> sinFotos,
    }) async {
      SharedPreferences.setMockInitialValues({
        'fotos_apagadas': sinFotos.map((v) => v.name).toList(),
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildBentoTheme(AcentoTinte.oro),
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: ImagenDelBancoVista(
                  // Una foto, no un icono: es lo que la preferencia apaga.
                  referencia: 'una-foto.jpg',
                  ventana: ventana,
                  categoria: 'Arroces',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('apagada, la celda NO queda vacía: va el icono de la categoría', (tester) async {
      // Es la diferencia entre optimizar y quitar funcionalidad. Se ahorra
      // decodificar el JPEG, no se pierde de qué es cada celda.
      await montarConFoto(
        tester,
        VentanaConFotos.ventaRapida,
        sinFotos: {VentanaConFotos.ventaRapida},
      );

      expect(find.byIcon(iconoDeProductoDe('casado').icono), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('apagarla en una ventana no la apaga en las otras', (tester) async {
      // Es el punto de que haya una por ventana: la carta puede ir sin fotos y
      // el inventario —donde las fotos son lo que se administra— con ellas.
      await montarConFoto(
        tester,
        VentanaConFotos.inventario,
        sinFotos: {VentanaConFotos.ventaRapida},
      );

      // Llega a intentar leer el archivo (que no existe en la prueba), o sea no
      // la cortó la preferencia.
      expect(tester.takeException(), isNull);
    });
  });

  group('la preferencia se guarda', () {
    test('apagar y encender una ventana deja rastro en el disco', () async {
      SharedPreferences.setMockInitialValues({});
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      await contenedor.read(preferenciasNotifierProvider.future);
      final notifier = contenedor.read(preferenciasNotifierProvider.notifier);

      await notifier.cambiarFotos(VentanaConFotos.ventaRapida, activo: false);
      expect(contenedor.read(preferenciasNotifierProvider).valueOrNull?.fotosApagadasEn, {
        VentanaConFotos.ventaRapida,
      });

      await notifier.cambiarFotos(VentanaConFotos.ventaRapida, activo: true);
      expect(contenedor.read(preferenciasNotifierProvider).valueOrNull?.fotosApagadasEn, isEmpty);
    });

    test('se relee al arrancar', () async {
      // Una preferencia de rendimiento que se olvida al cerrar la app no sirve
      // de nada: el aparato lento sigue siendo lento mañana.
      SharedPreferences.setMockInitialValues({
        'fotos_apagadas': [VentanaConFotos.venta.name, VentanaConFotos.inventario.name],
      });
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);

      final preferencias = await contenedor.read(preferenciasNotifierProvider.future);

      expect(preferencias.fotosApagadasEn, {VentanaConFotos.venta, VentanaConFotos.inventario});
    });

    test('un valor guardado que ya no existe se ignora en vez de romper', () async {
      // Pasa al renombrar o quitar una ventana: la preferencia vieja sigue en
      // el disco del aparato.
      SharedPreferences.setMockInitialValues({
        'fotos_apagadas': ['ventanaQueYaNoExiste', VentanaConFotos.venta.name],
      });
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);

      final preferencias = await contenedor.read(preferenciasNotifierProvider.future);

      expect(preferencias.fotosApagadasEn, {VentanaConFotos.venta});
    });
  });
}
