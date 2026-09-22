import 'entidades.dart';

/// Por qué un artículo necesita atención. Error impide el precio; advertencia
/// lo deja calcular pero avisa.
enum Alerta {
  sinReceta('Sin receta: el costo de insumos es cero', esError: false),
  sinVolumen('Sin volumen: no absorbe costos fijos', esError: false),
  volumenEstimado('Volumen estimado a mano, no de ventas', esError: false),
  margenBajoObjetivo('El precio actual queda por debajo del margen objetivo', esError: false),
  seVendeAPerdida('Se vende a pérdida: el precio actual no cubre el costo', esError: true),
  sinTiempo('Sin minutos de producción: con reparto por tiempo no absorbe costos fijos', esError: false),
  metaImposible('Margen + comisión llegan a 1: no existe precio que cumpla', esError: true),
  insumoDesconocido('La receta usa un insumo que ya no existe', esError: true);

  const Alerta(this.mensaje, {required this.esError});
  final String mensaje;
  final bool esError;
}

/// Una línea de receta ya valorada.
class LineaCosteada {
  const LineaCosteada({
    required this.insumoId,
    required this.insumoNombre,
    required this.cantidadPorLote,
    required this.costoUnitario,
  });
  final String insumoId;
  final String insumoNombre;
  final double cantidadPorLote;

  /// Costo efectivo por unidad base (con merma).
  final double costoUnitario;
  double get costoLinea => cantidadPorLote * costoUnitario;
}

/// Un artículo con todas sus cuentas.
class ArticuloCosteado {
  const ArticuloCosteado({
    required this.articulo,
    required this.lineas,
    required this.costoInsumosLote,
    required this.costoInsumosUnidad,
    required this.manoObraUnidad,
    required this.costoVariableUnidad,
    required this.overheadUnidad,
    required this.impuestoComprasUnidad,
    required this.costoTotalUnidad,
    required this.margenObjetivo,
    required this.precioSugerido,
    required this.precioRedondeado,
    required this.precioFinal,
    required this.margenReal,
    required this.utilidadUnidad,
    required this.alertas,
  });

  final Articulo articulo;
  final List<LineaCosteada> lineas;
  final double costoInsumosLote;
  final double costoInsumosUnidad;
  final double manoObraUnidad;
  final double costoVariableUnidad;
  final double overheadUnidad;

  /// Régimen simplificado: la parte del impuesto sobre compras que le toca a
  /// esta unidad (sobre su costo de insumos). Cero en régimen general.
  final double impuestoComprasUnidad;
  final double costoTotalUnidad;
  final double margenObjetivo;

  /// Lo que dice el modelo antes de redondear.
  final double precioSugerido;

  /// Redondeado hacia arriba al múltiplo configurado.
  final double precioRedondeado;

  /// Redondeado más el ajuste con signo: lo que el modelo propone cobrar.
  final double precioFinal;

  /// Recalculado hacia atrás sobre lo que HOY se cobra ([Articulo.precioActual]),
  /// no sobre el sugerido: es la comprobación que dice si redondear "para que
  /// quede en 2.000" erosionó la utilidad. Nulo sin precio actual.
  final double? margenReal;

  /// Utilidad por unidad al precio actual.
  final double? utilidadUnidad;
  final List<Alerta> alertas;

  double get utilidadMes => (utilidadUnidad ?? 0) * articulo.unidadesMes;

  /// Impuesto que va dentro del precio actual (régimen general), por unidad.
  double get impuestoPrecioUnidad => articulo.precioActual * articulo.fraccionImpuestoDelPrecio;

  /// **Food cost**: costo de insumos ÷ precio actual. Es la cifra del oficio
  /// (sano entre 28 y 35 % en comida; arriba de 38 % hay desperdicio o
  /// precios de proveedor sin control). Nulo sin precio.
  double? get foodCost => articulo.precioActual <= 0 ? null : costoInsumosUnidad / articulo.precioActual;
  double get ingresoMes => articulo.precioActual * articulo.unidadesMes;
  bool get tieneErrores => alertas.any((a) => a.esError);

