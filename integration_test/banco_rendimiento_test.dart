// Banco de rendimiento. Corre EN EL APARATO y en modo profile.
//
//   scripts/banco-rendimiento.sh
//
// Por qué en el aparato y no en el escritorio: el teléfono del negocio tiene
// bastante menos potencia, así que un cuello que en la computadora se pierde
// en el ruido acá se ve. Y por qué en profile: en debug TODOS los frames pasan
// del presupuesto y las consultas cargan con el interpretador, así que los
// números de debug no permiten decidir nada.
//
// Mide las dos mitades del problema, porque un tirón en la interfaz puede
// venir de cualquiera:
//   - CONSULTAS: cuánto tarda cada operación de datos, aislada.
//   - INTERFAZ: build y raster por frame mientras se navega, se desplaza y se
//     agregan productos — o sea con las consultas de verdad de por medio.
//
// El volumen sembrado imita un año de la soda, no una base de demostración:
// con pocos datos todo es rápido y el banco no sirve para nada.
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:vulp_tiketing/app.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_query_provider.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';

import 'package:vulp_tiketing/core/theme/bento_efectos.dart';
import 'package:vulp_tiketing/features/configuracion/preferencias_notifier.dart';

import 'siembra.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final medidas = <String, Object>{};
  final interfaz = <String, Object>{};

  setUpAll(() async {
    await prepararBaseDePruebas();
  });

  tearDownAll(() async {
    binding.reportData = {...?binding.reportData, 'consultas': medidas, 'interfaz': interfaz};
  });

  testWidgets('consultas', (tester) async {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    Future<void> medir(String nombre, Future<void> Function() accion) async {
      // Una vuelta en frío y tres cronometradas: la primera paga la
      // preparación de la sentencia y el caché de páginas de SQLite, y
      // mezclarla con el resto esconde el costo estable.
      await accion();
      final reloj = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        await accion();
      }
      reloj.stop();
      medidas[nombre] = reloj.elapsedMilliseconds / 3;
      // ignore: avoid_print
      print('BANCO\tconsulta\t$nombre\t${medidas[nombre]}');
    }

    final db = await contenedor.read(databaseProvider.future);
    final hoy = DateTime.now();

    await medir('cargar productos', () async {
      contenedor.invalidate(productoNotifierProvider);
      await contenedor.read(productoNotifierProvider.future);
    });

    // El buscador NO consulta SQLite: filtra en Dart la lista que ya trajo
    // ProductoNotifier (decisión 0019). Se mide igual porque corre en cada
    // pulsación de tecla, así que su costo se paga muchas más veces.
    await medir('filtrar por "ca"', () async {
      contenedor.read(productoBusquedaProvider.notifier).state = 'ca';
      contenedor.read(productoQueryProvider);
      contenedor.read(productoBusquedaProvider.notifier).state = '';
      contenedor.read(productoQueryProvider);
    });

    for (final rango in RangoReporte.values) {
      await medir('reporte ${rango.name}', () async {
        final params = ReportesParametros(rango: rango, fechaReferencia: hoy);
        contenedor.invalidate(reportesProvider(params));
        await contenedor.read(reportesProvider(params).future);
      });
    }

    await medir('detalle del mes', () async {
      final params = ReportesParametros(rango: RangoReporte.mes, fechaReferencia: hoy);
      contenedor.invalidate(detalleRangoProvider(params));
      await contenedor.read(detalleRangoProvider(params).future);
    });

    await medir('contar ventas', () async {
      await db.rawQuery('SELECT COUNT(*) FROM venta');
    });
  });

  testWidgets('interfaz', (tester) async {
    // El arranque se mide aparte y ANTES de montar nada: es la queja concreta
    // —"tarda en abrir con sesión iniciada"— y lo que cuenta es el tiempo hasta
    // que la primera pantalla está utilizable, no el de un frame suelto.
    //
    // Desglosado por etapas, no un número suelto: "tarda 15 s" no dice qué
    // arreglar. Las etapas son las que la app hace de verdad al abrirse con
    // sesión ya iniciada.
    final etapas = <String, int>{};
    final arranque = Stopwatch()..start();

    // PRIMERO restaurar la sesión, antes de tocar el almacén seguro por
    // cualquier otra vía: en un arranque real ese almacén está frío, y si el
    // banco lo abriera antes estaría midiendo con la caché puesta y diría que
    // todo va rápido.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rol_activo_pista', 'gerente');
    final reloj = Stopwatch()..start();
    final contenedorSesion = ProviderContainer();
    await contenedorSesion.read(sesionRestauradaProvider.future);
    etapas['restaurar sesión (con pista)'] = reloj.elapsedMilliseconds;
    contenedorSesion.dispose();

    reloj.reset();
    await AppDatabase.open();
    etapas['abrir base'] = reloj.elapsedMilliseconds;

    // Las dos lecturas por separado: si la primera es lenta y la segunda no,
    // el costo es abrir el almacén (Keystore) y no leer el dato, y entonces no
    // sirve de nada optimizar la consulta.
    const almacen = FlutterSecureStorage();
    reloj.reset();
    await almacen.read(key: 'rol_activo');
    etapas['almacén seguro · 1ª lectura'] = reloj.elapsedMilliseconds;

    reloj.reset();
    await almacen.read(key: 'rol_activo');
    etapas['almacén seguro · 2ª lectura'] = reloj.elapsedMilliseconds;

    // Comparación con un almacén NO cifrado, sobre una clave inventada para no
    // tocar datos reales: si esto es instantáneo, el 1,2 s es el coste de abrir
    // el cifrado (Keystore), y entonces la decisión es dónde vive el rol, no
    // cómo se lee.
    reloj.reset();
    prefs.getString('medicion_banco');
    etapas['preferencias simples · lectura'] = reloj.elapsedMilliseconds;

    reloj.reset();
    final contenedor = ProviderContainer();
    await contenedor.read(productoNotifierProvider.future);
    etapas['cargar catálogo'] = reloj.elapsedMilliseconds;
    contenedor.dispose();

    reloj.reset();
    await _montar(tester);
    etapas['montar y asentar la interfaz'] = reloj.elapsedMilliseconds;
    arranque.stop();

    for (final etapa in etapas.entries) {
      // ignore: avoid_print
      print('BANCO\tarranque\t${etapa.key}\t${etapa.value}');
      interfaz['arranque · ${etapa.key}'] = {
        'total_ms': etapa.value,
        'frames': 0,
        'build_prom_ms': 0,
        'build_p90_ms': 0,
        'build_peor_ms': 0,
        'raster_prom_ms': 0,
        'raster_p90_ms': 0,
        'raster_peor_ms': 0,
        'frames_lentos': 0,
      };
    }
    interfaz['arranque hasta pantalla usable'] = {
      'total_ms': arranque.elapsedMilliseconds,
      'frames': 0,
      'build_prom_ms': 0,
      'build_p90_ms': 0,
      'build_peor_ms': 0,
      'raster_prom_ms': 0,
      'raster_p90_ms': 0,
      'raster_peor_ms': 0,
      'frames_lentos': 0,
    };
    // ignore: avoid_print
    print('BANCO\tinterfaz\tarranque\t${arranque.elapsedMilliseconds}');

    // Cada escenario se mide por separado para saber CUÁL cuesta, en vez de un
    // promedio de toda la sesión que no señala nada.
    for (final destino in [
      'nav_producto',
      'nav_reportes',
      'nav_configuracion',
      'nav_panel_venta',
    ]) {
      interfaz['ir a ${destino.substring(4)}'] = await _medirFrames(
        tester,
        'ir a ${destino.substring(4)}',
        () async {
          await tester.tap(find.byKey(ValueKey(destino)));
          await tester.pumpAndSettle();
        },
      );
    }

    interfaz['volver a venta rápida'] = await _medirFrames(
      tester,
      'volver a venta rápida',
      () async {
        await tester.tap(find.byKey(const ValueKey('nav_venta_rapida')));
        await tester.pumpAndSettle();
      },
    );

    Future<void> desplazar() async {
      final lista = find.byType(Scrollable).first;
      for (var i = 0; i < 4; i++) {
        await tester.fling(lista, const Offset(0, -400), 3000);
        await tester.pumpAndSettle();
      }
    }

    // Una vuelta de calentamiento antes de comparar: la primera paga la
    // compilación de shaders, y sin descartarla la segunda variante siempre
    // parece mejor. Esa trampa ya nos hizo aplicar un cambio inútil a cuatro
    // pantallas — ver docs/arquitectura/rendimiento.md.
    await _medirFrames(tester, 'calentando', desplazar);
    interfaz['desplazar catálogo'] = await _medirFrames(tester, 'desplazar catálogo', desplazar);

    // Y con el relieve apagado, que es lo que ofrece Configuración →
    // Optimización: sirve para saber cuánto gana de verdad quien lo apaga.
    await _montar(tester, efectosApagados: const {EfectoPesado.tallado});
    await _medirFrames(tester, 'calentando sin relieve', desplazar);
    interfaz['desplazar catálogo · sin relieve'] = await _medirFrames(
      tester,
      'desplazar catálogo · sin relieve',
      desplazar,
    );
    await _montar(tester);

    interfaz['escribir en el buscador'] = await _medirFrames(
      tester,
      'escribir en el buscador',
      () async {
        final campo = find.byType(TextField).first;
        await tester.tap(campo);
        await tester.pumpAndSettle();
        // Letra por letra: cada una vuelve a filtrar y reconstruye la lista,
        // que es el caso real y el que puede trabarse.
        for (final letra in ['c', 'a', 'f', 'e']) {
          await tester.enterText(campo, letra);
          await tester.pumpAndSettle();
        }
      },
    );
  });
}

