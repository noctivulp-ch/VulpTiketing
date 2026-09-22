import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vulp_tiketing/core/moneda.dart';
import 'package:vulp_tiketing/features/configuracion/preferencias_notifier.dart';
import 'package:vulp_tiketing/features/reportes/reporte_export_service.dart';

/// La moneda es de presentación (0043): cambia cómo se leen y se capturan los
/// montos, nunca lo guardado. Lo que se vigila: colones enteros sin
/// configurar nada; símbolo y decimales cuando se configuran; que llegue a
/// todo widget por el árbol y al PDF por parámetro; que sobreviva al
/// reinicio.
void main() {
  test('de fábrica: colones enteros; con decimales forzados para los costos', () {
    expect(Moneda.colon.formatear(3000), '₡3000');
    expect(Moneda.colon.formatear(3000.4), '₡3000');
    expect(Moneda.colon.formatear(4.639, decimales: 2), '₡4.64');
    expect(Moneda.colon.entreParentesis, '(₡)');
  });

  test('dólares con centavos', () {
    const usd = Moneda(simbolo: r'$', decimales: 2);
    expect(usd.formatear(12.5), r'$12.50');
    expect(usd.formatear(1234.567), r'$1234.57');
  });

  testWidgets('llega por el árbol a un widget sin ref, y sin scope vale colones', (tester) async {
    late String conScope;
    late String sinScope;
    await tester.pumpWidget(
      Column(
        textDirection: TextDirection.ltr,
        children: [
          MonedaScope(
            moneda: const Moneda(simbolo: '€', decimales: 2),
            child: Builder(builder: (context) {
              conScope = Moneda.de(context).formatear(9.5);
              return const SizedBox();
            }),
          ),
          Builder(builder: (context) {
            sinScope = Moneda.de(context).formatear(9.5);
            return const SizedBox();
          }),
        ],
      ),
    );
    expect(conScope, '€9.50');
    expect(sinScope, '₡10', reason: 'sin scope, colones enteros: las pruebas de widget sueltas siguen valiendo');
  });

  test('la preferencia se guarda y vuelve tras reiniciar', () async {
    SharedPreferences.setMockInitialValues({});
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    expect((await c1.read(preferenciasNotifierProvider.future)).moneda, Moneda.colon);
    await c1.read(preferenciasNotifierProvider.notifier).cambiarMoneda(const Moneda(simbolo: 'US\$', decimales: 2));

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final leida = (await c2.read(preferenciasNotifierProvider.future)).moneda;
    expect(leida.simbolo, 'US\$');
    expect(leida.decimales, 2);
  });

  test('el exportador escribe con la moneda que le dan', () {
    const servicio = ReporteExportService(moneda: Moneda(simbolo: r'$', decimales: 2));
    expect(servicio.moneda.formatear(3), r'$3.00');
    expect(const ReporteExportService().moneda, Moneda.colon);
  });
}
