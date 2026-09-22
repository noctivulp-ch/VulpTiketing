import 'dart:io';

import 'package:costeo/costeo.dart' as c;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/costeo/costeo_notifiers.dart';
import 'package:vulp_tiketing/features/costeo/costo_fijo_model.dart';
import 'package:vulp_tiketing/features/costeo/insumo_model.dart';
import 'package:vulp_tiketing/features/costeo/ui/costeo_screen.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// La ventana de Costeo (0040): que muestre lo que hay, que las cuatro
/// secciones abran, y —lo que de verdad importa— que "Aplicar" esté apagado
/// cuando no hay nada que aplicar y que sea la única forma de tocar la carta.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;
  late LibroVentasService libros;
  late ProviderContainer container;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-costeo-ui');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    libros = LibroVentasService(directorio: dir.path);
    await libros.adjuntarAbierto(db);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        libroVentasServiceProvider.overrideWith((ref) async => libros),
      ],
    );
    await container.read(productoNotifierProvider.notifier).crear(
      Producto(id: 'casado', nombre: 'Casado', precioBase: 3000, updatedAt: DateTime(2026)),
    );
  });

  tearDown(() async {
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await libros.desadjuntar(db);
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildBentoTheme(AcentoTinte.oro), home: const CosteoScreen()),
      ),
    );
    // Hasta que el catálogo esté pintado: la primera prueba del archivo paga
    // el arranque del isolate de SQLite y cuatro vueltas no le alcanzaban.
    for (var i = 0; i < 20 && find.text('Casado').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('sin costear, el artículo aparece con sus avisos y el negocio en cero', (tester) async {
    await montar(tester);
    expect(find.text('Casado'), findsOneWidget);
    expect(find.textContaining('Sin receta'), findsOneWidget);
    expect(find.textContaining('Sin volumen'), findsOneWidget);
    // El tallado pinta el texto tres veces (sombra, luz y glifo).
    expect(find.text('Utilidad ₡0'), findsWidgets);
  });

  testWidgets('las cuatro secciones abren y las de carga tienen su botón de crear', (tester) async {
    await montar(tester);
    await tester.tap(find.text('Insumos'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nuevo insumo'), findsOneWidget);

    await tester.tap(find.text('Fijos'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nuevo costo'), findsOneWidget);

    await tester.tap(find.text('Ajustes'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(TextFormField, 'Margen objetivo (%)'), findsOneWidget);
    // La lista es perezosa: lo de abajo no existe hasta desplazar.
    await tester.drag(find.byType(ListView).last, const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Simplificado'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Factor IVA (%)'), findsOneWidget);
    expect(find.text('Guardar parámetros'), findsOneWidget);
  });

  testWidgets('crear un insumo desde su formulario lo deja en la lista con su costo efectivo', (tester) async {
    await montar(tester);
    await tester.tap(find.text('Insumos'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Nuevo insumo'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Harina');
    await tester.enterText(find.widgetWithText(TextFormField, 'Trae (g)'), '1000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Precio de arranque (₡)'), '4500');
    await tester.enterText(find.widgetWithText(TextFormField, 'Merma (%)'), '3');
    await tester.tap(find.text('Guardar'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Harina'), findsOneWidget);
    // 4.500 / 1000 / 0,97 = 4,64 por gramo con merma.
    expect(find.text('₡4.64'), findsOneWidget);
    final guardado = (await tester.runAsync(() => container.read(insumoNotifierProvider.future)))!.single;
    expect(guardado.unidadBase, c.UnidadBase.gramo);
    expect(guardado.merma, closeTo(0.03, 1e-9));
  });

  testWidgets('desde un insumo se anota una compra y el costo de la lista cambia con ella', (tester) async {
    await tester.runAsync(() => container.read(insumoNotifierProvider.notifier).crear(
      InsumoRegistro(id: 'harina', nombre: 'Harina', unidadBase: c.UnidadBase.gramo, contenidoPorCompra: 1000, precioCompra: 900, merma: 0, updatedAt: DateTime.now()),
    ));
    await montar(tester);
    await tester.tap(find.text('Insumos'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('₡0.90'), findsOneWidget, reason: 'sin compras manda el arranque');
    expect(find.textContaining('precio de arranque'), findsOneWidget);

    await tester.tap(find.text('Harina'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Anotar compra'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.widgetWithText(TextFormField, 'Cuántas'), '2');
    await tester.enterText(find.widgetWithText(TextFormField, 'De cuánto (g)'), '5000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Pagado por todo (₡)'), '4000');
    await tester.pump();
    expect(find.text('10000 g → ₡0.40 por g'), findsOneWidget, reason: 'la cuenta a la vista mientras se escribe');
    await tester.tap(find.text('Anotar'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text('Cerrar'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('₡0.40'), findsOneWidget);
    expect(find.textContaining('promedio de compras'), findsOneWidget);
    expect(find.textContaining('Comprado: mes ₡4000'), findsOneWidget);
  });

  testWidgets('el detalle del artículo apaga "Aplicar" cuando se cobra justo lo sugerido, y no toca la carta sin pulsarlo', (tester) async {
    // Con receta y sin costos fijos, precio sugerido = 240 / 0,37 → techo 50 = 650 + 0.
    // Sembrar va bajo `runAsync`: es I/O real y bajo el reloj falso del test
    // no termina nunca — esta prueba se colgó diez minutos por eso.
    await tester.runAsync(() async {
      await container.read(insumoNotifierProvider.notifier).crear(
        InsumoRegistro(id: 'arroz', nombre: 'Arroz', unidadBase: c.UnidadBase.gramo, contenidoPorCompra: 1000, precioCompra: 1200, merma: 0, updatedAt: DateTime.now()),
      );
      final articulos = container.read(articuloCosteoProvider.notifier);
      final registro = await articulos.asegurar('casado', '');
      await articulos.ponerLinea(registro.id, 'arroz', 200);
      await container.read(costoFijoNotifierProvider.notifier).crear(
        CostoFijoRegistro(id: 'x', concepto: 'Nada', montoMensual: 0, updatedAt: DateTime.now()),
      );
    });
    await montar(tester);

    await tester.tap(find.text('Casado'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Receta'), findsOneWidget);
    expect(find.textContaining('Arroz · 200 g'), findsOneWidget);
    // 240 de insumos sobre 3.000 cobrados: food cost 8 %.
    expect(find.textContaining('Food cost (insumos'), findsOneWidget);
    expect(find.text('8 %'), findsOneWidget);
    final aplicar = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Aplicar ₡650'));
    expect(aplicar.onPressed, isNotNull, reason: 'se cobra 3.000 y el modelo dice 650: hay qué aplicar');

    // Nada se aplicó por mirar. (Bajo `runAsync`: la lectura de la base es
    // I/O real y bajo el reloj falso no terminaría nunca.)
    final productos = await tester.runAsync(() => container.read(productoNotifierProvider.future));
    expect(productos!.single.precioBase, 3000);
  });
}
