import 'package:costeo/costeo.dart' as c;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import '../producto/producto_model.dart';
import '../producto/producto_notifier.dart';
import '../producto/variante_model.dart';
import '../venta/lectura_de_libros.dart';
import '../venta/libro_ventas.dart';
import 'articulo_costeo_model.dart';
import 'config_costeo_model.dart';
import 'costeo_notifiers.dart';
import 'costo_de_insumos_provider.dart';

/// Cuántos días hacia atrás se mira para el volumen real. Un mes rodante y
/// no el mes calendario: el día 3 de un mes, "este mes" son dos días.
const diasDeVolumen = 30;

/// Unidades vendidas por artículo en los últimos [diasDeVolumen] días,
/// leídas de los libros (cerrados incluidos).
///
/// La clave es la de `ArticuloCosteoRegistro.claveDe`. Una línea sin variante
/// de un producto que hoy las tiene —vendida antes de que existieran— se
/// atribuye a la por defecto: es lo que se vendía.
final volumenRealProvider = FutureProvider<Map<String, int>>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final productos = await ref.watch(productoNotifierProvider.future);
  final lector = LectorDeLibros(db, () => ref.read(libroVentasServiceProvider.future));
  final hasta = DateTime.now().add(const Duration(days: 1));
  final desde = DateTime(hasta.year, hasta.month, hasta.day).subtract(const Duration(days: diasDeVolumen));

  final porProducto = {for (final p in productos) p.id: p};
  final volumen = <String, int>{};
  for (final filas in await lector.enCadaLibro(desde, hasta, (e) => db.rawQuery('''
    SELECT lv.producto_id AS producto_id, lv.variante AS variante, SUM(lv.cantidad) AS cantidad
    FROM $e.linea_venta lv
    JOIN $e.venta v ON v.id = lv.venta_id
    WHERE v.estado = 'activa' AND v.fecha_hora >= ? AND v.fecha_hora < ? AND lv.producto_id IS NOT NULL
    GROUP BY lv.producto_id, lv.variante
  ''', [desde.toIso8601String(), hasta.toIso8601String()]))) {
    for (final f in filas) {
      final producto = porProducto[f['producto_id'] as String];
      if (producto == null) continue;
      final nombreVariante = f['variante'] as String?;
      final variante = nombreVariante == null
          ? producto.variantePorDefecto
          : producto.variantes.where((v) => v.nombre == nombreVariante).firstOrNull;
      final clave = ArticuloCosteoRegistro.claveDe(producto.id, variante?.id ?? '');
      volumen[clave] = (volumen[clave] ?? 0) + (f['cantidad'] as num).toInt();
    }
  }
  return volumen;
});

/// Qué parte del dinero de los últimos [diasDeVolumen] días entró por SINPE
/// (0..1). Es lo que pondera las comisiones por medio de pago (0042): la
/// comisión efectiva del negocio es la que de verdad se paga, no una cifra
/// escrita a mano.
final mixDePagoProvider = FutureProvider<double>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final lector = LectorDeLibros(db, () => ref.read(libroVentasServiceProvider.future));
  final hasta = DateTime.now().add(const Duration(days: 1));
  final desde = DateTime(hasta.year, hasta.month, hasta.day).subtract(const Duration(days: diasDeVolumen));
  var total = 0.0;
  var sinpe = 0.0;
  for (final filas in await lector.enCadaLibro(desde, hasta, (e) => db.rawQuery('''
    SELECT v.metodo_pago AS metodo, SUM(lv.precio_aplicado * lv.cantidad) AS total
    FROM $e.linea_venta lv JOIN $e.venta v ON v.id = lv.venta_id
    WHERE v.estado = 'activa' AND v.fecha_hora >= ? AND v.fecha_hora < ?
    GROUP BY v.metodo_pago
  ''', [desde.toIso8601String(), hasta.toIso8601String()]))) {
    for (final f in filas) {
      final monto = (f['total'] as num?)?.toDouble() ?? 0;
      total += monto;
      if (f['metodo'] == 'sinpe') sinpe += monto;
    }
  }
  return total <= 0 ? 0 : sinpe / total;
});

/// El `ConfigCosteo` que consume el cálculo, construido desde los parámetros
/// guardados: la comisión ponderada por el mix real y el impuesto sobre
/// compras si el régimen es simplificado.
c.ConfigCosteo configEfectiva(ConfigCosteoRegistro registro, double fraccionSinpe) => c.ConfigCosteo(
  diasAbiertosMes: registro.config.diasAbiertosMes,
  margenObjetivo: registro.config.margenObjetivo,
  comisionMediosPago: registro.comisionSinpe * fraccionSinpe + registro.comisionEfectivo * (1 - fraccionSinpe),
  mermaPorDefecto: registro.config.mermaPorDefecto,
  tarifaManoObraHora: registro.config.tarifaManoObraHora,
  redondeoPrecio: registro.config.redondeoPrecio,
  metodoReparto: registro.config.metodoReparto,
  impuestoSobreCompras: registro.impuestoSobreCompras,
);

