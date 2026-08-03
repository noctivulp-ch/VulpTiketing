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
         (altoCelda == null) != (relacionCelda == null),
         'Una celda se dimensiona por alto fijo o por relación, no por las dos',
       );

  final List<GrupoDeProductos> grupos;
  final int porFila;

  /// Alto fijo de cada celda. Para las que son FILAS, cuyo alto lo fija su
  /// contenido y no el ancho de la columna.
  final double? altoCelda;

  /// Ancho/alto, para las celdas que sí son cuadros. Exactamente uno de los dos
  /// tiene que venir.
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
