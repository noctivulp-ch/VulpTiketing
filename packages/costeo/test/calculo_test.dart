import 'package:costeo/costeo.dart';
import 'package:test/test.dart';

/// Las fórmulas de la hoja, con números a mano. Cada prueba cita la sección
/// de `01-modelo-de-costos.md` que reproduce; si una cifra cambia acá, cambió
/// el modelo, no un detalle.
void main() {
  const config = ConfigCosteo(
    diasAbiertosMes: 26,
    margenObjetivo: 0.60,
    comisionMediosPago: 0.03,
    mermaPorDefecto: 0.05,
    tarifaManoObraHora: 6000,
    redondeoPrecio: 50,
  );

  // §1: harina, bulto de 1 kg a 4.500 → 4,5 por gramo; con 3 % de merma, 4,639.
  const harina = Insumo(
    id: 'harina',
    nombre: 'Harina',
    unidadBase: UnidadBase.gramo,
    contenidoPorCompra: 1000,
    precioCompra: 4500,
    merma: 0.03,
  );
  // Sin merma propia: usa la global del 5 %.
  const huevo = Insumo(
    id: 'huevo',
    nombre: 'Huevo',
    unidadBase: UnidadBase.unidad,
    contenidoPorCompra: 30,
    precioCompra: 3000,
  );

  group('§1 costo de insumos', () {
    test('costo por unidad base y merma que se divide, no se multiplica', () {
      expect(harina.costoPorUnidadBase, 4.5);
      expect(harina.costoEfectivo(0.05), closeTo(4.5 / 0.97, 1e-9)); // 4,639: la propia, no la global
      expect(huevo.costoPorUnidadBase, 100);
      expect(huevo.costoEfectivo(0.05), closeTo(100 / 0.95, 1e-9)); // la global
    });

    test('la receta es por lote y el costo por unidad sale de dividir', () {
      // 500 g de harina y 3 huevos para 12 queques.
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [],
        insumos: const [harina, huevo],
        articulos: const [Articulo(id: 'q', nombre: 'Queque', precioActual: 0, unidadesPorLote: 12)],
        recetas: const [
          LineaReceta(articuloId: 'q', insumoId: 'harina', cantidadPorLote: 500),
          LineaReceta(articuloId: 'q', insumoId: 'huevo', cantidadPorLote: 3),
        ],
      );
      final q = r.articulos.single;
      final lote = 500 * (4.5 / 0.97) + 3 * (100 / 0.95);
      expect(q.costoInsumosLote, closeTo(lote, 1e-9));
      expect(q.costoInsumosUnidad, closeTo(lote / 12, 1e-9));
      expect(q.lineas.map((l) => l.insumoNombre), ['Harina', 'Huevo']);
    });
  });

  test('§2 mano de obra: minutos del lote por la tarifa, entre las unidades', () {
    final r = calcularCatalogo(
      config: config,
      costosFijos: const [],
      insumos: const [],
      articulos: const [Articulo(id: 'q', nombre: 'Queque', precioActual: 0, unidadesPorLote: 12, minutosLote: 90)],
      recetas: const [],
    );
    // 90 min = 1,5 h × 6.000 = 9.000 el lote → 750 por queque.
    expect(r.articulos.single.manoObraUnidad, closeTo(750, 1e-9));
  });

  group('§4 costos fijos', () {
    const fijos = [
      CostoFijo(id: 'a', concepto: 'Alquiler', montoMensual: 200000),
      CostoFijo(id: 's', concepto: 'Servicios', montoMensual: 60000),
    ];
    const soda = Articulo(id: 's', nombre: 'Soda', precioActual: 0, unidadesMes: 900, minutosLote: 2);
    const queque = Articulo(id: 'q', nombre: 'Queque', precioActual: 0, unidadesMes: 100, minutosLote: 90);

    test('por UNIDAD cada una absorbe lo mismo', () {
      final r = calcularCatalogo(config: config, costosFijos: fijos, insumos: const [], articulos: const [soda, queque], recetas: const []);
      expect(r.costosFijosMes, 260000);
      expect(r.totalUnidadesMes, 1000);
      for (final a in r.articulos) {
        expect(a.overheadUnidad, closeTo(260, 1e-9));
      }
    });

    test('por TIEMPO absorbe según los minutos', () {
      final r = calcularCatalogo(
        config: const ConfigCosteo(metodoReparto: MetodoReparto.tiempo),
        costosFijos: fijos,
        insumos: const [],
        articulos: const [soda, queque],
        recetas: const [],
      );
      // minutos: soda 2×900 = 1.800; queque 90×100 = 9.000; total 10.800.
      expect(r.totalMinutosMes, 10800);
      expect(r.articulos[0].overheadUnidad, closeTo(260000 * 2 / 10800, 1e-9));
      expect(r.articulos[1].overheadUnidad, closeTo(260000 * 90 / 10800, 1e-9));
      // La soda se lleva 43 y el queque 2.167: el horno lo paga quien lo ocupa.
      expect(r.articulos[1].overheadUnidad, greaterThan(r.articulos[0].overheadUnidad * 40));
    });

    test('cambiar el volumen de UNO mueve el overhead de TODOS', () {
      final antes = calcularCatalogo(config: config, costosFijos: fijos, insumos: const [], articulos: const [soda, queque], recetas: const []);
      final despues = calcularCatalogo(
        config: config,
        costosFijos: fijos,
        insumos: const [],
        articulos: const [Articulo(id: 's', nombre: 'Soda', precioActual: 0, unidadesMes: 1900), queque],
        recetas: const [],
      );
      expect(despues.articulos[1].overheadUnidad, lessThan(antes.articulos[1].overheadUnidad));
    });

    test('sin volumen nadie absorbe y se avisa', () {
      final r = calcularCatalogo(
        config: config,
        costosFijos: fijos,
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 0)],
        recetas: const [],
      );
      expect(r.articulos.single.overheadUnidad, 0);
      expect(r.articulos.single.alertas, contains(Alerta.sinVolumen));
    });
  });

  group('§5 precio', () {
    test('sugerido = costo / (1 − margen − comisión); redondeado hacia arriba; más ajuste', () {
      // Costo total 1.000 → 1000 / 0.37 = 2.702,70 → techo a 50 = 2.750 → +(-50) = 2.700.
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 0, otrosCostosDirectos: 1000, ajustePrecio: -50, unidadesMes: 1, volumenEsReal: true)],
        recetas: const [],
      );
      final x = r.articulos.single;
      expect(x.precioSugerido, closeTo(1000 / 0.37, 1e-9));
      expect(x.precioRedondeado, 2750);
      expect(x.precioFinal, 2700);
    });

    test('margen + comisión ≥ 1 no tiene precio y es error', () {
      final r = calcularCatalogo(
        config: const ConfigCosteo(margenObjetivo: 0.98, comisionMediosPago: 0.03),
        costosFijos: const [],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 100)],
        recetas: const [],
      );
      expect(r.alertasGlobales, contains(Alerta.metaImposible));
      expect(r.articulos.single.precioSugerido.isNaN, isTrue);
      expect(r.articulos.single.tieneErrores, isTrue);
    });

    test('el margen propio del artículo manda sobre el global', () {
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 0, otrosCostosDirectos: 100, margenObjetivo: 0.5)],
        recetas: const [],
      );
      expect(r.articulos.single.precioSugerido, closeTo(100 / 0.47, 1e-9));
    });
  });

  group('§6 margen real contra el precio ACTUAL, no contra el sugerido', () {
    test('lo que se cobra hoy sostiene o no el margen', () {
      // Costo 1.000; se cobra 2.000: utilidad = 2000 − 1000 − 60 = 940 → 47 % < 60 %.
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 2000, otrosCostosDirectos: 1000, unidadesMes: 10, volumenEsReal: true)],
        recetas: const [],
      );
      final x = r.articulos.single;
      expect(x.utilidadUnidad, closeTo(940, 1e-9));
      expect(x.margenReal, closeTo(0.47, 1e-9));
      expect(x.alertas, contains(Alerta.margenBajoObjetivo));
      expect(x.alertas, isNot(contains(Alerta.seVendeAPerdida)));
      expect(x.diferenciaConSugerido, lessThan(0), reason: 'se cobra menos que lo que dice el modelo');
    });

    test('a pérdida es error', () {
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 800, otrosCostosDirectos: 1000)],
        recetas: const [],
      );
      expect(r.articulos.single.alertas, contains(Alerta.seVendeAPerdida));
      expect(r.articulos.single.tieneErrores, isTrue);
    });

    test('sin precio actual no hay margen real que medir', () {
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 0, otrosCostosDirectos: 1000)],
        recetas: const [],
      );
      expect(r.articulos.single.margenReal, isNull);
    });
  });

  group('§7 punto de equilibrio', () {
    test('unidades que pagan los costos fijos, meta diaria y colchón', () {
      // Un artículo: se cobra 2.000, variable 1.000, comisión 60 → contribución 940.
      // Costos fijos 188.000 → equilibrio 200 unidades; se venden 250 → colchón 25 %.
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [CostoFijo(id: 'a', concepto: 'Alquiler', montoMensual: 188000)],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 2000, otrosCostosDirectos: 1000, unidadesMes: 250, volumenEsReal: true)],
        recetas: const [],
      );
      expect(r.contribucionUnidad, closeTo(940, 1e-9));
      expect(r.unidadesEquilibrio, closeTo(200, 1e-9));
      expect(r.unidadesEquilibrioDia(26), closeTo(200 / 26, 1e-9));
      expect(r.colchon, closeTo(0.25, 1e-9));
      expect(r.ingresoMes, 500000);
      expect(r.utilidadMes, closeTo((2000 - 1000 - 188000 / 250 - 60) * 250, 1e-6));
    });

    test('sin contribución positiva no hay equilibrio', () {
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [CostoFijo(id: 'a', concepto: 'Alquiler', montoMensual: 1000)],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 500, otrosCostosDirectos: 1000, unidadesMes: 10)],
        recetas: const [],
      );
      expect(r.unidadesEquilibrio, isNull);
    });
  });

  group('alertas de datos', () {
    test('receta con insumo que ya no existe, y volumen estimado', () {
      final r = calcularCatalogo(
        config: config,
        costosFijos: const [],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 100, unidadesMes: 5)],
        recetas: const [LineaReceta(articuloId: 'x', insumoId: 'fantasma', cantidadPorLote: 1)],
      );
      final x = r.articulos.single;
      expect(x.alertas, containsAll([Alerta.insumoDesconocido, Alerta.sinReceta, Alerta.volumenEstimado]));
    });

    test('reparto por tiempo sin minutos avisa', () {
      final r = calcularCatalogo(
        config: const ConfigCosteo(metodoReparto: MetodoReparto.tiempo),
        costosFijos: const [],
        insumos: const [],
        articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 100, unidadesMes: 5, volumenEsReal: true)],
        recetas: const [],
      );
      expect(r.articulos.single.alertas, contains(Alerta.sinTiempo));
    });
  });

  group('impuestos', pruebasDeImpuestos);

  test('es determinista: dos llamadas iguales dan lo mismo', () {
    ResultadoCosteo correr() => calcularCatalogo(
      config: config,
      costosFijos: const [CostoFijo(id: 'a', concepto: 'A', montoMensual: 1234)],
      insumos: const [harina, huevo],
      articulos: const [Articulo(id: 'q', nombre: 'Queque', precioActual: 1500, unidadesPorLote: 12, minutosLote: 90, unidadesMes: 40, volumenEsReal: true)],
      recetas: const [LineaReceta(articuloId: 'q', insumoId: 'harina', cantidadPorLote: 500)],
    );
    final a = correr();
    final b = correr();
    expect(a.articulos.single.precioFinal, b.articulos.single.precioFinal);
    expect(a.utilidadMes, b.utilidadMes);
  });
}

