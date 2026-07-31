import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/producto/categoria_model.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/ui/producto_form_dialog.dart';

/// El formulario de producto tiene que aguantar datos rotos y ofrecer las
/// salidas de un producto fuera de la carta.
void main() {
  final categoria = Categoria(id: 'cat-viva', nombre: 'Bebidas', updatedAt: DateTime(2026));

  Producto producto({required bool activo, String? categoriaId}) => Producto(
    id: 'p1',
    nombre: 'Horchata',
    precioBase: 1200,
    categoriaId: categoriaId,
    // "Fuera de la carta" ES `deletedAt` con fecha: descontinuar no borra, marca
    // (0005), y `activo` se deriva de eso.
    deletedAt: activo ? null : DateTime(2026, 6),
    updatedAt: DateTime(2026),
  );

  Future<void> montar(WidgetTester tester, Producto p) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriaNotifierProvider.overrideWith(() => _CategoriasFijas([categoria])),
        ],
        child: MaterialApp(
          theme: buildBentoTheme(AcentoTinte.oro, brightness: Brightness.dark),
          home: Scaffold(body: ProductoFormDialog(producto: p)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('una categoría que ya no existe no tumba el formulario', (tester) async {
    // Pasa tras importar un catálogo con reemplazo o cuando la sincronización
    // trae un borrado: el producto queda apuntando a una categoría muerta. El
    // `DropdownButton` revienta con un assert si su valor no está entre los
    // items, y entonces el producto que había que arreglar no se puede ni
    // abrir.
    await montar(tester, producto(activo: true, categoriaId: 'cat-borrada'));

    expect(tester.takeException(), isNull);
    expect(find.text('Categoría eliminada'), findsOneWidget);
  });

  testWidgets('una categoría viva se muestra normal', (tester) async {
    await montar(tester, producto(activo: true, categoriaId: 'cat-viva'));

    expect(tester.takeException(), isNull);
    expect(find.text('Bebidas'), findsOneWidget);
    expect(find.text('Categoría eliminada'), findsNothing);
  });

  testWidgets('un producto fuera de la carta ofrece reactivar y eliminar', (tester) async {
    await montar(tester, producto(activo: false, categoriaId: 'cat-viva'));

    expect(find.text('Reactivar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
  });

  testWidgets('uno activo no ofrece ninguna de las dos', (tester) async {
    await montar(tester, producto(activo: true, categoriaId: 'cat-viva'));

    expect(find.text('Reactivar'), findsNothing);
    expect(find.text('Eliminar'), findsNothing);
  });
}

class _CategoriasFijas extends CategoriaNotifier {
  _CategoriasFijas(this.categorias);

  final List<Categoria> categorias;

  @override
  Future<List<Categoria>> build() async => categorias;
}
