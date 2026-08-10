import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/core/theme/bento_bandeja.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/auth/login_screen.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';
import 'package:vulp_tiketing/features/configuracion/ui/configuracion_screen.dart';
import 'package:vulp_tiketing/features/producto/ui/producto_crud_screen.dart';
import 'package:vulp_tiketing/features/reportes/ui/reportes_screen.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
import 'package:vulp_tiketing/features/venta/ui/panel_venta_screen.dart';
import 'package:vulp_tiketing/features/venta/ui/venta_rapida_screen.dart';

/// Ninguna pantalla puede desbordar en ningún tamaño ni con ningún rol.
///
/// Antes de esta prueba **no existía ni un test que redimensionara la ventana**,
/// y por eso cuatro desbordes reales llegaron hasta el aparato: la fila de 4
/// celdas de Reportes, la barra de cobro de Panel Venta, la `Row` raíz del
/// carrito y la rejilla de Configuración que no scrolleaba.
///
/// El rol importa aparte del tamaño porque **cambia el layout**: el Gerente ve
/// 9 tiles en Configuración contra 7, y 4 segmentos de rango contra 2.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('vulp-layout');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    // Las ventas viven en un libro (0025); acá se aplica sobre la misma base.
    await aplicarEsquemaLibro(db);

    await db.insert('categoria', {
      'id': 'cat',
      'nombre': 'General',
      'updated_at': DateTime(2026).toIso8601String(),
    });
    // Con datos, no vacías: juzgar y probar la composición con la base vacía ya
    // nos hizo pasar por alto zonas que en uso real se llenan.
    for (var i = 0; i < 12; i++) {
      await db.insert('producto', {
        'id': 'p$i',
        'nombre': 'Producto de nombre largo número $i',
        'categoria_id': 'cat',
        'precio_base': 1000.0 + i * 250,
        'updated_at': DateTime(2026).toIso8601String(),
      });
    }
    final ahora = DateTime.now();
    for (var i = 0; i < 5; i++) {
      final f = DateTime(ahora.year, ahora.month, ahora.day, 8 + i * 3).toIso8601String();
      await db.insert('venta', {'id': 'v$i', 'fecha_hora': f, 'estado': 'activa', 'updated_at': f});
      await db.insert('linea_venta', {
        'id': 'l$i', 'venta_id': 'v$i', 'producto_id': 'p$i',
        // Importes grandes a propósito: son los que desbordan una celda angosta.
        'precio_aplicado': 125000.0, 'cantidad': 3, 'updated_at': f,
      });
    }
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Los tres tamaños del sistema, con el teléfono real del negocio primero.
  const tamanos = <String, Size>{
    'compacto 360x800': Size(360, 800),
    // Teléfono ACOSTADO: 800 de ancho por solo 360 de alto. Es el caso que más
    // aprieta en vertical y no estaba cubierto — el usuario reportó un
    // "overflowed by 36 pixels" en Reportes que ninguna prueba veía.
    'horizontal 800x360': Size(800, 360),
    'medio 800x1280': Size(800, 1280),
    'amplio 1440x900': Size(1440, 900),
  };

  Future<void> montar(WidgetTester tester, Widget pantalla, Size tamano, Rol rol) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          libroVentasServiceProvider.overrideWith(
            (ref) async => LibroVentasService(directorio: dir.path),
          ),
          sesionNotifierProvider.overrideWith(() => _SesionFija(rol)),
        ],
        child: MaterialApp(theme: buildBentoTheme(AcentoTinte.oro), home: pantalla),
      ),
    );
    // `pump` con tiempo en vez de `pumpAndSettle`: hay indicadores de progreso
    // que giran para siempre y dejarían el settle esperando indefinidamente.
    //
    // Y `runAsync` en medio: los `pump` mueven un reloj FALSO, así que las
    // consultas a SQLite —que son I/O de verdad— no avanzan con ellos. Las
    // cargas van en cadena (base → productos → categorías, que hacen falta para
    // los títulos por categoría) y sin dejar correr el reloj real la última
    // quedaba a medio camino: el test moría con "a Timer is still pending"
    // porque el tearDown cerraba la base debajo de una consulta en vuelo.
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  final pantallas = <String, Widget Function()>{
    'Login': () => const LoginScreen(),
    'Venta Rápida': () => const VentaRapidaScreen(),
    'Panel Venta': () => const PanelVentaScreen(),
    'Productos': () => const ProductoCrudScreen(),
    'Reportes': () => const ReportesScreen(),
    'Configuración': () => const ConfiguracionScreen(),
  };

  for (final rol in Rol.values) {
    for (final tamano in tamanos.entries) {
      for (final pantalla in pantallas.entries) {
        testWidgets('${pantalla.key} no desborda en ${tamano.key} (${rol.name})', (tester) async {
          await montar(tester, pantalla.value(), tamano.value, rol);

          expect(
            tester.takeException(),
            isNull,
            reason: '${pantalla.key} desborda a ${tamano.key} con rol ${rol.name}',
          );
        });
      }
    }
  }

  testWidgets('el Login no desborda con el teclado abierto', (tester) async {
    // La dimensión que faltaba. El usuario encontró en el aparato un
    // "BOTTOM OVERFLOWED BY 251 PIXELS" en el Login acostado con el teclado
    // abierto, y ninguna prueba lo veía: todas medían la pantalla completa.
    //
    // Acostado es el peor caso porque el teclado se come más de la mitad del
    // alto disponible.
    for (final tamano in [const Size(800, 360), const Size(360, 800)]) {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      // El inset de la vuelta anterior sigue puesto si no se limpia acá, y la
      // segunda iteración arrancaba con medio teclado fantasma.
      tester.view.viewInsets = FakeViewPadding.zero;
      addTearDown(tester.view.reset);

      // Árbol vacío entre vueltas: sin esto el `State` del Login sobrevive al
      // segundo `pumpWidget` y la prueba no empieza en la vista de roles.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: buildBentoTheme(AcentoTinte.oro), home: const LoginScreen()),
        ),
      );
      await tester.pump();

      // Elegir el rol es lo que abre el teclado — el inset entra DESPUÉS, no
      // antes: en la pantalla de roles no hay ningún campo y simular el teclado
      // ahí probaba una situación que no existe.
      await tester.tap(find.text('Gerente'));
      await tester.pump(const Duration(milliseconds: 300));

      // Un teclado real ocupa cerca de la mitad del alto en horizontal.
      tester.view.viewInsets = FakeViewPadding(bottom: tamano.height * 0.55);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.takeException(),
        isNull,
        reason: 'el Login desborda con el teclado abierto a $tamano',
      );

      // No desbordar no basta: acostado el contenido cabía en el scroll pero
      // "Entrar" quedaba por debajo del borde visible, así que había que
      // desplazar para poder pulsarlo. El botón tiene que estar A LA VISTA.
      final visible = tamano.height - tamano.height * 0.55;
      expect(
        tester.getRect(find.text('Entrar')).bottom,
        lessThanOrEqualTo(visible),
        reason: '"Entrar" queda fuera de la vista con el teclado abierto a $tamano',
      );
    }
  });

  testWidgets('los tiles de Configuración caen de a 3 por fila', (tester) async {
    // La comprobación visible de que la retícula manda: cada tile ocupa 2 de 6
    // columnas, así que son 3 por fila den 360 dp o 1440.
    await montar(tester, const ConfiguracionScreen(), const Size(360, 800), Rol.gerente);

    // Se mide el POZO de cada tile, no su texto. Las etiquetas encogen cada una
    // lo suyo para no partirse (`BentoEtiquetaAjustada`), así que su alto ya no
    // es idéntico entre vecinas y comparar la cima del texto daba tres valores
    // distintos para una misma fila.
    double cimaDelTile(String etiqueta) => tester
        .getTopLeft(find.ancestor(of: find.text(etiqueta), matching: find.byType(BentoPozo)).first)
        .dy;

    final primeros = ['Contraseña', 'Exportar', 'Restaurar'];
    final ys = {for (final t in primeros) cimaDelTile(t)};
    expect(ys, hasLength(1), reason: 'los tres primeros tiles van en la misma fila');

    expect(cimaDelTile('Catálogo'), greaterThan(ys.first), reason: 'el cuarto abre fila nueva');
  });

  testWidgets('Configuración muestra el panel al lado en escritorio y debajo en teléfono', (
    tester,
  ) async {
    await montar(tester, const ConfiguracionScreen(), const Size(1440, 900), Rol.gerente);
    // `.first` porque tras elegir la opción el panel repite el rótulo
    // "Acento" en su cabecera, y el finder encontraría dos.
    await tester.tap(find.text('Acento').first);
    await tester.pump(const Duration(milliseconds: 300));

    // Dos "Acento": el tile y la cabecera del panel. La segunda ubica al panel
    // sin depender de que sus controles ya hayan cargado de preferencias.
    expect(find.text('Acento'), findsNWidgets(2));
    final xTile = tester.getTopLeft(find.text('Acento').first).dx;
    final xPanel = tester.getTopLeft(find.text('Acento').last).dx;
    expect(
      xPanel,
      greaterThan(xTile),
      reason: 'en escritorio el detalle va a la derecha de los tiles',
    );

    await montar(tester, const ConfiguracionScreen(), const Size(360, 800), Rol.gerente);
    await tester.tap(find.text('Acento').first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Acento'), findsNWidgets(2));
    final yTile = tester.getTopLeft(find.text('Acento').first).dy;
    final yPanel = tester.getTopLeft(find.text('Acento').last).dy;
    expect(yPanel, greaterThan(yTile), reason: 'en teléfono el detalle va debajo');
  });
}

/// Fija el rol sin pasar por almacenamiento seguro, que no existe en un test.
class _SesionFija extends SesionNotifier {
  _SesionFija(this.rol);
  final Rol rol;

  @override
  Rol? build() => rol;
}
