import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/core/ui/bento_dialogo.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/venta/ui/cobro_rapido_overlay.dart';

/// Ningún emergente desborda en ningún tamaño, ni con el teclado abierto.
///
/// El overlay de cobro desbordó en el aparato después de pasarlo a "sin
/// scroll", y ninguna prueba lo veía: las de layout montaban PANTALLAS, y un
/// diálogo no está montado mientras nadie lo abre. Acá se montan directamente.
///
/// El teclado importa tanto como el tamaño: cobrar significa escribir cuánto
/// recibiste, o sea que la mitad del alto se va justo cuando el emergente está
/// abierto.
void main() {
  /// Los tamaños del parque real, en las dos orientaciones. El teléfono del
  /// negocio es un Honor X6c (360×800) y el de pruebas un P30 lite (412×915).
  const tamanos = <String, Size>{
    'teléfono chico 360x640': Size(360, 640),
    'teléfono 360x800': Size(360, 800),
    'teléfono grande 412x915': Size(412, 915),
    'teléfono chico acostado 640x360': Size(640, 360),
    'teléfono acostado 800x360': Size(800, 360),
    'teléfono grande acostado 915x412': Size(915, 412),
    'tablet 800x1280': Size(800, 1280),
    'tablet acostada 1280x800': Size(1280, 800),
    'escritorio 1440x900': Size(1440, 900),
  };

  final producto = Producto(
    id: 'p1',
    nombre: 'Casado con pollo a la plancha y ensalada',
    precioBase: 3500,
    updatedAt: DateTime(2026),
  );

  Future<void> montar(
    WidgetTester tester,
    Size tamano,
    Widget emergente, {
    bool conTeclado = false,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = conTeclado
        // Un teclado real se come cerca de la mitad del alto acostado.
        ? FakeViewPadding(bottom: tamano.height * 0.45)
        : FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    // Por `showDialog`, no como `body` de un Scaffold: un emergente montado a
    // mano recibe restricciones distintas de las que tiene abierto de verdad
    // —insetPadding, el ancho mínimo del Dialog, el descuento del teclado— y
    // probar la versión de mentira es no probar nada.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildBentoTheme(AcentoTinte.oro),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => emergente),
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

  group('el cobro rápido', () {
    for (final tamano in tamanos.entries) {
      for (final conTeclado in [false, true]) {
        final con = conTeclado ? ' con el teclado abierto' : '';
        testWidgets('no desborda en ${tamano.key}$con', (tester) async {
          await montar(
            tester,
            tamano.value,
            CobroRapidoOverlay(producto: producto),
            conTeclado: conTeclado,
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'el cobro rápido desborda en ${tamano.key}$con',
          );

          // No desbordar no basta: cobrar tiene que poder terminarse sin
          // desplazar nada. Es la queja original —"el de venta actualmente es
          // un scroll que para eficiencia no va"— y la razón de que los botones
          // vivan fuera del scroll.
          final alto = tamano.value.height - (conTeclado ? tamano.value.height * 0.45 : 0);
          expect(
            tester.getRect(find.text('Completado')).bottom,
            lessThanOrEqualTo(alto),
            reason: '"Completado" queda fuera de la vista en ${tamano.key}$con',
          );
          expect(
            tester.getRect(find.text('Cancelar')).bottom,
            lessThanOrEqualTo(alto),
            reason: '"Cancelar" queda fuera de la vista en ${tamano.key}$con',
          );
        });
      }
    }

    testWidgets('acostado los botones van al costado, no debajo', (tester) async {
      await montar(tester, const Size(800, 360), CobroRapidoOverlay(producto: producto));

      final total = tester.getRect(find.textContaining('₡3500').first);
      expect(tester.getRect(find.text('Completado')).left, greaterThan(total.right));
    });

    testWidgets('de pie los botones van debajo, en dos columnas', (tester) async {
      await montar(tester, const Size(360, 800), CobroRapidoOverlay(producto: producto));

      final total = tester.getRect(find.textContaining('₡3500').first);
      final boton = tester.getRect(find.text('Completado'));
      expect(boton.top, greaterThan(total.bottom));
      expect(boton.left, greaterThan(tester.getRect(find.text('Cancelar')).right));
    });
  });

  group('un diálogo con cuatro acciones', () {
    Widget dialogo() => BentoDialogo(
      titulo: const Text('Editar producto'),
      contenido: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(decoration: InputDecoration(labelText: 'Nombre')),
          TextField(decoration: InputDecoration(labelText: 'Precio base (₡)')),
          TextField(decoration: InputDecoration(labelText: 'Categoría')),
        ],
      ),
      acciones: BentoAcciones(
        izquierda: [
          TextButton(onPressed: null, child: const Text('Reactivar')),
          TextButton(onPressed: null, child: const Text('Eliminar')),
        ],
        derecha: [
          TextButton(onPressed: null, child: const Text('Cancelar')),
          FilledButton(onPressed: null, child: const Text('Guardar')),
        ],
      ),
    );

    for (final tamano in tamanos.entries) {
      for (final conTeclado in [false, true]) {
        final con = conTeclado ? ' con el teclado abierto' : '';
        testWidgets('no desborda en ${tamano.key}$con', (tester) async {
          await montar(tester, tamano.value, dialogo(), conTeclado: conTeclado);

          expect(
            tester.takeException(),
            isNull,
            reason: 'el diálogo desborda en ${tamano.key}$con',
          );
        });
      }
    }
  });
}
