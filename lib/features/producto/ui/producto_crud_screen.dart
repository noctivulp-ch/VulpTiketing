import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_fotos.dart';
import '../../../core/theme/bento_velo.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_falla.dart';
import '../../auth/sesion_notifier.dart';
import '../../sync/sync_notifier.dart';
import '../producto_model.dart';
import '../producto_notifier.dart';
import '../producto_query_provider.dart';
import 'categorias_panel.dart';
import 'imagen_del_banco_vista.dart';
import 'lista_productos_agrupada.dart';
import 'producto_form_dialog.dart';
import '../../../core/moneda.dart';

/// Ventana 3 — ver docs/pantallas/flujo-descripcion.md#ventana-3--crud-de-producto
/// y docs/pantallas/prototipos-ascii.md.
///
/// Permisos por rol (Operations.feature): Gerente ve Crear/Editar/
/// Descontinuar/Purgar; Registradora solo Editar.
///
/// **Las categorías viven acá, no en Configuración**: son parte de la carta,
/// y ordenarlas es la misma tarea que ordenar los productos. Un botón flotante
/// rota entre la lista de productos y el editor de categorías; el icono del
/// botón dice a dónde se va, no dónde se está.
class ProductoCrudScreen extends ConsumerStatefulWidget {
  const ProductoCrudScreen({super.key});

  @override
  ConsumerState<ProductoCrudScreen> createState() => _ProductoCrudScreenState();
}

class _ProductoCrudScreenState extends ConsumerState<ProductoCrudScreen> {
  bool _mostrandoCategorias = false;

