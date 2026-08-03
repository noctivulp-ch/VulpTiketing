import 'package:flutter/material.dart';

import '../../../core/theme/bento_theme.dart';
import '../producto_model.dart';
import '../producto_query_provider.dart';

/// La lista de productos con **títulos divisorios** cuando el orden agrupa.
///
/// El ajuste "ordenar por categoría" agrupaba sin decir por dónde empezaba cada
/// grupo: se veían los productos en un orden que no se explicaba solo. Con los
/// otros dos órdenes hay un único grupo sin título, y entonces esto se comporta
/// igual que la cuadrícula de antes.
///
/// Un `CustomScrollView` y no un `GridView`: un encabezado ocupa la fila entera
/// y una cuadrícula de columnas fijas no sabe hacer eso.
class ListaProductosAgrupada extends StatelessWidget {
  const ListaProductosAgrupada({
    super.key,
    required this.grupos,
    required this.porFila,
    this.altoCelda,
    this.relacionCelda,
    required this.celda,
    this.padding = EdgeInsets.zero,
    this.invertida = false,
  }) : assert(
         altoCelda == null || relacionCelda == null,
         'Una celda se dimensiona por alto fijo o por relación, no por las dos',
       ),
       assert(
         altoCelda != null || relacionCelda != null || porFila == 1,
         'Solo una fila a lo ancho puede medir lo que pida su contenido: en una '
         'cuadrícula de varias columnas todas las celdas de una línea miden igual',
       );

  final List<GrupoDeProductos> grupos;
  final int porFila;

  /// Alto fijo de cada celda. Para las que son FILAS, cuyo alto lo fija su
  /// contenido y no el ancho de la columna.
  ///
  /// Con los dos en nulo —y una sola celda a lo ancho— cada fila mide **lo que
  /// pida su propio contenido**. Es lo que hace que un nombre largo tome dos
  /// líneas sin estirar de paso las filas de los nombres cortos: con alto
  /// uniforme, un solo "Arroz con pollo, tipo chino (entero)" dejaba a "Tamal"
  /// con medio dedo de aire debajo.
  final double? altoCelda;

  /// Ancho/alto, para las celdas que sí son cuadros.
  final double? relacionCelda;
  final Widget Function(Producto producto) celda;

  /// En coordenadas de pantalla, también cuando la lista está invertida. Va
  /// DENTRO del scroll para que las celdas se desvanezcan bajo el velo en vez
  /// de frenar contra un borde.
  final EdgeInsets padding;

  /// Cascada invertida (decisión 0023): la lista crece hacia arriba desde el
  /// buscador de la barra inferior.
  final bool invertida;

  @override
  Widget build(BuildContext context) {
    // Con `reverse` los slivers se apilan de abajo hacia arriba, así que hay
    // que darlos al revés para que se LEAN en el orden correcto: el primer
    // grupo pegado al buscador, y el título de cada grupo encima de su
    // cuadrícula.
    final enOrden = invertida ? grupos.reversed.toList() : grupos;
    final horizontal = EdgeInsets.only(left: padding.left, right: padding.right);
    final primero = invertida ? padding.bottom : padding.top;
    final ultimo = invertida ? padding.top : padding.bottom;

    return CustomScrollView(
      reverse: invertida,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: primero)),
        for (final grupo in enOrden)
          for (final sliver in _slivers(context, grupo))
            SliverPadding(padding: horizontal, sliver: sliver),
        SliverToBoxAdapter(child: SizedBox(height: ultimo)),
      ],
    );
  }

  List<Widget> _slivers(BuildContext context, GrupoDeProductos grupo) {
    final titulo = grupo.titulo;
    if (titulo == null) return [_grid(grupo)];
    return invertida
        ? [_grid(grupo), _titulo(context, titulo)]
        : [_titulo(context, titulo), _grid(grupo)];
  }

  Widget _titulo(BuildContext context, String texto) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.only(top: BentoSpacing.gapCelda, bottom: BentoSpacing.unidad),
      child: Text(
        texto,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: lacaDe(context).textoAtenuadoEnBandeja),
      ),
    ),
  );

  Widget _grid(GrupoDeProductos grupo) {
    final productos = invertida ? grupo.productos.reversed.toList() : grupo.productos;

    // Sin alto ni relación, cada fila mide lo suyo. Una lista y no una
    // cuadrícula: un `SliverGrid` reparte alto uniforme por definición, así que
    // no hay forma de pedirle filas de distinto tamaño.
    if (altoCelda == null && relacionCelda == null) {
      return SliverList.separated(
        itemCount: productos.length,
        separatorBuilder: (_, _) => const SizedBox(height: BentoSpacing.pared),
        itemBuilder: (context, i) => celda(productos[i]),
      );
    }

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: porFila,
        mainAxisSpacing: BentoSpacing.pared,
        crossAxisSpacing: BentoSpacing.pared,
        mainAxisExtent: altoCelda,
        childAspectRatio: relacionCelda ?? 1,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => celda(productos[i]),
        childCount: productos.length,
      ),
    );
  }
}

/// Cuántas líneas hace falta darle al nombre para que **ninguno** de la lista
/// salga recortado, y cuánto alto pide eso.
///
/// Las celdas de una cuadrícula miden todas lo mismo, así que la alternativa
/// —dejar el alto de una línea y elidir— recortaba nombres que en esta app se
/// parecen entre sí justo en el final: "Arroz con pollo, tipo chino (entero)"
/// y "…(medio)" quedaban los dos en "Arroz con pollo, tipo chi…", o sea
/// indistinguibles en la pantalla desde la que se elige qué cobrar.
///
/// Se mide **de verdad** con un `TextPainter` en vez de estimar por cantidad de
/// caracteres: la fuente no es monoespaciada y el error se paga en un recorte.
/// Solo se miden los candidatos más largos —el resto no puede ganar— para que
/// el coste no crezca con el catálogo.
class AltoDeFila {
  const AltoDeFila({required this.lineasDelNombre, required this.alto});

  final int lineasDelNombre;
  final double alto;
}

AltoDeFila altoDeFilaSegunNombre({
  required List<GrupoDeProductos> grupos,
  required TextStyle estilo,
  required TextScaler escala,
  required double anchoDelTexto,
  required double altoConUnaLinea,
  int maxLineas = 3,
  int candidatos = 5,
}) {
  final nombres = [for (final g in grupos) ...g.productos.map((p) => p.nombre)]
    ..sort((a, b) => b.length.compareTo(a.length));

  var lineas = 1;
  for (final nombre in nombres.take(candidatos)) {
    final pintor = TextPainter(
      text: TextSpan(text: nombre, style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: escala,
      maxLines: maxLineas,
    )..layout(maxWidth: anchoDelTexto);
    final n = pintor.computeLineMetrics().length;
    pintor.dispose();
    if (n > lineas) lineas = n;
    if (lineas >= maxLineas) break;
  }

  final altoDeLinea = escala.scale(estilo.fontSize ?? 14) * (estilo.height ?? 1.35);
  return AltoDeFila(lineasDelNombre: lineas, alto: altoConUnaLinea + (lineas - 1) * altoDeLinea);
}
