import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';
import 'package:vulp_tiketing/features/producto/categoria_model.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/producto/ui/producto_form_dialog.dart';
import 'package:vulp_tiketing/features/producto/variante_model.dart';

/// El formulario con variantes: el campo "Precio base" se convierte en el
/// señalador de cuál es la por defecto, y al guardar `precio_base` es el
/// precio de esa. Lo pidió el dueño al ver que, con variantes, el precio base
/// quedaba "de facto sin uso".
void main() {
  final categoria = Categoria(id: 'cat', nombre: 'Cafés', updatedAt: DateTime(2026));

  Producto conVariantes() => Producto(
    id: 'cafe',
    nombre: 'Café',
    precioBase: 800,
    categoriaId: 'cat',
    variantes: const [
      Variante(id: 'p', nombre: 'Pequeño', precio: 800, porDefecto: true),
      Variante(id: 'g', nombre: 'Grande', precio: 1200),
    ],
    updatedAt: DateTime(2026),
  );

  Producto sinVariantes() =>
      Producto(id: 'casado', nombre: 'Casado', precioBase: 3000, categoriaId: 'cat', updatedAt: DateTime(2026));

  Future<_ProductosEspia> montar(WidgetTester tester, Producto p) async {
    tester.view.physicalSize = const Size(412, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final espia = _ProductosEspia();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriaNotifierProvider.overrideWith(() => _CategoriasFijas([categoria])),
          sesionNotifierProvider.overrideWith(() => _SesionFija(Rol.gerente)),
          productoNotifierProvider.overrideWith(() => espia),
        ],
        child: MaterialApp(
          theme: buildBentoTheme(AcentoTinte.oro),
          home: Scaffold(body: ProductoFormDialog(producto: p)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return espia;
  }

  testWidgets('sin variantes hay campo numérico y ningún radio', (tester) async {
    await montar(tester, sinVariantes());
    expect(find.widgetWithText(TextFormField, 'Precio base (₡)'), findsOneWidget);
    expect(find.byType(Radio<String>), findsNothing);
  });

  testWidgets('con variantes hay un radio por variante y ningún campo numérico', (tester) async {
    await montar(tester, conVariantes());
    expect(find.widgetWithText(TextFormField, 'Precio base (₡)'), findsNothing);
    expect(find.byType(Radio<String>), findsNWidgets(2));
    expect(find.textContaining('la marcada es la que se cobra'), findsOneWidget);
  });

  testWidgets('cambiar la por defecto cambia el precio base al guardar', (tester) async {
    final espia = await montar(tester, conVariantes());

    // El segundo radio es "Grande".
    await tester.tap(find.byType(Radio<String>).last);
    await tester.pump();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pump(const Duration(milliseconds: 300));

    final guardado = espia.ultimo!;
    expect(guardado.precioBase, 1200, reason: 'el precio base es el de la por defecto');
    expect(guardado.variantePorDefecto!.id, 'g');
    expect(guardado.variantes.where((v) => v.porDefecto), hasLength(1));
  });

  testWidgets('la primera variante que se agrega hereda el precio base y queda por defecto', (tester) async {
    final espia = await montar(tester, sinVariantes());

    await tester.ensureVisible(find.text('Agregar variante'));
    await tester.tap(find.text('Agregar variante'));
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'Precio base (₡)'), findsNothing, reason: 'el campo se vuelve señalador');
    final precioDeLaVariante = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Precio (₡)'));
    expect(precioDeLaVariante.controller!.text, '3000', reason: 'lo que se vendía hasta ahora es lo que se vende por defecto');

    await tester.enterText(find.widgetWithText(TextFormField, 'Variante'), 'Normal');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(espia.ultimo!.variantes.single.porDefecto, isTrue);
    expect(espia.ultimo!.precioBase, 3000);
  });

  testWidgets('quitar la última variante devuelve el campo numérico con su precio', (tester) async {
    await montar(tester, conVariantes());

    await tester.tap(find.byTooltip('Quitar variante').last); // Grande
    await tester.pump();
    await tester.tap(find.byTooltip('Quitar variante').first); // Pequeño, la por defecto
    await tester.pump();

    final campo = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Precio base (₡)'));
    expect(campo.controller!.text, '800');
  });
}

class _ProductosEspia extends ProductoNotifier {
  Producto? ultimo;

  @override
  Future<List<Producto>> build() async => const [];

  @override
  Future<void> actualizar(Producto producto) async => ultimo = producto;

  @override
  Future<void> crear(Producto producto) async => ultimo = producto;
}

class _CategoriasFijas extends CategoriaNotifier {
  _CategoriasFijas(this.fijas);
  final List<Categoria> fijas;

  @override
  Future<List<Categoria>> build() async => fijas;
}

class _SesionFija extends SesionNotifier {
  _SesionFija(this.rol);
  final Rol rol;

  @override
  Rol? build() => rol;
}