  @override
  Widget build(BuildContext context) {
    // El catálogo del Gerente SÍ muestra los descontinuados: es la única
    // pantalla desde la que se puede recontinuarlos.
    final productosAsync = ref.watch(productoCatalogoAgrupadoProvider);
    // `false` mientras se lee: nunca habilitar un borrado físico por no haber
    // terminado de comprobar si hay otros aparatos.
    final sincronizado = ref.watch(dispositivoSinParesProvider).valueOrNull ?? false;
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;
    final iconos = ref.watch(iconosDeCategoriaProvider);

    // Cascada invertida (mismo patron que el panel lateral de Ventana 2): el
    // buscador vive en la barra inferior, la lista crece hacia arriba desde
    // ahi con `reverse: true`.
    final listaDeProductos = productosAsync.when(
              data: (grupos) => grupos.every((g) => g.productos.isEmpty)
                  ? const Center(child: Text('Sin productos'))
                  : LayoutBuilder(
                      builder: (context, restricciones) {
                        final porFila = bentoPorFila(
                          BentoAncho.de(context),
                          compacto: 6,
                          medio: 3,
                          amplio: 2,
                        );
                        // Una sola a lo ancho —el teléfono— deja que cada fila
                        // mida lo suyo. Con varias columnas no se puede: las
                        // celdas de una línea miden todas igual, así que ahí sí
                        // hay que calcular un alto común.
                        final unaPorLinea = porFila == 1;
                        final medida = unaPorLinea
                            ? null
                            : _altoDeFila(
                                context,
                                grupos: grupos,
                                anchoDisponible: restricciones.maxWidth,
                                porFila: porFila,
                                esGerente: esGerente,
                              );
                        return ListaProductosAgrupada(
                          grupos: grupos,
                          // Se conserva la cascada invertida: la lista crece
                          // hacia arriba desde el buscador de la barra inferior.
                          invertida: true,
                          // El padding va en coordenadas de pantalla aunque el
                          // scroll esté invertido: el velo está arriba, o sea
                          // `top`.
                          padding: EdgeInsets.fromLTRB(
                            BentoSpacing.gapCelda,
                            bentoInsetSuperior(context),
                            BentoSpacing.gapCelda,
                            BentoSpacing.gapCelda,
                          ),
                          // Una fila de producto ocupa 6, 3 o 2 columnas: en
                          // teléfono va a lo ancho, en escritorio caben tres.
                          porFila: porFila,
                          // El alto lo fija el contenido (miniatura de 44,
                          // botones de 48 y las líneas del nombre), nunca el
                          // ancho de la columna.
                          altoCelda: medida?.alto,
                          celda: (producto) {
                            return _FilaProducto(
                              producto: producto,
                              iconoDeSuCategoria: iconos[producto.categoriaId],
                              lineasDelNombre: medida?.lineasDelNombre,
                              esGerente: esGerente,
                              sincronizado: sincronizado,
                              onEditar: () => _editar(context, producto),
                              onDescontinuar: () async {
                                final notifier = ref.read(productoNotifierProvider.notifier);
                                if (producto.activo) {
                                  await notifier.descontinuar(producto.id);
                                } else {
                                  await notifier.recontinuar(producto.id);
                                }
                                if (context.mounted) {
                                  mostrarAviso(
                                    context,
                                    producto.activo
                                        ? '✓ Producto descontinuado'
                                        : '✓ Producto de vuelta en la carta',
                                  );
                                }
                              },
                              onPurgar: () => _confirmarYPurgar(
                                context,
                                ref,
                                producto,
                                sincronizado: sincronizado,
                              ),
                            );
                          },
                        );
                      },
                    ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => BentoFalla(
        mensaje: 'No se pudo cargar el catálogo.',
        error: e,
        onReintentar: () => ref.invalidate(productoNotifierProvider),
      ),
    );

    // El editor de categorías ocupa el mismo sitio que la lista. Es un panel
    // con su propio "Crear", así que abajo no hace falta buscador ni "Nuevo".
    final editorDeCategorias = ListView(
      padding: EdgeInsets.fromLTRB(
        BentoSpacing.gapCelda,
        bentoInsetSuperior(context) + BentoSpacing.gapCelda,
        BentoSpacing.gapCelda,
        BentoSpacing.gapCelda,
      ),
      children: const [PanelCategorias()],
    );

    // Barra inferior unificada: buscador + agregar en el mismo panel (antes el
    // buscador vivia en el AppBar y "agregar" era un FAB flotando aparte, sin
    // relacion visual con el buscador). Va como barra del Scaffold y no dentro
    // del cuerpo para que el botón flotante se apoye encima de ella.
    final barra = ColoredBox(
      color: lacaDe(context).pozo,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.unidad),
          child: _mostrandoCategorias
              ? SizedBox(
                  height: bentoObjetivoTactilMin,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Categorías de la carta', style: Theme.of(context).textTheme.titleSmall),
                      ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar producto o categoría…',
                          isDense: true,
                        ),
                        onChanged: (v) => ref.read(productoBusquedaProvider.notifier).state = v,
                      ),
                    ),
                    if (esGerente) ...[
                      const SizedBox(width: BentoSpacing.unidad),
                      FilledButton.icon(
                        onPressed: () => _crear(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo'),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );

    return Scaffold(
      body: _mostrandoCategorias ? editorDeCategorias : listaDeProductos,
      bottomNavigationBar: barra,
      // Solo Gerente, como el editor que abre: renombrar o sacar una categoría
      // reordena la carta que ve todo el mundo.
      floatingActionButton: esGerente
          ? _BotonQueRota(
              mostrandoCategorias: _mostrandoCategorias,
              onPressed: () => setState(() => _mostrandoCategorias = !_mostrandoCategorias),
            )
          : null,
    );
  }

  /// Cuánto mide una fila del catálogo, dadas las líneas que pide el nombre
  /// más largo.
  ///
  /// Hay que descontar del ancho todo lo que NO es el nombre —la miniatura, los
  /// botones, los aires— porque es lo único que queda para el texto, y de ahí
  /// sale cuántas líneas hacen falta.
  static AltoDeFila _altoDeFila(
    BuildContext context, {
    required List<GrupoDeProductos> grupos,
    required double anchoDisponible,
    required int porFila,
    required bool esGerente,
  }) {
    // `porFila` es cuántas celdas entran en una línea, no cuántas columnas de
    // la retícula ocupa cada una.
    final anchoCelda =
        (anchoDisponible - BentoSpacing.gapCelda * 2 - BentoSpacing.pared * (porFila - 1)) /
        porFila;

    // Un botón siempre (editar); el Gerente ve además purgar, y descontinuar
    // solo si el producto está activo — se cuenta el caso peor, que es el que
    // deja menos sitio al nombre.
    final botones = esGerente ? 3 : 1;
    final anchoDelTexto =
        anchoCelda -
        BentoSpacing.unidad * 2 - // el padding del pozo
        bentoMiniatura -
        BentoSpacing.unidad - // la separación de la miniatura
        bentoObjetivoTactilMin * botones;

    return altoDeFilaSegunNombre(
      grupos: grupos,
      estilo: Theme.of(context).textTheme.bodyLarge!,
      escala: MediaQuery.textScalerOf(context),
      // Nunca menos de un ancho mínimo: con la ventana muy angosta el cálculo
      // puede dar negativo, y un `maxWidth` negativo revienta el `TextPainter`.
      anchoDelTexto: anchoDelTexto < 40 ? 40 : anchoDelTexto,
      // 76 era el alto de siempre, con el nombre en una línea.
      altoConUnaLinea: 76,
    );
  }

  Future<void> _editar(BuildContext context, Producto producto) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => ProductoFormDialog(producto: producto),
    );
    if (guardado == true && context.mounted) {
      mostrarAviso(context, '✓ Producto actualizado');
    }
  }

