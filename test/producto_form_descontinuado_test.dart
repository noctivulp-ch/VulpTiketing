import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/producto/categoria_model.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';
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

  Future<void> montar(
    WidgetTester tester,
    Producto p, {
    Size? tamano,
    Rol rol = Rol.gerente,
  }) async {
    if (tamano != null) {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriaNotifierProvider.overrideWith(() => _CategoriasFijas([categoria])),
          sesionNotifierProvider.overrideWith(() => _SesionFija(rol)),
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

  testWidgets('al Gerente, un producto fuera de la carta le ofrece reactivar y eliminar', (
    tester,
  ) async {
    await montar(tester, producto(activo: false, categoriaId: 'cat-viva'));

    expect(find.text('Reactivar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
  });

  testWidgets('a la Registradora, solo reactivar — nunca eliminar', (tester) async {
    // Lo encontró el dueño usando la app: la lista del catálogo ya escondía el
    // borrado físico a la Registradora, pero este diálogo lo ofrecía a
    // cualquiera. Un borrado físico no se deshace y se propaga a los demás
    // aparatos como borrado; descontinuar, que sí es reversible, es lo que le
    // corresponde a una caja.
    await montar(tester, producto(activo: false, categoriaId: 'cat-viva'), rol: Rol.registradora);

    expect(find.text('Reactivar'), findsOneWidget);
    expect(find.text('Eliminar'), findsNothing);
  });

  testWidgets('acostado no desborda: las acciones se van al costado', (tester) async {
    // Acostado el alto es el recurso escaso, y con las cuatro acciones debajo
    // el diálogo desbordaba 95 px en el aparato.
    await montar(
      tester,
      producto(activo: false, categoriaId: 'cat-viva'),
      tamano: const Size(800, 360),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Reactivar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets('Guardar queda a la derecha de Cancelar, y en la misma fila', (tester) async {
    // Lo vio el dueño usando la app: para guardar se pulsa a la derecha sin
    // mirar, y este formulario apilaba Cancelar encima de Guardar en la columna
    // derecha — así que la mitad de las veces el pulgar caía en Cancelar.
    await montar(tester, producto(activo: true, categoriaId: 'cat-viva'));

    final guardar = tester.getCenter(find.text('Guardar'));
    final cancelar = tester.getCenter(find.text('Cancelar'));

    expect(guardar.dx, greaterThan(cancelar.dx));
    expect(guardar.dy, cancelar.dy, reason: 'en la misma fila, no apilados');
  });

  testWidgets('y lo destructivo queda lejos del botón de guardar', (tester) async {
    await montar(tester, producto(activo: false, categoriaId: 'cat-viva'));

    final guardar = tester.getCenter(find.text('Guardar'));
    expect(tester.getCenter(find.text('Eliminar')).dx, lessThan(guardar.dx));
    expect(tester.getCenter(find.text('Eliminar')).dy, greaterThan(guardar.dy));
  });

  testWidgets('uno activo no ofrece ninguna de las dos', (tester) async {
    await montar(tester, producto(activo: true, categoriaId: 'cat-viva'));

    expect(find.text('Reactivar'), findsNothing);
    expect(find.text('Eliminar'), findsNothing);
  });
}

class _SesionFija extends SesionNotifier {
  _SesionFija(this.rol);

  final Rol rol;

  @override
  Rol? build() => rol;
}

class _CategoriasFijas extends CategoriaNotifier {
  _CategoriasFijas(this.categorias);

  final List<Categoria> categorias;

  @override
  Future<List<Categoria>> build() async => categorias;
}
