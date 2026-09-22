/// El modelo de costos y precios: cuánto cuesta producir cada artículo y qué
/// precio sostiene el margen (decisión 0040 de VulpTiketing; fórmulas de
/// `Tablas/docs/CalculoCostoRecetas/01-modelo-de-costos.md`).
///
/// Sin Flutter ni base de datos a propósito: es un paquete aparte para que
/// **no pueda** importarlos. Entra el catálogo entero, sale el catálogo
/// calculado. El cálculo es de catálogo y no de artículo: el reparto de costos
/// fijos depende de las unidades de TODOS, así que no existe `articulo.precio()`.
library;

export 'src/entidades.dart';
export 'src/calculo.dart';
export 'src/resultado.dart';