// ── Impuestos (decisión 0042) ────────────────────────────────────────────────
void pruebasDeImpuestos() {
  const base = ConfigCosteo(margenObjetivo: 0.5, comisionMediosPago: 0, mermaPorDefecto: 0, redondeoPrecio: 1);

  test('régimen general: el IVA va dentro del precio como fracción tasa/(1+tasa)', () {
    // Costo 1.000, margen 50 %, IVA 13 % → fracción 0,1150 → precio = 1000 / (1 − 0,5 − 0,1150).
    final r = calcularCatalogo(
      config: base,
      costosFijos: const [],
      insumos: const [],
      articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 2600, otrosCostosDirectos: 1000, tasaImpuesto: 0.13, unidadesMes: 10, volumenEsReal: true)],
      recetas: const [],
    );
    final x = r.articulos.single;
    expect(x.articulo.fraccionImpuestoDelPrecio, closeTo(0.13 / 1.13, 1e-9));
    expect(x.precioSugerido, closeTo(1000 / (0.5 - 0.13 / 1.13), 1e-9));
    // Al precio actual de 2.600: 299,1 de IVA dentro; utilidad = 2600 − 1000 − 299,1.
    expect(x.impuestoPrecioUnidad, closeTo(2600 * 0.13 / 1.13, 1e-6));
    expect(x.utilidadUnidad, closeTo(2600 - 1000 - 2600 * 0.13 / 1.13, 1e-6));
    expect(r.impuestoSobrePrecioMes, closeTo(2600 * 0.13 / 1.13 * 10, 1e-6));
  });

  test('régimen simplificado: el impuesto es una fracción del costo de insumos, no del precio', () {
    // Insumo 800 por unidad; factores 3 % + 2,5 % = 5,5 % → 44 de impuesto por unidad.
    final r = calcularCatalogo(
      config: const ConfigCosteo(margenObjetivo: 0.5, comisionMediosPago: 0, mermaPorDefecto: 0, redondeoPrecio: 1, impuestoSobreCompras: 0.055),
      costosFijos: const [],
      insumos: const [Insumo(id: 'i', nombre: 'I', unidadBase: UnidadBase.unidad, contenidoPorCompra: 1, precioCompra: 800)],
      articulos: const [Articulo(id: 'x', nombre: 'X', precioActual: 2000, unidadesMes: 10, volumenEsReal: true)],
      recetas: const [LineaReceta(articuloId: 'x', insumoId: 'i', cantidadPorLote: 1)],
    );
    final x = r.articulos.single;
    expect(x.impuestoComprasUnidad, closeTo(44, 1e-9));
    expect(x.costoTotalUnidad, closeTo(844, 1e-9));
    expect(x.precioSugerido, closeTo(844 / 0.5, 1e-9));
    expect(x.impuestoPrecioUnidad, 0);
    expect(r.impuestoSobrePrecioMes, 0);
    // Y entra en la contribución como costo variable.
    expect(r.contribucionUnidad, closeTo(2000 - 844, 1e-9));
  });
}
