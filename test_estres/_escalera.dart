/// Escalera de volúmenes y presupuestos de las pruebas de estrés.
///
/// Vive en `test_estres/` y NO en `test/` a propósito: `flutter test` sin
/// argumentos solo recorre `test/`, así la suite normal sigue tardando ~5 s y
/// estas pruebas se corren aparte con `flutter test test_estres/`. Misma
/// convención que `test_driver/`.
///
/// Los volúmenes salen de datos reales del negocio, no de números redondos
/// inventados: ingreso de ₡120–150 mil/día contra el catálogo real, donde los
/// 8 items de alta rotación promedian ₡875. Con esa mezcla y 3× de
/// crecimiento salen ~500 ventas/día, así que el techo se fija más arriba por
/// el límite FÍSICO de una caja: 2.000 ventas/día es una venta cada 25
/// segundos durante 14 horas sin un solo hueco — volumen de franquicia de
/// comida rápida, no de soda. Irrazonable acá, pero alcanzable de verdad.
///
/// El horizonte es largo porque nada purga ni archiva ventas: `venta` y
/// `linea_venta` solo crecen, así que el horizonte no es una ventana móvil
/// sino la vida entera del negocio.
library;

import 'dart:io';

/// Cómo se trata el resultado de una medición en cada nivel.
enum Trato {
  /// La prueba falla si no cumple el presupuesto. Solo el nivel realista: es
  /// el escenario que la app tiene que sostener de verdad.
  presupuestoDuro,

  /// Mide y registra. Solo falla ante algo catastrófico (sin memoria, >30 s, o
  /// un resultado incorrecto). El volumen extremo es una dirección, no una
  /// meta: no tiene sentido exigir 400 ms sobre 7 M de filas en una tablet
  /// lenta.
  caracterizacion,

  /// Sin presupuesto: reporta el número para saber cuánto margen real hay.
  puntoDeQuiebre,
}

class Nivel {
  const Nivel({
    required this.nombre,
    required this.ventasPorDia,
    required this.dias,
    required this.trato,
  });

  final String nombre;
  final int ventasPorDia;
  final int dias;
  final Trato trato;

  int get ventas => ventasPorDia * dias;

  /// 2 líneas por venta: ticket típico de soda con la mezcla sesgada a barato.
  int get lineas => ventas * 2;

  int get filas => ventas + lineas;

  /// Los niveles grandes se cachean en disco; el realista se genera en memoria
  /// en cada corrida porque es barato.
  bool get cacheable => filas > 1000000;

  @override
  String toString() => '$nombre (${ventas ~/ 1000}k ventas, ${lineas ~/ 1000}k lineas)';
}

const nivelRealista = Nivel(
  nombre: 'realista',
  ventasPorDia: 320,
  dias: 365,
  trato: Trato.presupuestoDuro,
);

const nivelAlto = Nivel(
  nombre: 'alto',
  ventasPorDia: 500,
  dias: 365 * 5,
  trato: Trato.caracterizacion,
);

const nivelTecho = Nivel(
  nombre: 'techo',
  ventasPorDia: 2000,
  dias: 365 * 5,
  trato: Trato.caracterizacion,
);

const nivelAbsoluto = Nivel(
  nombre: 'absoluto',
  ventasPorDia: 2000,
  dias: 365 * 10,
  trato: Trato.puntoDeQuiebre,
);

const todosLosNiveles = [nivelRealista, nivelAlto, nivelTecho, nivelAbsoluto];

/// Qué niveles corren. Por defecto realista + alto + techo; el absoluto queda
/// fuera porque generarlo son ~7 min y 22 M de filas.
///
/// Se puede acotar con `VULP_ESTRES_NIVELES=realista,alto` — sirve para iterar
/// sobre las pruebas sin esperar la generación de los niveles grandes, y para
/// saltear un nivel donde una operación todavía es inviable (por ejemplo el
/// reporte anual antes de arreglar el N+1: en el techo serían ~3,6 M de
/// consultas y no termina en un tiempo útil).
List<Nivel> get nivelesActivos {
  final pedidos = Platform.environment['VULP_ESTRES_NIVELES'];
  if (pedidos == null || pedidos.trim().isEmpty) {
    return const [nivelRealista, nivelAlto, nivelTecho];
  }
  final nombres = pedidos.split(',').map((s) => s.trim()).toSet();
  final seleccion = todosLosNiveles.where((n) => nombres.contains(n.nombre)).toList();
  if (seleccion.isEmpty) {
    throw ArgumentError(
      'VULP_ESTRES_NIVELES="$pedidos" no coincide con ninguno de: '
      '${todosLosNiveles.map((n) => n.nombre).join(", ")}',
    );
  }
  return seleccion;
}

// --- Presupuestos ------------------------------------------------------------
// Se miden en la laptop de desarrollo, pero el objetivo es una tablet lenta y
// sin definir. Cada presupuesto es "lo que se acepta en la TABLET"; al medir
// acá se exige `objetivo / factorTablet`, asumiendo que la tablet es unas 4
// veces más lenta.
//
// Esto es una estimación declarada, no una medición: cuando exista el equipo
// real hay que revalidar. Está en una constante justamente para poder
// ajustarlo de una sola vez.
const factorTablet = 4;

Duration presupuestoLaptop(Duration objetivoEnTablet) =>
    Duration(microseconds: objetivoEnTablet.inMicroseconds ~/ factorTablet);

/// Guardar una venta con la base ya cargada. Es la operación que el cajero
/// hace decenas de veces por hora: si esto se degrada, la caja se siente lenta.
const objetivoGuardarVenta = Duration(milliseconds: 100);

/// Reporte del día. Se abre constantemente durante el turno.
const objetivoReporteDia = Duration(milliseconds: 400);

/// Reporte anual. Se consulta de vez en cuando, tolera más.
const objetivoReporteAnio = Duration(seconds: 3);

/// Filtrado de productos por pulsación de tecla. Por encima de esto la
/// escritura se siente pegajosa.
const objetivoBusquedaPorTecla = Duration(milliseconds: 50);

/// Umbral de catástrofe para los niveles de caracterización: por encima de
/// esto la operación se considera inservible, no solo lenta.
const umbralCatastrofe = Duration(seconds: 30);
