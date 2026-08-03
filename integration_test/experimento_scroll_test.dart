// Experimento: qué encarece el RASTER al desplazar el catálogo.
//
//   flutter drive --driver=test_driver/banco_driver.dart \
//     --target=integration_test/experimento_scroll_test.dart --profile -d <id>
//
// El banco dejó 102 de 106 frames fuera de presupuesto al desplazar, con el
// costo en raster (19,5 ms) y no en build (3,4). Raster es la GPU pintando, o
// sea que la culpa está en QUÉ se dibuja, no en el código que lo arma. Los
// sospechosos son los tres adornos de la tarjeta: el texto tallado —que pinta
// el mismo texto varias veces desplazado—, la cresta de 1 px y el velo
// superior con su degradado.
//
// Se mide con los widgets REALES en una cuadrícula igual a la de Venta Rápida,
// variante por variante. No se toca la pantalla de producción: primero hay que
// saber cuál es el culpable, y para eso hace falta poder apagarlos de a uno.
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vulp_tiketing/core/theme/bento_bandeja.dart';
import 'package:vulp_tiketing/core/theme/bento_tallado.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/core/theme/bento_velo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> medir(WidgetTester tester, String etiqueta, Widget pantalla) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildBentoTheme(AcentoTinte.jade, brightness: Brightness.dark),
        home: Scaffold(body: pantalla),
      ),
    );
    await tester.pumpAndSettle();

    final tiempos = <FrameTiming>[];
    void recoger(List<FrameTiming> nuevos) => tiempos.addAll(nuevos);
    tester.binding.addTimingsCallback(recoger);
    for (var i = 0; i < 4; i++) {
      await tester.fling(find.byType(GridView), const Offset(0, -500), 3000);
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 50));
    tester.binding.removeTimingsCallback(recoger);

    double ms(Duration d) => d.inMicroseconds / 1000;
    final rasters = tiempos.map((t) => ms(t.rasterDuration)).toList()..sort();
    final builds = tiempos.map((t) => ms(t.buildDuration)).toList()..sort();
    double prom(List<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
    final lentos = tiempos.where((t) => ms(t.buildDuration) + ms(t.rasterDuration) > 16.7).length;
    // ignore: avoid_print
    print(
      'EXPERIMENTO\t$etiqueta\traster ${prom(rasters).toStringAsFixed(1)}\t'
      'build ${prom(builds).toStringAsFixed(1)}\tlentos $lentos/${tiempos.length}',
    );
  }

  testWidgets('qué cuesta al desplazar', (tester) async {
    const variantes = <String, Widget>{
      'como está': _Catalogo(),
      'sin texto tallado': _Catalogo(tallado: false),
      'sin velo superior': _Catalogo(velo: false),
      'con RepaintBoundary por tarjeta': _Catalogo(aislarTarjetas: true),
      'sin tallado y sin velo': _Catalogo(tallado: false, velo: false),
    };

    // DOS pasadas, y solo cuenta la segunda.
    //
    // La primera versión de este experimento medía cada variante una vez, en
    // orden, y daba una mejora enorme a las últimas. Era mentira: lo que
    // mejoraba era el proceso, que ya tenía compilados los shaders y caliente
    // la GPU. Con esa medición se llegó a "RepaintBoundary baja el raster un
    // 68 %", se aplicó a las cuatro listas de la app, y el banco sobre la
    // pantalla real no mostró ninguna diferencia — porque Flutter YA envuelve
    // cada ítem de una lista (`addRepaintBoundaries` es true por defecto).
    for (final calentando in [true, false]) {
      for (final v in variantes.entries) {
        await medir(tester, calentando ? 'calentando · ${v.key}' : v.key, v.value);
      }
    }
  });
}

/// La misma cuadrícula de Venta Rápida: tarjeta = pozo con nombre y precio.
class _Catalogo extends StatelessWidget {
  const _Catalogo({this.tallado = true, this.velo = true, this.aislarTarjetas = false});

  final bool tallado;
  final bool velo;
  final bool aislarTarjetas;

  @override
  Widget build(BuildContext context) {
    final grid = GridView.builder(
      padding: const EdgeInsets.all(BentoSpacing.pared),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: BentoSpacing.pared,
        crossAxisSpacing: BentoSpacing.pared,
        childAspectRatio: 1.1,
      ),
      itemCount: 120,
      itemBuilder: (context, i) {
        Widget tarjeta = _Tarjeta(indice: i, tallado: tallado);
        if (aislarTarjetas) tarjeta = RepaintBoundary(child: tarjeta);
        return tarjeta;
      },
    );
    if (!velo) return grid;
    return Stack(children: [grid, const BentoVeloSuperior()]);
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.indice, required this.tallado});

  final int indice;
  final bool tallado;

  @override
  Widget build(BuildContext context) {
    final precio = '₡${(500 + indice * 25)}';
    return BentoPozo(
      onTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Café con leche variante $indice'),
          const Spacer(),
          if (tallado)
            BentoTextoTallado(
              precio,
              sobre: lacaDe(context).pozo,
              nivel: TalladoNivel.marcado,
              estilo: Theme.of(context).textTheme.titleLarge,
            )
          else
            Text(precio, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}
