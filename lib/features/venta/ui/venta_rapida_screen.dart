import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_tallado.dart';
import '../../../core/theme/bento_velo.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/ui/bento_falla.dart';
import '../../producto/producto_model.dart';
import '../../producto/producto_notifier.dart';
import '../../producto/producto_query_provider.dart';
import '../../producto/ui/lista_productos_agrupada.dart';
import 'cobro_rapido_overlay.dart';

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
                data: (grupos) => grupos.every((g) => g.productos.isEmpty)
                    ? const _SinProductos()
                    : ListaProductosAgrupada(
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
                        porFila: bentoPorFila(
                          BentoAncho.de(context),
                          compacto: 3,
                          medio: 2,
                          amplio: 1,
                        ),
                        // Mas ancho que alto: sin hueco de imagen el pozo
                        // solo tiene que sostener nombre y precio, y una
                        // celda alta dejaba un vacio muerto en el medio.
                        //
                        // Acostado, más ancho: con 360 dp de alto y la
                        // proporción de pie entraba UNA fila de productos y
                        // sobraban 90 dp en blanco. Con 1.8 entran dos filas y
                        // el nombre conserva sus dos líneas — con 2.6 entraban
                        // dos y media, pero "Arroz cantones (entero)" se
                        // cortaba en "Arroz cantones" y dejaba de distinguirse
                        // del medio: más carta a la vista y menos legible no es
                        // mejor.
                        relacionCelda: bentoEstaAcostado(context) ? 1.8 : 1.25,
                        celda: (producto) => _TarjetaProducto(
                          producto: producto,
                          onTap: () => _abrirCobroRapido(context, ref, producto),
                        ),
                      ),
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
  const _TarjetaProducto({required this.producto, required this.onTap});

  final Producto producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final tema = Theme.of(context);
    final tieneImagen = producto.imagen != null;

    return BentoPozo(
      onTap: onTap,
      padding: const EdgeInsets.all(BentoSpacing.unidad * 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sin imagen no se reserva el hueco: un rebaje vacio con un icono
          // generico se comia el 60% de la celda para no decir nada. Lo que
          // se lee al cobrar es el nombre y el precio, asi que ellos ocupan
          // el compartimento.
          if (tieneImagen)
            Expanded(
              // Rebaje mas profundo DENTRO del pozo, no una tarjeta anidada:
              // es el platito metido en el compartimento (referencias
              // visuales, fotos 2 y 5), de ahi el tono de sombra de contacto.
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: laca.pozoContacto,
                  borderRadius: BorderRadius.circular(BentoRadius.pozo / 2),
                ),
                child: Center(child: Icon(Icons.image_outlined, size: 32, color: laca.paredCresta)),
              ),
            ),
          if (tieneImagen) const SizedBox(height: BentoSpacing.unidad),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: BentoTextoTallado(
                producto.nombre,
                sobre: laca.pozo,
                maxLines: 3,
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
          BentoTextoTallado(
            '₡${producto.precioBase.toStringAsFixed(0)}',
            sobre: laca.pozo,
            estilo: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