  /// Cuánto se aleja el precio actual del final del modelo, con signo.
  double get diferenciaConSugerido => articulo.precioActual - precioFinal;
}

/// El catálogo calculado, más los agregados del negocio.
class ResultadoCosteo {
  const ResultadoCosteo({
    required this.articulos,
    required this.costosFijosMes,
    required this.totalUnidadesMes,
    required this.totalMinutosMes,
    required this.ingresoMes,
    required this.costoVariableMes,
    required this.utilidadMes,
    required this.comisionesMes,
    required this.impuestoSobrePrecioMes,
    required this.costoInsumosMes,
    required this.contribucionUnidad,
    required this.unidadesEquilibrio,
    required this.colchon,
    required this.alertasGlobales,
  });

  final List<ArticuloCosteado> articulos;
  final double costosFijosMes;
  final int totalUnidadesMes;
  final double totalMinutosMes;

  /// A precios actuales y volúmenes del mes.
  final double ingresoMes;
  final double costoVariableMes;
  final double utilidadMes;
  final double comisionesMes;

  /// Impuesto dentro de los precios cobrados en el mes (régimen general):
  /// lo que se declara de IVA. Cero en simplificado.
  final double impuestoSobrePrecioMes;

  /// Solo insumos, para el food cost del negocio.
  final double costoInsumosMes;

  /// Lo que cada unidad deja para pagar costos fijos, a precios actuales.
  final double? contribucionUnidad;

  /// Cuántas unidades al mes hay que vender para no perder plata. Nulo si la
  /// contribución no es positiva: entonces no hay equilibrio posible.
  final double? unidadesEquilibrio;

  /// Cuánto puede caer la venta antes de entrar en pérdida (0,25 = un cuarto).
  final double? colchon;
  final List<Alerta> alertasGlobales;

  double get margenNetoPromedio => ingresoMes <= 0 ? 0 : utilidadMes / ingresoMes;

  /// Food cost del negocio: insumos consumidos ÷ ingreso, ponderado por
  /// volumen. Nulo sin ingreso.
  double? get foodCostPromedio => ingresoMes <= 0 ? null : costoInsumosMes / ingresoMes;

  /// Precio promedio de una unidad vendida, a precios actuales.
  double? get precioPromedio => totalUnidadesMes <= 0 ? null : ingresoMes / totalUnidadesMes;

  /// El punto de equilibrio en DINERO: lo que hay que vender al mes para no
  /// perder. Es lo que pide un plan de negocio junto a las unidades.
  double? get ingresoEquilibrio =>
      unidadesEquilibrio == null || precioPromedio == null ? null : unidadesEquilibrio! * precioPromedio!;

  /// Qué pasa si el volumen cambia por [factor] (0,8 = cae un 20 %). Los
  /// costos fijos NO escalan: ese es justamente el riesgo que muestra.
  Escenario escenario(double factor) {
    final ingreso = ingresoMes * factor;
    final variable = (costoVariableMes + comisionesMes + impuestoSobrePrecioMes) * factor;
    return Escenario(
      factor: factor,
      unidades: (totalUnidadesMes * factor).round(),
      ingreso: ingreso,
      utilidad: ingreso - variable - costosFijosMes,
    );
  }

  /// La meta diaria, que es la cifra útil para el día a día.
  double? unidadesEquilibrioDia(int diasAbiertosMes) =>
      unidadesEquilibrio == null || diasAbiertosMes <= 0 ? null : unidadesEquilibrio! / diasAbiertosMes;
}


/// Un "qué pasaría si" sobre el volumen del mes.
class Escenario {
  const Escenario({required this.factor, required this.unidades, required this.ingreso, required this.utilidad});
  final double factor;
  final int unidades;
  final double ingreso;
  final double utilidad;
}