Future<void> _montar(WidgetTester tester, {Set<EfectoPesado> efectosApagados = const {}}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferenciasNotifierProvider.overrideWith(() => _PreferenciasFijas(efectosApagados)),
        sesionNotifierProvider.overrideWith(() => _SesionGerente()),
        // También la restauración, y no por comodidad: sin esto la app hace el
        // arranque de verdad, la verificación no encuentra sesión en el almacén
        // seguro de este aparato y termina en el Login — con lo cual el
        // escenario mediría la pantalla equivocada. El coste del arranque ya se
        // mide arriba, aparte.
        sesionRestauradaProvider.overrideWith((ref) async {}),
      ],
      child: const VulpTiketingApp(),
    ),
  );
  // `pumpAndSettle()` a secas: su parámetro es el INTERVALO de cada bombeo, no
  // un límite de espera. Pasarle 5 s hacía que cada iteración avanzara 5 s de
  // reloj virtual y el montaje "medía" 15 s que no existen.
  await tester.pumpAndSettle();
}

/// Mide un escenario recogiendo los `FrameTiming` que emite el motor.
///
/// NO se usa `binding.traceAction`: esa API abre una conexión al VM service
/// desde dentro de la app y en este teléfono falla con
/// `SocketException: Connection refused`. Los `FrameTiming` llegan por
/// callback, sin sockets de por medio, y traen exactamente lo que hace falta.
///
/// Los dos números dicen cosas distintas: *build* es Dart —reconstruir
/// widgets, esperar consultas—, *raster* es la GPU pintando. Un tirón con
/// build alto se arregla en el código; uno con raster alto, en lo que se
/// dibuja.
Future<Map<String, Object>> _medirFrames(
  WidgetTester tester,
  String nombre,
  Future<void> Function() accion,
) async {
  final tiempos = <FrameTiming>[];
  void recoger(List<FrameTiming> nuevos) => tiempos.addAll(nuevos);

  final reloj = Stopwatch()..start();
  tester.binding.addTimingsCallback(recoger);
  await accion();
  // Un pump extra: los FrameTiming del último frame llegan DESPUÉS de que
  // termina la acción, y sin esto el escenario se cerraba perdiéndolos.
  await tester.pump(const Duration(milliseconds: 50));
  tester.binding.removeTimingsCallback(recoger);
  reloj.stop();

  double ms(Duration d) => d.inMicroseconds / 1000;
  final builds = tiempos.map((t) => ms(t.buildDuration)).toList()..sort();
  final rasters = tiempos.map((t) => ms(t.rasterDuration)).toList()..sort();
  double percentil(List<double> xs, double p) =>
      xs.isEmpty ? 0 : xs[(xs.length * p).clamp(0, xs.length - 1).floor()];
  double promedio(List<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  final medida = <String, Object>{
    'total_ms': reloj.elapsedMilliseconds,
    'frames': tiempos.length,
    'build_prom_ms': promedio(builds),
    'build_p90_ms': percentil(builds, 0.9),
    'build_peor_ms': builds.isEmpty ? 0 : builds.last,
    'raster_prom_ms': promedio(rasters),
    'raster_p90_ms': percentil(rasters, 0.9),
    'raster_peor_ms': rasters.isEmpty ? 0 : rasters.last,
    'frames_lentos': tiempos.where((t) => ms(t.buildDuration) + ms(t.rasterDuration) > 16.7).length,
  };
  // ignore: avoid_print
  print('BANCO\tinterfaz\t$nombre\t${medida['total_ms']}');
  return medida;
}

class _PreferenciasFijas extends PreferenciasNotifier {
  _PreferenciasFijas(this.apagados);

  final Set<EfectoPesado> apagados;

  @override
  Future<Preferencias> build() async => Preferencias(efectosApagados: apagados);
}

class _SesionGerente extends SesionNotifier {
  @override
  Rol? build() => Rol.gerente;
}