  Future<void> _crear(BuildContext context) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => const ProductoFormDialog(),
    );
    if (guardado == true && context.mounted) {
      mostrarAviso(context, '✓ Producto creado');
    }
  }

  /// Purgar es irreversible (0015) — SIEMPRE pide confirmación aparte,
  /// nunca borra al primer tap (ver docs/pantallas/prototipos-ascii.md).
  Future<void> _confirmarYPurgar(
    BuildContext context,
    WidgetRef ref,
    Producto producto, {
    required bool sincronizado,
  }) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('¿Purgar este producto?'),
        contenido: Text(
          'Esto borra "${producto.nombre}" de forma permanente. No se puede deshacer.',
        ),
        acciones: BentoAcciones(
          izquierda: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
          ],
          derecha: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Purgar'),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !context.mounted) return;

    final resultado = await ref
        .read(productoNotifierProvider.notifier)
        .purgar(producto.id, todosLosDispositivosSincronizados: sincronizado);
    if (context.mounted) {
      mostrarAviso(context, _mensaje(resultado));
    }
  }

  String _mensaje(PurgarResultado resultado) {
    switch (resultado) {
      case PurgarResultado.ok:
        return 'Producto purgado';
      case PurgarResultado.tieneVentasAsociadas:
        return 'No se puede purgar: tiene ventas asociadas';
      case PurgarResultado.faltaSincronizar:
        return 'No se puede purgar: faltan dispositivos por sincronizar';
    }
  }
}

/// Mismo lenguaje visual que `_TarjetaProducto` (Ventana 1) y
/// `_FilaLineaVenta` (Ventana 2): placeholder cuadrado + nombre + precio,
/// en formato de fila — consistencia entre pantallas (skill
/// `aesthetic-usability`).
class _FilaProducto extends StatelessWidget {
  const _FilaProducto({
    required this.producto,
    required this.iconoDeSuCategoria,
    required this.lineasDelNombre,
    required this.esGerente,
    required this.sincronizado,
    required this.onEditar,
    required this.onDescontinuar,
    required this.onPurgar,
  });

  final Producto producto;

  /// La clave del icono que le toca por su categoría, ya resuelta.
  final String? iconoDeSuCategoria;

  /// Cuántas líneas se le dieron al nombre, cuando la lista tiene varias
  /// columnas y hay que darles a todas el mismo alto. **Nulo con una sola fila
  /// a lo ancho**: ahí cada nombre toma las que necesite, que es lo que se
  /// quiere y lo que una cuadrícula no puede dar.
  final int? lineasDelNombre;

  final bool esGerente;
  final bool sincronizado;
  final VoidCallback onEditar;
  final VoidCallback onDescontinuar;
  final VoidCallback onPurgar;

