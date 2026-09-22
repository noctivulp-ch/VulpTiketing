import 'dart:math' as math;

import 'entidades.dart';
import 'resultado.dart';

/// Calcula el catálogo entero. Determinista y sin efectos: mismas entradas,
/// mismo resultado.
///
/// Es de catálogo y no de artículo porque el overhead de cada unidad depende
/// de las unidades de TODOS: cambiar el volumen de uno mueve el precio de los
/// demás. Por eso la pantalla recalcula todo en cada edición y no cachea por
/// artículo.
ResultadoCosteo calcularCatalogo({
  required ConfigCosteo config,
  required List<CostoFijo> costosFijos,
  required List<Insumo> insumos,
  required List<Articulo> articulos,
  required List<LineaReceta> recetas,
}) {
  final porInsumo = {for (final i in insumos) i.id: i};
  final recetasPor = <String, List<LineaReceta>>{};
  for (final l in recetas) {
    (recetasPor[l.articuloId] ??= []).add(l);
  }

  final costosFijosMes = costosFijos.fold(0.0, (s, c) => s + c.montoMensual);
  final totalUnidades = articulos.fold(0, (s, a) => s + a.unidadesMes);
  final totalMinutos = articulos.fold(0.0, (s, a) => s + a.minutosPorUnidad * a.unidadesMes);

  final alertasGlobales = <Alerta>[
    if (config.divisor <= 0) Alerta.metaImposible,
  ];

  double overheadDe(Articulo a) {
    switch (config.metodoReparto) {
      case MetodoReparto.tiempo:
        if (totalMinutos <= 0) return 0;
        return costosFijosMes * a.minutosPorUnidad / totalMinutos;
      case MetodoReparto.unidad:
        if (totalUnidades <= 0) return 0;
        return costosFijosMes / totalUnidades;
    }
  }

  final calculados = <ArticuloCosteado>[];
  var ingresoMes = 0.0;
  var costoVariableMes = 0.0;
  var utilidadMes = 0.0;
  var comisionesMes = 0.0;
  var impuestoSobrePrecioMes = 0.0;
  var costoInsumosMes = 0.0;

  for (final a in articulos) {
    final alertas = <Alerta>[];
    final lineas = <LineaCosteada>[];
    for (final l in recetasPor[a.id] ?? const <LineaReceta>[]) {
      final insumo = porInsumo[l.insumoId];
      if (insumo == null) {
        alertas.add(Alerta.insumoDesconocido);
        continue;
      }
      lineas.add(
        LineaCosteada(
          insumoId: insumo.id,
          insumoNombre: insumo.nombre,
          cantidadPorLote: l.cantidadPorLote,
          costoUnitario: insumo.costoEfectivo(config.mermaPorDefecto),
        ),
      );
    }
    if (lineas.isEmpty && !config.recetasOpcionales) alertas.add(Alerta.sinReceta);

    final unidadesPorLote = math.max(1, a.unidadesPorLote);
    final costoInsumosLote = lineas.fold(0.0, (s, l) => s + l.costoLinea);
    final costoInsumosUnidad = costoInsumosLote / unidadesPorLote;
    final manoObraUnidad = (a.minutosLote / 60) * config.tarifaManoObraHora / unidadesPorLote;
    final costoVariableUnidad = costoInsumosUnidad + a.otrosCostosDirectos + manoObraUnidad;
    final overheadUnidad = overheadDe(a);
    // Simplificado: el impuesto se paga sobre lo comprado, así que por unidad
    // es una fracción del costo de insumos. Va como costo, no como fracción
    // del precio: no depende de a cuánto se venda.
    final impuestoComprasUnidad = costoInsumosUnidad * config.impuestoSobreCompras;
    final costoTotalUnidad = costoVariableUnidad + overheadUnidad + impuestoComprasUnidad;

    if (a.unidadesMes <= 0) {
      alertas.add(Alerta.sinVolumen);
    } else if (!a.volumenEsReal) {
      alertas.add(Alerta.volumenEstimado);
    }
    if (config.metodoReparto == MetodoReparto.tiempo && a.minutosLote <= 0) alertas.add(Alerta.sinTiempo);

    final margen = a.margenObjetivo ?? config.margenObjetivo;
    // General: el IVA va DENTRO del precio, así que es una fracción más del
    // precio que no es utilidad, como la comisión.
    final divisor = 1 - margen - config.comisionMediosPago - a.fraccionImpuestoDelPrecio;
    double precioSugerido;
    if (divisor <= 0) {
      alertas.add(Alerta.metaImposible);
      precioSugerido = double.nan;
    } else {
      precioSugerido = costoTotalUnidad / divisor;
    }
    final precioRedondeado = precioSugerido.isNaN ? double.nan : _techo(precioSugerido, config.redondeoPrecio);
    final precioFinal = precioRedondeado.isNaN ? double.nan : precioRedondeado + a.ajustePrecio;

    // El margen REAL se mide contra lo que se cobra hoy, no contra la
    // propuesta: es lo que dice si el precio de la carta sostiene el negocio.
    double? margenReal;
    double? utilidadUnidad;
    if (a.precioActual > 0) {
      utilidadUnidad = a.precioActual -
          costoTotalUnidad -
          a.precioActual * config.comisionMediosPago -
          a.precioActual * a.fraccionImpuestoDelPrecio;
      margenReal = utilidadUnidad / a.precioActual;
      if (margenReal < 0) {
        alertas.add(Alerta.seVendeAPerdida);
      } else if (margenReal < margen - 0.005) {
        alertas.add(Alerta.margenBajoObjetivo);
      }
    }

    ingresoMes += a.precioActual * a.unidadesMes;
    // El impuesto sobre compras es variable (sigue al volumen), así que entra
    // en el costo variable del mes y por tanto en la contribución.
    costoVariableMes += (costoVariableUnidad + impuestoComprasUnidad) * a.unidadesMes;
    utilidadMes += (utilidadUnidad ?? 0) * a.unidadesMes;
    comisionesMes += a.precioActual * config.comisionMediosPago * a.unidadesMes;
    impuestoSobrePrecioMes += a.precioActual * a.fraccionImpuestoDelPrecio * a.unidadesMes;
    costoInsumosMes += costoInsumosUnidad * a.unidadesMes;

    calculados.add(
      ArticuloCosteado(
        articulo: a,
        lineas: lineas,
        costoInsumosLote: costoInsumosLote,
        costoInsumosUnidad: costoInsumosUnidad,
        manoObraUnidad: manoObraUnidad,
        costoVariableUnidad: costoVariableUnidad,
        overheadUnidad: overheadUnidad,
        impuestoComprasUnidad: impuestoComprasUnidad,
        costoTotalUnidad: costoTotalUnidad,
        margenObjetivo: margen,
        precioSugerido: precioSugerido,
        precioRedondeado: precioRedondeado,
        precioFinal: precioFinal,
        margenReal: margenReal,
        utilidadUnidad: utilidadUnidad,
        alertas: alertas,
      ),
    );
  }

  // Punto de equilibrio: cuántas unidades al mes pagan los costos fijos, con
  // la contribución promedio a precios actuales.
  double? contribucion;
  double? equilibrio;
  double? colchon;
  if (totalUnidades > 0) {
    contribucion = (ingresoMes - costoVariableMes - comisionesMes - impuestoSobrePrecioMes) / totalUnidades;
    if (contribucion > 0) {
      equilibrio = costosFijosMes / contribucion;
      colchon = equilibrio > 0 ? totalUnidades / equilibrio - 1 : null;
    }
  }

  return ResultadoCosteo(
    articulos: calculados,
    costosFijosMes: costosFijosMes,
    totalUnidadesMes: totalUnidades,
    totalMinutosMes: totalMinutos,
    ingresoMes: ingresoMes,
    costoVariableMes: costoVariableMes,
    utilidadMes: utilidadMes,
    comisionesMes: comisionesMes,
    impuestoSobrePrecioMes: impuestoSobrePrecioMes,
    costoInsumosMes: costoInsumosMes,
    contribucionUnidad: contribucion,
    unidadesEquilibrio: equilibrio,
    colchon: colchon,
    alertasGlobales: alertasGlobales,
  );
}

/// Redondea hacia ARRIBA al múltiplo. Con múltiplo 0 o negativo, devuelve tal
/// cual: un redondeo que no existe no puede bajar el precio.
double _techo(double valor, double multiplo) {
  if (multiplo <= 0) return valor;
  return (valor / multiplo).ceilToDouble() * multiplo;
}
