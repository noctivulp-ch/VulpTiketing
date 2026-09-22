import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_fotos.dart';
import '../../../core/theme/bento_tallado.dart';
import '../../../core/theme/bento_velo.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_falla.dart';
import '../../producto/producto_model.dart';
import '../../producto/producto_notifier.dart';
import '../../producto/producto_query_provider.dart';
import '../../producto/ui/imagen_del_banco_vista.dart';
import '../../producto/ui/lista_productos_agrupada.dart';
import 'cobro_rapido_overlay.dart';
import 'elegir_variante.dart';

/// Ventana 1 — ver docs/pantallas/flujo-descripcion.md#ventana-1--venta-rápida
/// y docs/pantallas/prototipos-ascii.md. Crea una Venta de una sola línea
/// reutilizando VentaEnCursoNotifier (mismo modelo que la Ventana 2, ruta de
/// UI más corta para el caso de un producto).
class VentaRapidaScreen extends ConsumerWidget {
  const VentaRapidaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productosAsync = ref.watch(productoAgrupadoProvider);

    // Una sola bandeja: el buscador y el grid son pozos tallados en ella,
    // separados por paredes de material. Sin AppBar — la barra superior de
    // Material seria una pieza pegada ENCIMA de la bandeja, no un hueco
    // dentro (DESIGN.md, regla 8).
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: BentoBandeja(
              child: productosAsync.when(
                data: (grupos) {
                  if (grupos.every((g) => g.productos.isEmpty)) return const _SinProductos();
                  final iconos = ref.watch(iconosDeCategoriaProvider);
                  return ListaProductosAgrupada(
                    grupos: grupos,
                    // Padding del SCROLL, no del contenedor: así las
                    // tarjetas suben y se desvanecen bajo el velo en vez
                    // de frenar contra un borde.
                    padding: EdgeInsets.only(top: bentoInsetSuperior(context)),
                    // Columnas EXPLÍCITAS: cada producto ocupa 3, 2 o 1
                    // de las 6 columnas de la retícula, o sea 2 por fila
                    // en teléfono, 3 en tablet y 6 en escritorio.
                    //
                    // Antes era `maxCrossAxisExtent: 190`, donde el
                    // número de columnas salía de si 190 dp entraban o
                    // no: la cuadrícula era un efecto secundario del
                    // ancho, no una decisión, y por eso no se leía como
                    // una forma deliberada.
                    porFila: bentoPorFila(BentoAncho.de(context), compacto: 3, medio: 2, amplio: 1),
                    // La celda ALARGA en vez de apretar el texto, y su alto
                    // se CALCULA en vez de salir de una proporción con el
                    // ancho: lo que tiene que caber son el hueco de la imagen,
                    // tres líneas de nombre y el precio, y ninguna de esas tres
                    // cosas depende de lo ancha que sea la columna.
                    //
                    // Con proporción el nombre se partía a media línea en el
                    // aparato —"(medio)" cortado por la mitad—, que es peor que
                    // elidir: no se lee y encima parece un fallo de pintado. Y
                    // recortarlo a "Arroz cant…" para que entrara el dibujo
                    // dejaba la tarjeta más bonita y menos útil: en una carta
                    // de cuarenta productos el nombre es lo que se lee para
                    // cobrar. Caben menos productos por pantalla; es el precio
                    // de mostrar las dos cosas enteras.
                    altoCelda: _altoDeCelda(context),
                    celda: (producto) => _TarjetaProducto(
                      producto: producto,
                      iconoDeSuCategoria: iconos[producto.categoriaId],
                      onTap: () => _abrirCobroRapido(context, ref, producto),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => BentoFalla(
                  mensaje: 'No se pudo cargar el catálogo.',
                  error: e,
                  onReintentar: () => ref.invalidate(productoNotifierProvider),
                ),
              ),
            ),
          ),
          // El buscador va ABAJO, al alcance del pulgar y en el mismo sitio
          // que en Catálogo y que en el panel de Ventana 2: las tres pantallas
          // que buscan productos lo tienen en el mismo borde.
          //
          // Y va FUERA de la bandeja, a lo ancho de la pantalla y pegado al
          // borde, igual que en esas dos. Dentro del labio de la bandeja
          // quedaba un pozo con aire por los cuatro costados: se leía como un
          // elemento flotando, no como la barra de la pantalla.
          ColoredBox(
            color: lacaDe(context).pozo,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BentoSpacing.paddingCelda,
                  vertical: BentoSpacing.unidad / 2,
                ),
                child: TextField(
                  // CON su contorno, como los otros dos buscadores. Estaba en
                  // `none` de cuando el campo vivía dentro de un pozo y el pozo
                  // ya ponía el marco; al sacarlo a la barra se quedó sin
                  // ningún borde, así que no se leía como algo donde se escribe.
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar producto o categoría…',
                  ),
                  onChanged: (v) => ref.read(productoBusquedaProvider.notifier).state = v,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lo que mide una tarjeta: el hueco de la imagen, tres líneas de nombre y el
  /// precio, más los aires del pozo.
  ///
  /// Se suma a partir de los estilos del tema y no de constantes, para que siga
  /// al tamaño de letra del sistema: con la letra grande de Android las tres
  /// líneas ocupan bastante más, y un alto fijo volvería a cortar el nombre —
  /// justo el fallo que esto arregla.
  static double _altoDeCelda(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final escala = MediaQuery.textScalerOf(context);
    double lineaDe(TextStyle? estilo) =>
        escala.scale(estilo?.fontSize ?? 14) * (estilo?.height ?? 1.35);

    return BentoSpacing.unidad * 1.5 * 2 + // el padding del pozo, arriba y abajo
        _TarjetaProducto.altoImagen +
        BentoSpacing.unidad +
        lineaDe(textos.bodyLarge) * _TarjetaProducto.lineasDelNombre +
        BentoSpacing.unidad / 2 +
        lineaDe(textos.titleLarge);
  }

  Future<void> _abrirCobroRapido(BuildContext context, WidgetRef ref, Producto producto) async {
    final completado = await showDialog<bool>(
      context: context,
      builder: (_) => CobroRapidoOverlay(producto: producto),
    );
    if (completado == true && context.mounted) {
      mostrarAviso(context, '✓ Venta OK');
    }
  }
}

/// Estado vacio que enseña la interfaz en vez de decir "no hay nada"
/// (bandeja recien puesta, todavia sin compartimentos servidos).
class _SinProductos extends StatelessWidget {
  const _SinProductos();

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'La bandeja está vacía',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: laca.textoEnBandeja),
          ),
          const SizedBox(height: BentoSpacing.unidad),
          Text(
            'Agregá productos en Catálogo, o importá el menú desde Configuración.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: laca.textoAtenuadoEnBandeja),
          ),
        ],
      ),
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({
    required this.producto,
    required this.iconoDeSuCategoria,
    required this.onTap,
  });

  /// Lo justo para reconocer el icono de un vistazo. Más alto no ayuda a
  /// distinguir una taza de un plato, y sale del sitio del nombre.
  static const altoImagen = 56.0;

  /// "Arroz con pollo, tipo chino (medio)" necesita las tres para no quedarse
  /// en "Arroz con pollo, tipo…", que no lo distingue del entero.
  static const lineasDelNombre = 3;

  final Producto producto;

  /// La clave del icono que le toca por su categoría, ya resuelta: es la cara
  /// que lleva cuando nadie le eligió imagen propia.
  final String? iconoDeSuCategoria;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final tema = Theme.of(context);

    return BentoPozo(
      onTap: onTap,
      padding: const EdgeInsets.all(BentoSpacing.unidad * 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El hueco va SIEMPRE: todo producto tiene cara, la que eligió o la
          // de su categoría. Antes solo aparecía con imagen elegida, y una
          // cuadrícula con unas celdas con dibujo y otras sin él se lee peor
          // que una donde todas lo tienen — las filas dejan de alinearse y la
          // vista se vuelve irregular sin que eso signifique nada.
          //
          // Alto FIJO, no `Expanded`: compitiendo con el nombre por el sitio
          // sobrante se llevaba la mitad de la celda y dejaba el nombre en
          // una línea.
          SizedBox(
            height: altoImagen,
            width: double.infinity,
            // Rebaje mas profundo DENTRO del pozo, no una tarjeta anidada:
            // es el platito metido en el compartimento (referencias
            // visuales, fotos 2 y 5), de ahi el tono de sombra de contacto.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BentoRadius.pozo / 2),
              child: ImagenDelBancoVista(
                referencia: producto.imagen,
                ventana: VentanaConFotos.ventaRapida,
                iconoDeSuCategoria: iconoDeSuCategoria,
              ),
            ),
          ),
          const SizedBox(height: BentoSpacing.unidad),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: BentoTextoTallado(
                producto.nombre,
                sobre: laca.pozo,
                maxLines: lineasDelNombre,
                overflow: TextOverflow.ellipsis,
                estilo: tema.textTheme.bodyLarge,
              ),
            ),
          ),
          const SizedBox(height: BentoSpacing.unidad / 2),
          // El precio es el dato que decide la accion, asi que su jerarquia la
          // dan el tamano y el peso — NO se le baja el contraste. Con nivel
          // `marcado` quedaba mas apagado que el nombre del producto, o sea
          // invertia la jerarquia: el tallado se comia justo lo que tenia que
          // destacar. `marcado` queda reservado para los numeros de 40px de
          // Reportes, donde el tamano lo sostiene solo.
          // Con variantes es el precio de la por defecto (0039). `FittedBox`
          // por si un precio largo no entra en la tarjeta.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: BentoTextoTallado(
              precioParaMostrar(producto),
              sobre: laca.pozo,
              estilo: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