  @override
  Widget build(BuildContext context) {
    return BentoPozo(
      padding: const EdgeInsets.all(BentoSpacing.unidad),
      child: Row(
        children: [
          // La miniatura es la señal que se ve sin leer: un producto fuera de
          // la carta se distingue de un vistazo en una lista larga.
          //
          // Aquí el hueco va SIEMPRE, con imagen o sin ella: es una lista de
          // filas de alto fijo, así que la miniatura no le quita sitio a nada.
          // En Venta Rápida y en el carrito es al revés — ahí el hueco se lo
          // disputa el nombre y solo aparece si hay imagen de verdad.
          SizedBox(
            width: bentoMiniatura,
            height: bentoMiniatura,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BentoRadius.pozo - BentoSpacing.unidad / 2),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImagenDelBancoVista(
                    referencia: producto.imagen,
                    ventana: VentanaConFotos.inventario,
                    iconoDeSuCategoria: iconoDeSuCategoria,
                    apagada: !producto.activo,
                  ),
                  // El aspa va en una ESQUINA y pequeña, no centrada y del
                  // mismo tamaño que lo de abajo. Centradas, las dos marcas se
                  // pisaban y no se leía ninguna: un cubierto y una prohibición
                  // superpuestos son un borrón, no dos datos.
                  //
                  // Y son dos datos distintos que hacen falta a la vez — qué es
                  // el producto y que está fuera de la carta—, así que la
                  // respuesta es apartarlas, no callar una.
                  if (!producto.activo)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        // Fondo propio: encima de una foto clara, el aspa sola
                        // desaparecía.
                        decoration: BoxDecoration(
                          color: lacaDe(context).pozo,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(BentoRadius.pozo / 2),
                          ),
                        ),
                        padding: const EdgeInsets.only(left: 2, top: 2),
                        child: Icon(
                          Icons.block,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: BentoSpacing.unidad),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // El nombre entero, en las líneas que haga falta. Con una sola
                // línea, "Arroz con pollo, tipo chino (entero)" y "…(medio)"
                // quedaban los dos en "Arroz con pollo, tipo chi…":
                // indistinguibles justo donde hay que elegir cuál es cuál.
                Text(
                  producto.nombre,
                  style: Theme.of(context).textTheme.bodyLarge,
                  maxLines: lineasDelNombre,
                  overflow: lineasDelNombre == null ? null : TextOverflow.ellipsis,
                ),
                Text(
                  // El PRECIO primero: cuando el subtítulo no entra, la elipsis
                  // se come lo último. Con el estado delante, "Fuera de la
                  // carta · ₡15000" salía como "Fuera de la carta · ₡1500…" —
                  // un número recortado se lee como otro número, y eso es peor
                  // que no verlo.
                  producto.activo
                      ? Moneda.de(context).formatear(producto.precioBase)
                      : '${Moneda.de(context).formatear(producto.precioBase)} · Fuera de la carta',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    // Atenuado, no translúcido: bajar la opacidad se
                    // llevaría el contraste por debajo del mínimo AA, y el
                    // dato tiene que seguir leyéndose.
                    color: producto.activo ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: onEditar),
          if (esGerente) ...[
            if (producto.activo)
              IconButton(
                icon: const Icon(Icons.block),
                tooltip: 'Descontinuar',
                onPressed: onDescontinuar,
              ),
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: sincronizado
                  ? 'Purgar'
                  : 'Purgar (requiere que todos los dispositivos estén sincronizados)',
              onPressed: onPurgar,
            ),
          ],
        ],
      ),
    );
  }
}


/// El botón que rota entre productos y categorías.
///
/// El icono dice **a dónde se va**: en la lista de productos muestra la
/// etiqueta de categorías, y en el editor muestra la cuadrícula del catálogo.
/// Al pulsarlo el icono actual sale por la izquierda mientras el nuevo entra
/// por la derecha — lo pidió así el dueño, y es lo que hace legible el cambio:
/// se ve que se cambió de sitio, no que el botón parpadeó.
class _BotonQueRota extends StatelessWidget {
  const _BotonQueRota({required this.mostrandoCategorias, required this.onPressed});

  final bool mostrandoCategorias;
  final VoidCallback onPressed;

  static const _duracion = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: mostrandoCategorias ? 'Volver a los productos' : 'Editar categorías',
      // El recorte es lo que hace que el icono "salga" y "entre" en vez de
      // asomar fuera del círculo a mitad de camino.
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: _duracion,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          // El que entra viene de la derecha; el que sale se va a la izquierda.
          // `AnimatedSwitcher` corre la animación del saliente hacia atrás
          // (de 1 a 0), así que su tween va de "fuera a la izquierda" a
          // "en su sitio": al retroceder, se va.
          transitionBuilder: (child, animacion) {
            final entra = child.key == ValueKey(mostrandoCategorias);
            final desplazamiento = Tween<Offset>(
              begin: entra ? const Offset(1.2, 0) : const Offset(-1.2, 0),
              end: Offset.zero,
            ).animate(animacion);
            return SlideTransition(position: desplazamiento, child: child);
          },
          // Los dos superpuestos en el mismo sitio mientras cruzan.
          layoutBuilder: (actual, anteriores) => Stack(
            alignment: Alignment.center,
            children: [...anteriores, ?actual],
          ),
          child: Icon(
            mostrandoCategorias ? Icons.grid_view_rounded : Icons.label_outline,
            key: ValueKey(mostrandoCategorias),
          ),
        ),
      ),
    );
  }
}
