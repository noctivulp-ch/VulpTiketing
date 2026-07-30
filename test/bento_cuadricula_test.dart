import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_cuadricula.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';

/// La retícula de 6 columnas ([decisión 0026](../docs/decisiones/0026-cuadricula-bento-y-breakpoints.md)).
///
/// Lo que se prueba es la propiedad que la hace valer la pena: que las celdas
/// caigan SIEMPRE en una retícula, en los tres tamaños. Si una fila estirara sus
/// celdas para rellenar el hueco, o si dos celdas de la misma fila tuvieran
/// alturas distintas, el resultado dejaría de leerse como una caja bento — que
/// es justamente lo que este widget existe para garantizar.
void main() {
  /// La ventana de prueba mide 800×600 por defecto y RECORTA cualquier hijo más
  /// ancho, así que un `SizedBox(width: 1440)` mediría 800 sin avisar. Hay que
  /// dimensionar la superficie de verdad para poder probar el tamaño amplio.
  Future<void> montar(WidgetTester tester, Widget hijo, {double ancho = 360}) async {
    tester.view.physicalSize = Size(ancho, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildBentoTheme(AcentoTinte.oro),
      home: Scaffold(body: hijo),
    ));
  }

  BentoCelda celda(String nombre,
          {required int compacto, required int medio, required int amplio}) =>
      BentoCelda(
        compacto: compacto,
        medio: medio,
        amplio: amplio,
        hijo: Text(nombre, key: ValueKey(nombre)),
      );

  double anchoDe(WidgetTester tester, String nombre) =>
      tester.getSize(find.byKey(ValueKey(nombre))).width;

  group('los cortes de tamaño', () {
    test('360 dp es compacto; 600 y 800 son medio; 1024 en adelante es amplio', () {
      expect(BentoAncho.deAncho(360), BentoAncho.compacto);
      expect(BentoAncho.deAncho(599), BentoAncho.compacto);
      expect(BentoAncho.deAncho(600), BentoAncho.medio);
      expect(BentoAncho.deAncho(800), BentoAncho.medio);
      expect(BentoAncho.deAncho(1023), BentoAncho.medio);
      expect(BentoAncho.deAncho(1024), BentoAncho.amplio);
      expect(BentoAncho.deAncho(1920), BentoAncho.amplio);
    });
  });

  testWidgets('una celda de 6 columnas ocupa el ancho entero', (tester) async {
    await montar(tester,
      BentoCuadricula(hijos: [
        celda('hero', compacto: 6, medio: 6, amplio: 6),
      ]),
      ancho: 360,
    );

    expect(anchoDe(tester, 'hero'), closeTo(360, 0.5));
  });

  testWidgets('tres celdas de 2 columnas caben en una sola fila', (tester) async {
    // Es el caso de los tres turnos de Reportes, que hoy revientan a 360 dp
    // porque comparten fila con el hero.
    await montar(tester,
      BentoCuadricula(hijos: [
        for (final t in ['manana', 'tarde', 'noche'])
          celda(t, compacto: 2, medio: 2, amplio: 2),
      ]),
      ancho: 360,
    );

    final y = [
      for (final t in ['manana', 'tarde', 'noche'])
        tester.getTopLeft(find.byKey(ValueKey(t))).dy,
    ];
    expect(y.toSet(), hasLength(1), reason: 'las tres tienen que estar en la misma fila');

    // 360 - 2 paredes de 12 = 336, repartidos en tres.
    for (final t in ['manana', 'tarde', 'noche']) {
      expect(anchoDe(tester, t), closeTo(112, 0.5));
    }
  });

  testWidgets('una celda que no entra en la fila abre una nueva', (tester) async {
    await montar(tester,
      BentoCuadricula(hijos: [
        celda('a', compacto: 4, medio: 4, amplio: 4),
        celda('b', compacto: 4, medio: 4, amplio: 4),
      ]),
    );

    final ya = tester.getTopLeft(find.byKey(const ValueKey('a'))).dy;
    final yb = tester.getTopLeft(find.byKey(const ValueKey('b'))).dy;
    expect(yb, greaterThan(ya), reason: '4 + 4 no entran en 6 columnas');
  });

  testWidgets('una fila a medio llenar NO estira sus celdas', (tester) async {
    // Si la última fila estirara su única celda al ancho completo, esa celda
    // sería más ancha que las de arriba y la retícula dejaría de verse como una
    // retícula. Es el defecto tipico de resolver esto con un Wrap.
    await montar(tester,
      BentoCuadricula(hijos: [
        celda('a', compacto: 3, medio: 3, amplio: 3),
        celda('b', compacto: 3, medio: 3, amplio: 3),
        celda('sola', compacto: 3, medio: 3, amplio: 3),
      ]),
    );

    expect(anchoDe(tester, 'sola'), closeTo(anchoDe(tester, 'a'), 0.5));
    expect(anchoDe(tester, 'sola'), lessThan(300));
  });

  testWidgets('las celdas de una fila comparten altura', (tester) async {
    await montar(tester,
      BentoCuadricula(hijos: [
        BentoCelda(
          compacto: 3, medio: 3, amplio: 3,
          hijo: Container(key: const ValueKey('baja'), color: Colors.red, height: 20),
        ),
        BentoCelda(
          compacto: 3, medio: 3, amplio: 3,
          hijo: Container(key: const ValueKey('alta'), color: Colors.blue, height: 80),
        ),
      ]),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('baja'))).height,
      equals(tester.getSize(find.byKey(const ValueKey('alta'))).height),
      reason: 'alturas distintas en la misma fila rompen la lectura de bandeja',
    );
  });

  testWidgets('la misma composicion cambia de forma en los tres tamaños', (tester) async {
    // Esta es la razon de ser del sistema: una sola declaracion, tres formas.
    List<BentoCelda> composicion() => [
          celda('hero', compacto: 6, medio: 6, amplio: 3),
          celda('t1', compacto: 2, medio: 2, amplio: 1),
          celda('t2', compacto: 2, medio: 2, amplio: 1),
          celda('t3', compacto: 2, medio: 2, amplio: 1),
        ];

    Future<int> filasCon(double ancho) async {
      await montar(tester, BentoCuadricula(hijos: composicion()), ancho: ancho);
      final alturas = <double>{
        for (final k in ['hero', 't1', 't2', 't3'])
          tester.getTopLeft(find.byKey(ValueKey(k))).dy,
      };
      return alturas.length;
    }

    expect(await filasCon(360), 2, reason: 'compacto: hero solo, y los 3 turnos debajo');
    expect(await filasCon(1440), 1, reason: 'amplio: hero(3) + 3 turnos(1) = 6 en una fila');
  });

  testWidgets('anchoForzado permite componer contra una caja y no contra la ventana',
      (tester) async {
    // Un panel angosto dentro de un escritorio ancho tiene que componerse como
    // teléfono, no como escritorio.
    await montar(tester,
      BentoCuadricula(
        anchoForzado: BentoAncho.compacto,
        hijos: [
          celda('hero', compacto: 6, medio: 3, amplio: 1),
        ],
      ),
      ancho: 1440,
    );

    expect(anchoDe(tester, 'hero'), closeTo(1440, 0.5),
        reason: 'con anchoForzado compacto usa el span de compacto, que es 6');
  });
}