/// Un artículo del catálogo con lo que lo identifica en pantalla.
class ArticuloDelCatalogo {
  const ArticuloDelCatalogo({required this.producto, this.variante, this.registro});
  final Producto producto;
  final Variante? variante;

  /// Nulo si nunca se costeó: vale con los valores de fábrica.
  final ArticuloCosteoRegistro? registro;

  String get clave => ArticuloCosteoRegistro.claveDe(producto.id, variante?.id ?? '');
  String get nombre => variante == null ? producto.nombre : '${producto.nombre} · ${variante!.nombre}';
  double get precioActual => variante?.precio ?? producto.precioBase;
}

/// El costeo del catálogo entero: junta base, ventas y parámetros y llama al
/// paquete puro. Se recalcula cuando cambia cualquiera de las entradas.
class Costeo {
  const Costeo({
    required this.resultado,
    required this.articulos,
    required this.config,
    required this.registro,
    required this.fraccionSinpe,
  });
  final c.ResultadoCosteo resultado;

  /// Por clave de artículo, en el mismo orden que `resultado.articulos`.
  final Map<String, ArticuloDelCatalogo> articulos;

  /// La efectiva, con la comisión ya ponderada por el mix.
  final c.ConfigCosteo config;
  final ConfigCosteoRegistro registro;
  final double fraccionSinpe;

  c.ArticuloCosteado? calculadoDe(String clave) =>
      resultado.articulos.where((a) => a.articulo.id == clave).firstOrNull;
}

final costeoProvider = FutureProvider<Costeo>((ref) async {
  final registro = await ref.watch(configCosteoProvider.future);
  final fraccionSinpe = await ref.watch(mixDePagoProvider.future);
  final config = configEfectiva(registro, fraccionSinpe);
  final insumos = await ref.watch(insumoNotifierProvider.future);
  final costos = await ref.watch(costoDeInsumosProvider.future);
  final fijos = await ref.watch(costoFijoNotifierProvider.future);
  final estado = await ref.watch(articuloCosteoProvider.future);
  final productos = await ref.watch(productoNotifierProvider.future);
  final volumen = await ref.watch(volumenRealProvider.future);

  // Todo lo activo del catálogo, con o sin fila de costeo: un producto sin
  // costear también aparece, con sus alertas, que es como se ve qué falta.
  final catalogo = <ArticuloDelCatalogo>[];
  for (final p in productos.where((p) => p.activo)) {
    if (p.tieneVariantes) {
      for (final v in p.variantes) {
        catalogo.add(ArticuloDelCatalogo(producto: p, variante: v, registro: estado.articuloDe(p.id, v.id)));
      }
    } else {
      catalogo.add(ArticuloDelCatalogo(producto: p, registro: estado.articuloDe(p.id, '')));
    }
  }

  final articulos = <c.Articulo>[];
  final recetas = <c.LineaReceta>[];
  for (final a in catalogo) {
    final r = a.registro;
    final real = volumen[a.clave] ?? 0;
    articulos.add(
      c.Articulo(
        id: a.clave,
        nombre: a.nombre,
        precioActual: a.precioActual,
        unidadesPorLote: r?.unidadesPorLote ?? 1,
        otrosCostosDirectos: r?.otrosCostosDirectos ?? 0,
        minutosLote: r?.minutosLote ?? 0,
        unidadesMes: real > 0 ? real : (r?.unidadesEstimadasMes ?? 0),
        margenObjetivo: r?.margenObjetivo,
        ajustePrecio: r?.ajustePrecio ?? 0,
        volumenEsReal: real > 0,
        // Solo en general el IVA va dentro del precio; en simplificado el
        // impuesto ya entró como fracción de las compras.
        tasaImpuesto: registro.regimen == Regimen.general ? (a.producto.tasaIva ?? registro.tasaIvaPorDefecto) : 0,
      ),
    );
    if (r != null) {
      for (final l in estado.lineasDe(r.id)) {
        recetas.add(c.LineaReceta(articuloId: a.clave, insumoId: l.insumoId, cantidadPorLote: l.cantidadPorLote));
      }
    }
  }

  final resultado = c.calcularCatalogo(
    config: config,
    costosFijos: [for (final f in fijos) if (f.activo) f.puro],
    // El costo de cada insumo sale de sus compras (0041), no del maestro.
    insumos: [for (final i in insumos) if (i.activo) insumoConCosto(i, costos[i.id])],
    articulos: articulos,
    recetas: recetas,
  );
  return Costeo(
    resultado: resultado,
    articulos: {for (final a in catalogo) a.clave: a},
    config: config,
    registro: registro,
    fraccionSinpe: fraccionSinpe,
  );
});
