/// En qué se mide un insumo. Fijas a propósito (ADR-007 de la hoja): un
/// conversor de unidades introduce errores silenciosos cuando alguien elige
/// mal; con tres y una regla, el error se ve.
enum UnidadBase { gramo, mililitro, unidad }

/// Cómo se reparten los costos fijos entre los artículos.
enum MetodoReparto {
  /// Cada unidad vendida absorbe lo mismo.
  unidad,

  /// Absorbe según los minutos que ocupa producirla: un queque de 90 minutos
  /// de horno no debería absorber lo mismo que una soda de 2.
  tiempo,
}

/// Parámetros globales del negocio.
class ConfigCosteo {
  const ConfigCosteo({
    this.diasAbiertosMes = 26,
    this.margenObjetivo = 0.60,
    this.comisionMediosPago = 0.03,
    this.mermaPorDefecto = 0.05,
    this.tarifaManoObraHora = 0,
    this.redondeoPrecio = 50,
    this.metodoReparto = MetodoReparto.unidad,
    this.impuestoSobreCompras = 0,
  });

  final int diasAbiertosMes;

  /// Utilidad deseada como fracción DEL PRECIO (ADR-001 de la hoja): 0,60 es
  /// que de cada 100 vendidos, 60 son utilidad.
  final double margenObjetivo;

  /// Datáfono, transferencias: fracción del precio.
  final double comisionMediosPago;

  /// Cuando el insumo no declara la suya.
  final double mermaPorDefecto;

  /// Costo de una hora de producción. Cero si nadie se lo imputa — pero el
  /// modelo lo pide a propósito: si el producto no aguanta pagar el trabajo
  /// que lleva, no es rentable, es un pasatiempo subsidiado.
  final double tarifaManoObraHora;

  /// Múltiplo al que se redondea HACIA ARRIBA el precio sugerido.
  final double redondeoPrecio;
  final MetodoReparto metodoReparto;

  /// Régimen simplificado de Costa Rica: el impuesto se paga como fracción de
  /// las COMPRAS del trimestre (factor de IVA + factor de renta). Por unidad
  /// se imputa sobre el costo de insumos, que es lo que se compra. Cero en
  /// régimen general, donde el impuesto va sobre el precio de cada artículo
  /// ([Articulo.tasaImpuesto]).
  final double impuestoSobreCompras;

  /// Lo que queda del precio después de margen y comisión (sin impuesto sobre
  /// el precio, que es por artículo). Tiene que ser positivo.
  double get divisor => 1 - margenObjetivo - comisionMediosPago;
}

class CostoFijo {
  const CostoFijo({required this.id, required this.concepto, required this.montoMensual});
  final String id;
  final String concepto;
  final double montoMensual;
}

/// Una materia prima: se compra en una presentación y se usa en unidad base.
class Insumo {
  const Insumo({
    required this.id,
    required this.nombre,
    required this.unidadBase,
    required this.contenidoPorCompra,
    required this.precioCompra,
    this.merma,
  });

  final String id;
  final String nombre;
  final UnidadBase unidadBase;

  /// Cuánto trae la presentación, en unidad base: un bulto de 1 kg son 1000.
  final double contenidoPorCompra;
  final double precioCompra;

  /// Fracción que se pierde (se cae, se pega, se vence). Nula usa la global.
  final double? merma;

  double get costoPorUnidadBase => contenidoPorCompra <= 0 ? 0 : precioCompra / contenidoPorCompra;

  /// El que usan las recetas: se DIVIDE por (1 − merma), no se multiplica.
  /// Para usar 100 g con 3 % de merma hay que comprar 103.
  double costoEfectivo(double mermaPorDefecto) {
    final m = merma ?? mermaPorDefecto;
    if (m >= 1) return double.infinity;
    return costoPorUnidadBase / (1 - m);
  }
}

/// Lo que se costea: un producto, o una variante de un producto. Lo que se
/// vende como "una unidad".
class Articulo {
  const Articulo({
    required this.id,
    required this.nombre,
    required this.precioActual,
    this.unidadesPorLote = 1,
    this.otrosCostosDirectos = 0,
    this.minutosLote = 0,
    this.unidadesMes = 0,
    this.margenObjetivo,
    this.ajustePrecio = 0,
    this.volumenEsReal = false,
    this.tasaImpuesto = 0,
  });

  final String id;
  final String nombre;

  /// Lo que hoy se cobra. El módulo NO lo cambia: lo compara.
  final double precioActual;

  /// Cuántas unidades da una tanda de la receta. Un producto suelto, 1.
  final int unidadesPorLote;

  /// Por unidad: una etiqueta impresa afuera, una comisión de maquila.
  final double otrosCostosDirectos;

  /// Tiempo total de producir el lote.
  final double minutosLote;

  /// Cuántas se venden al mes. Es el dato más sensible del modelo: reparte
  /// los costos fijos. Las ventas reales cuando las hay; si no, la estimación.
  final int unidadesMes;

  /// Nulo usa el global.
  final double? margenObjetivo;

  /// Con signo: cobrar por encima (estrella) o por debajo (gancho) del modelo.
  final double ajustePrecio;

  /// Si [unidadesMes] salió de las ventas, y no de una estimación a mano.
  final bool volumenEsReal;

  /// IVA que lleva el precio de este artículo (0,13, 0,01, 0…), régimen
  /// general. El precio al público lo INCLUYE, así que la fracción del
  /// precio que se va en impuesto es `tasa / (1 + tasa)`: con 13 %, el 11,5 %
  /// de lo cobrado.
  final double tasaImpuesto;

  double get fraccionImpuestoDelPrecio => tasaImpuesto <= 0 ? 0 : tasaImpuesto / (1 + tasaImpuesto);

  double get minutosPorUnidad => unidadesPorLote <= 0 ? 0 : minutosLote / unidadesPorLote;
}

class LineaReceta {
  const LineaReceta({required this.articuloId, required this.insumoId, required this.cantidadPorLote});
  final String articuloId;
  final String insumoId;

  /// En la unidad base del insumo, y POR LOTE, no por unidad: es como se
  /// produce (500 g de harina para 12 queques), y convertir a mano es una
  /// fuente de errores.
  final double cantidadPorLote;
}
