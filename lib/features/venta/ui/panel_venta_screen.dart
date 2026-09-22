import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nav/gesto_dos_dedos.dart';
import '../../../core/nav/retroceso.dart';
import '../../../core/theme/bento_bandeja.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_falla.dart';
import '../../../core/theme/bento_velo.dart';
import '../../auth/sesion_notifier.dart';
import '../../producto/producto_model.dart';
import '../../producto/producto_notifier.dart';
import '../../producto/producto_query_provider.dart';
import '../../../core/theme/bento_fotos.dart';
import '../../producto/ui/imagen_del_banco_vista.dart';
import '../../producto/ui/lista_productos_agrupada.dart';
import '../../producto/ui/producto_form_dialog.dart';
import 'casilla_sinpe.dart';
import 'elegir_variante.dart';
import '../linea_venta_model.dart';
import '../venta_model.dart';
import '../venta_en_curso_notifier.dart';

/// Ventana 2 — ver docs/pantallas/flujo-descripcion.md#ventana-2--panel-de-venta-carrito-completo
/// y docs/pantallas/prototipos-ascii.md. Carrito multi-línea + panel de
/// agregar producto (lista vertical, no cuadrícula — corregido tras
/// revisión del usuario).
class PanelVentaScreen extends ConsumerStatefulWidget {
  const PanelVentaScreen({super.key});

  @override
  ConsumerState<PanelVentaScreen> createState() => _PanelVentaScreenState();
}

class _PanelVentaScreenState extends ConsumerState<PanelVentaScreen> {
  bool _panelAbierto = false;

  // El estado del cobro vive acá y no dentro del carrito porque la barra de
  // cobro dejó de estar dentro de él: acostada cruza la pantalla entera por
  // debajo del carrito Y del panel, que es lo que la vuelve "la caja" y no un
  // apéndice de la lista.
  final _recibidoController = TextEditingController();
  double? _cambio;
  Timer? _debounce;
  bool _finalizando = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _recibidoController.dispose();
    super.dispose();
  }

  void _onRecibidoChanged(String valor, double total) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final recibido = double.tryParse(valor);
      setState(() => _cambio = recibido == null ? null : recibido - total);
    });
  }

  Future<void> _finalizar() async {
    setState(() => _finalizando = true);
    await ref.read(ventaEnCursoNotifierProvider.notifier).guardar();
    _recibidoController.clear();
    _cambio = null;
    if (mounted) {
      setState(() {
        _finalizando = false;
        _panelAbierto = false;
      });
      mostrarAviso(context, '✓ Venta OK');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(ventaEnCursoNotifierProvider).total;
    final hayLineas = ref.watch(ventaEnCursoNotifierProvider).lineas.isNotEmpty;
    final costura = _SeparadorConToggle(
      abierto: _panelAbierto,
      onTap: () => setState(() => _panelAbierto = !_panelAbierto),
    );
    final barra = _BarraDeCobro(
      controlador: _recibidoController,
      cambio: _cambio,
      total: total,
      habilitado: hayLineas && !_finalizando,
      sinpe: ref.watch(ventaEnCursoNotifierProvider).metodoPago == MetodoPago.sinpe,
      onSinpe: (activo) =>
          ref.read(ventaEnCursoNotifierProvider.notifier).marcarSinpe(activo: activo),
      onRecibidoChanged: (v) => _onRecibidoChanged(v, total),
      onFinalizar: _finalizar,
    );

    // El panel se ACOPLA AL LADO LARGO: a la derecha cuando hay ancho, ARRIBA
    // cuando no. Es el mismo panel persistente y el mismo botón de la costura,
    // rotados — no un overlay, que es lo que la decisión 0023 descarta.
    //
    // En teléfono la fila fija de antes repartía 3:4, o sea ~144 dp de carrito:
    // ahí no entra una línea de venta (miniatura 44 + nombre + subtotal + dos
    // botones de 48). Apilado, cada panel usa el ancho completo.
    //
    // Y va ARRIBA, no abajo: abajo empujaba la barra de cobro cada vez que se
    // abría o cerraba, así que el botón de Finalizar y el campo de Recibí se
    // movían debajo del dedo. Arriba, la zona con la que se cobra no se mueve
    // nunca — que es la que importa que esté quieta.
    if (BentoAncho.de(context).esCompacto) {
      return _conGestoDePanel(
        RetrocesoCierra(
          activo: _panelAbierto,
          alRetroceder: () => setState(() => _panelAbierto = false),
          child: Scaffold(
            body: Column(
              children: [
                // Abierto, el panel ocupa TODO el sitio del carrito: en un
                // teléfono un tercio de pantalla eran tres productos a la vista
                // y había que desplazar para todo — lo dijo el dueño probando:
                // "se queda muy pequeño". El carrito no se ve mientras se elige,
                // y no hace falta: la barra de cobro con el total sigue abajo,
                // quieta, y cerrar el panel devuelve la lista. En escritorio
                // sobra ancho y siguen conviviendo la mitad cada uno (abajo).
                //
                // Con el color de pozo, igual que acostado: es lo que se
                // despliega ENCIMA de la superficie de trabajo, así que tiene que
                // leerse por delante.
                if (_panelAbierto)
                  Expanded(
                    child: Padding(
                      // Bajo la muesca de la cámara: el panel llega hasta arriba.
                      padding: EdgeInsets.only(top: bentoInsetSuperior(context)),
                      child: BentoPozo(padding: EdgeInsets.zero, child: _PanelAgregarProducto()),
                    ),
                  )
                else ...[
                  // El botón de la costura es fijo: si quedara pegado al borde lo
                  // taparían la muesca de la cámara o una notificación que baje, y
                  // es el control que abre el panel.
                  SizedBox(height: bentoInsetSuperior(context)),
                  costura,
                  const Expanded(child: _ListaCarrito()),
                ],
                // Abierto, la costura baja a pegarse a la barra de cobro: es lo
                // que cierra el panel y ahí queda bajo el pulgar. La barra no se
                // mueve en ningún caso — es la zona con la que se cobra.
                if (_panelAbierto) costura,
                barra,
              ],
            ),
          ),
        ),
      );
    }

    // Acostado la barra de cobro sale de la fila y cruza el ancho COMPLETO por
    // debajo. Antes vivía dentro del carrito, y eso dejaba dos cosas mal: el
    // botón de la costura caía al costado DE la barra en vez de encima de ella
    // —medio fuera de la pantalla—, y la barra terminaba antes del borde, así
    // que no se leía como la zona de cobro sino como el pie de una lista.
    return _conGestoDePanel(
      RetrocesoCierra(
        activo: _panelAbierto,
        alRetroceder: () => setState(() => _panelAbierto = false),
        child: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Padding(
                  // Más aire a la derecha con el panel cerrado: ahí la costura es
                  // el último elemento y el botón, que sobresale de ella, quedaba
                  // al ras del borde de la pantalla.
                  padding: EdgeInsets.fromLTRB(
                    BentoSpacing.pared,
                    BentoSpacing.pared,
                    _panelAbierto ? BentoSpacing.pared : BentoSpacing.rim,
                    0,
                  ),
                  child: Row(
                    children: [
                      // Los dos NO están al mismo nivel, y eso tiene que verse.
                      //
                      // El carrito es la superficie de trabajo: se queda en el
                      // fondo de bandeja, sin relleno ni cresta propios. El panel
                      // abatible es lo que aparece encima, y por eso es el único
                      // con color de pozo y contorno. Darles a los dos el mismo
                      // pozo separaba, pero los dejaba empatados: dos
                      // compartimentos gemelos donde hay una base y algo que se
                      // despliega sobre ella.
                      Expanded(flex: _panelAbierto ? 3 : 5, child: const _ListaCarrito()),
                      costura,
                      if (_panelAbierto)
                        Expanded(
                          flex: 4,
                          child: BentoPozo(
                            padding: EdgeInsets.zero,
                            child: _PanelAgregarProducto(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              barra,
            ],
          ),
        ),
      ),
    );
  }

  /// Dos dedos hacia abajo abren el panel de productos; hacia arriba lo cierran.
  ///
  /// Primera acción de dos dedos de la app (decisión 0030). Abrir "hacia abajo"
  /// es el sentido de desplegar algo que estaba recogido, y da igual que el
  /// panel esté arriba de pie y al costado acostado: lo que se recuerda es el
  /// sentido del gesto, no dónde aparece la caja.
  ///
  /// El botón de la costura sigue estando: el gesto es un atajo para quien
  /// cobra con una mano todo el día, no la única forma de hacerlo.
  Widget _conGestoDePanel(Widget hijo) {
    // `Ctrl+P` hace lo mismo que el gesto en escritorio, donde no hay dedos.
    // Con `Ctrl` porque esta pantalla SÍ tiene campos —el de Recibí— y una P
    // suelta ahí es una letra.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            setState(() => _panelAbierto = !_panelAbierto),
      },
      child: GestoDeDosDedos(
        // `!_panelAbierto` en vez de alternar: repetir el gesto en el mismo
        // sentido no puede cerrar lo que acaba de abrir.
        alDeslizarAbajo: _panelAbierto ? null : () => setState(() => _panelAbierto = true),
        alDeslizarArriba: _panelAbierto ? () => setState(() => _panelAbierto = false) : null,
        child: hijo,
      ),
    );
  }
}

/// Costura entre el carrito y el panel de agregar producto, con el botón que
/// lo abre y lo cierra. El mismo botón hace las dos cosas y se "arrastra" con
/// el panel porque vive estructuralmente en la costura, no en una posición
/// fija.
///
/// Las dos orientaciones separan distinto, y a propósito:
/// - apilada (teléfono de pie) es una FRANJA con tono de bandeja, porque ahí
///   los dos paneles ocupan el ancho completo y no hay pared que los separe;
/// - vertical (acostado, tablet, escritorio) es solo la PARED entre dos pozos:
///   el material de bandeja ya está detrás y la cresta de cada pozo hace la
///   separación, así que pintarle un fondo encima sería una franja de más.
class _SeparadorConToggle extends StatelessWidget {
  const _SeparadorConToggle({required this.abierto, required this.onTap});

  final bool abierto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final horizontal = BentoAncho.de(context).esCompacto;

    // Tooltip además del icono: es el único control de la pantalla sin texto, y
    // sin etiqueta no lo anuncia un lector de pantalla ni lo encuentra el
    // harness de pruebas.
    final boton = Tooltip(
      message: abierto ? 'Cerrar panel de productos' : 'Agregar productos',
      child: Material(
        key: const ValueKey('costura_toggle'),
        color: scheme.primaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(BentoSpacing.unidad),
            child: Icon(
              // El icono apunta hacia donde se va el panel: a la derecha cuando
              // la costura es vertical, hacia abajo cuando es horizontal.
              abierto
                  ? (horizontal ? Icons.expand_less : Icons.chevron_right)
                  : Icons.add_shopping_cart,
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );

    final fondo = ColoredBox(color: lacaDe(context).bandeja);

    // Costura horizontal: la franja cruza la pantalla y el botón se ancla a la
    // DERECHA, a la misma altura. Centrado quedaba en medio del recorrido de
    // lectura y lejos del pulgar; contra el borde derecho cae donde la mano ya
    // está, y deja libre el resto de la franja.
    if (horizontal) {
      return SizedBox(
        height: bentoObjetivoTactilMin,
        child: Stack(
          children: [
            Positioned.fill(child: fondo),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: BentoSpacing.gapCelda),
                child: boton,
              ),
            ),
          ],
        ),
      );
    }

    // Costura vertical: es la PARED entre dos pozos, así que no lleva fondo
    // propio —el material de bandeja ya está detrás— y el botón se ancla ABAJO
    // del todo. Ahí queda encima de la barra de cobro y a la derecha del
    // carrito, que es donde lo esperaba el usuario; antes vivía a media altura
    // y terminaba AL LADO de la barra, medio fuera de la pantalla.
    return SizedBox(
      width: BentoSpacing.gapGrupo,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: BentoSpacing.unidad),
          // `OverflowBox`: la costura mide 24 y el botón 36, así que el ancho
          // de la costura lo APLASTABA — el círculo se recortaba a 24 y el
          // icono, que sigue midiendo 20 más su padding, terminaba corrido y
          // saliéndose por la derecha. Con esto el botón toma su tamaño natural
          // y queda centrado sobre la pared.
          child: OverflowBox(
            maxWidth: bentoObjetivoTactilMin,
            alignment: Alignment.center,
            child: boton,
          ),
        ),
      ),
    );
  }
}

/// Solo la lista de líneas: la barra de cobro es hermana suya, no hija — ver
/// el porqué en el layout acostado de [_PanelVentaScreenState].
class _ListaCarrito extends ConsumerWidget {
  const _ListaCarrito();

  Future<void> _editarLinea(BuildContext context, LineaVenta linea) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DialogoEditarLinea(linea: linea),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ventaEnCurso = ref.watch(ventaEnCursoNotifierProvider);
    final productos = ref.watch(productoQueryProvider).valueOrNull ?? const <Producto>[];
    final iconos = ref.watch(iconosDeCategoriaProvider);

    if (ventaEnCurso.lineas.isEmpty) {
      // El texto sigue al panel: en teléfono la costura está ABAJO, y decir "a
      // la derecha" mandaba al usuario a mirar donde no hay nada. Es el tipo de
      // incoherencia que aparece al mover algo de sitio y no revisar lo que lo
      // nombra.
      return Center(
        child: Text(
          BentoAncho.de(context).esCompacto
              ? 'Agregá productos con el botón de arriba'
              : 'Agregá productos con el botón de la derecha',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(BentoSpacing.gapCelda),
      itemCount: ventaEnCurso.lineas.length,
      separatorBuilder: (_, _) => const SizedBox(height: BentoSpacing.unidad),
      itemBuilder: (context, i) {
        final linea = ventaEnCurso.lineas[i];
        final producto = _buscarProducto(linea.productoId, productos);
        final nombre = linea.nombreLibre ?? producto?.nombre ?? _sinProducto(linea.productoId);
        return _FilaLineaVenta(
          // Con la variante detrás: "Pollo frito · Pechuga y ala". Es lo que
          // se cobró, y sin ella dos líneas del mismo producto a distinto
          // precio se ven como un error.
          nombre: linea.describir(nombre),
          imagen: producto?.imagen,
          iconoDeSuCategoria: iconos[producto?.categoriaId],
          lineaLibre: linea.nombreLibre != null,
          cantidad: linea.cantidad,
          nota: linea.nota,
          subtotal: linea.precioAplicado * linea.cantidad,
          onEditar: () => _editarLinea(context, linea),
          onQuitar: () => ref.read(ventaEnCursoNotifierProvider.notifier).quitarLinea(linea.id),
        );
      },
    );
  }

  Producto? _buscarProducto(String? productoId, List<Producto> productos) {
    if (productoId == null) return null;
    for (final p in productos) {
      if (p.id == productoId) return p;
    }
    return null;
  }

  String _sinProducto(String? productoId) => productoId == null ? 'Producto' : 'Producto eliminado';
}

/// Recibí · Cambio · Total · Finalizar.
///
/// En teléfono va en DOS filas de la retícula (3+3 y 3+3) en vez de una sola:
/// las cuatro piezas juntas eran el desborde más probable de la app, porque un
/// campo de texto, dos importes en colones y un botón no entran en 360 dp.
///
/// Sin `Material(elevation: 4)`: la sombra levantaba la barra de la bandeja
/// (DESIGN.md regla 1, prohibidas las sombras suaves — la escena de uso es sol
/// directo). El escalón lo marca ahora el pozo, como el resto de la app.
class _BarraDeCobro extends StatelessWidget {
  const _BarraDeCobro({
    required this.controlador,
    required this.cambio,
    required this.total,
    required this.habilitado,
    required this.sinpe,
    required this.onSinpe,
    required this.onRecibidoChanged,
    required this.onFinalizar,
  });

  final TextEditingController controlador;
  final double? cambio;
  final double total;
  final bool habilitado;
  final bool sinpe;
  final ValueChanged<bool> onSinpe;
  final ValueChanged<String> onRecibidoChanged;
  final VoidCallback onFinalizar;

  @override
  Widget build(BuildContext context) {
    final recibido = TextField(
      controller: controlador,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Recibí', isDense: true),
      onChanged: onRecibidoChanged,
    );
    final textoCambio = Align(
      alignment: Alignment.centerLeft,
      child: Text(cambio == null ? 'Cambio: —' : 'Cambio: ₡${cambio!.toStringAsFixed(2)}'),
    );
    final vertical = BentoAncho.de(context).esCompacto;
    // Apilado, Cambio y Total quedan uno debajo del otro en la misma columna:
    // con uno pegado a la izquierda y el otro a la derecha, dos importes que se
    // leen juntos no compartían margen y la columna se veía descuadrada.
    // Acostado van en celdas distintas de la misma fila y ahí el Total sí cierra
    // contra su borde, al lado del botón.
    final textoTotal = Align(
      alignment: vertical ? Alignment.centerLeft : Alignment.centerRight,
      child: Text('₡${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
    );
    final casillaSinpe = CasillaSinpe(activa: sinpe, onCambio: onSinpe);
    final finalizar = FilledButton(
      onPressed: habilitado ? onFinalizar : null,
      // Una línea: en la celda de 1/6 de la retícula "Finalizar" se partía en
      // "Finaliza/r", que en la acción principal de la pantalla se lee como un
      // defecto.
      child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Finalizar', maxLines: 1)),
    );

    return ColoredBox(
      color: lacaDe(context).pozo,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
          child: BentoCuadricula(
            // En dos filas, Recibí arriba-izquierda y Finalizar abajo-derecha
            // dejaban los dos elementos INTERACTIVOS en diagonal, con los dos
            // textos cruzándolos. Invirtiendo Recibí y Cambio, lo que se toca
            // queda en la misma columna y lo que solo se lee en la otra.
            //
            // En una sola fila —tablet y escritorio— no hay diagonal que
            // arreglar, y ahí el orden natural es Recibí antes que Cambio:
            // primero se escribe, después se lee el resultado.
            hijos: vertical
                ? [
                    // SINPE en su propia fila y a lo ancho: es lo que hay que
                    // acordarse de marcar ANTES de cobrar, y una casilla
                    // apretada en media celda se pasa por alto.
                    BentoCelda(compacto: 6, medio: 6, amplio: 6, hijo: casillaSinpe),
                    BentoCelda(compacto: 3, medio: 3, amplio: 3, hijo: textoCambio),
                    BentoCelda(compacto: 3, medio: 3, amplio: 3, hijo: recibido),
                    BentoCelda(compacto: 3, medio: 3, amplio: 3, hijo: textoTotal),
                    BentoCelda(compacto: 3, medio: 3, amplio: 3, hijo: finalizar),
                  ]
                : [
                    BentoCelda(compacto: 1, medio: 1, amplio: 1, hijo: casillaSinpe),
                    BentoCelda(compacto: 2, medio: 2, amplio: 2, hijo: recibido),
                    BentoCelda(compacto: 1, medio: 1, amplio: 1, hijo: textoCambio),
                    BentoCelda(compacto: 1, medio: 1, amplio: 1, hijo: textoTotal),
                    BentoCelda(compacto: 1, medio: 1, amplio: 1, hijo: finalizar),
                  ],
          ),
        ),
      ),
    );
  }
}

/// Fila del carrito — mismo lenguaje visual que `_TarjetaProducto` de
/// Ventana 1 (imagen + nombre + precio), en formato de fila en vez de tarjeta
/// porque aquí el contexto es una lista angosta, no un grid (consistencia entre
/// pantallas pedida por la skill `aesthetic-usability`: la misma "pieza" de
/// producto en toda la app).
///
/// Todo producto de la carta trae cara —la que eligió o la de su categoría—, y
/// la línea libre trae su lápiz, que es lo que la distingue de un producto del
/// catálogo. El único caso sin miniatura es el producto que ya no existe: no
/// hay de dónde sacarle categoría, y un icono neutro ahí solo gastaría los 52
/// dp que el carrito angosto necesita para el nombre.
class _FilaLineaVenta extends StatelessWidget {
  const _FilaLineaVenta({
    required this.nombre,
    required this.imagen,
    required this.iconoDeSuCategoria,
    required this.lineaLibre,
    required this.cantidad,
    required this.nota,
    required this.subtotal,
    required this.onEditar,
    required this.onQuitar,
  });

  final String nombre;

  /// Lo guardado en `producto.imagen`. Nulo cuando nadie eligió ninguna: la
  /// cara sale entonces de [categoria].
  final String? imagen;

  /// La clave del icono que le toca por su categoría, ya resuelta. Nulo solo si
  /// el producto ya no está en el catálogo, y entonces la fila va sin
  /// miniatura.
  final String? iconoDeSuCategoria;

  final bool lineaLibre;
  final int cantidad;
  final String? nota;
  final double subtotal;
  final VoidCallback onEditar;
  final VoidCallback onQuitar;

  /// Por debajo de este ancho la fila no entra de una: la miniatura (44), los
  /// dos botones (48+48) y el subtotal ya se comen casi todo, y al nombre no le
  /// queda nada.
  static const _anchoMinimoEnUnaFila = 320.0;

  /// Sin miniatura la fila aguanta más angosta antes de partirse en dos: son 52
  /// dp que se le devuelven al nombre.
  static const _anchoMinimoSinMiniatura = 268.0;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    // La línea libre SÍ lleva marca aunque no tenga imagen: el lápiz es lo que
    // la distingue de un producto de la carta, o sea es un dato, no un relleno.
    final miniatura = lineaLibre
        ? Container(
            width: bentoMiniatura,
            height: bentoMiniatura,
            decoration: BoxDecoration(
              color: lacaDe(context).pozoContacto,
              borderRadius: BorderRadius.circular(BentoRadius.pozo - BentoSpacing.unidad / 2),
            ),
            child: const Icon(Icons.edit_note, size: 22),
          )
        : imagen == null && iconoDeSuCategoria == null
        ? null
        : SizedBox(
            width: bentoMiniatura,
            height: bentoMiniatura,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BentoRadius.pozo - BentoSpacing.unidad / 2),
              child: ImagenDelBancoVista(
                referencia: imagen,
                ventana: VentanaConFotos.venta,
                iconoDeSuCategoria: iconoDeSuCategoria,
              ),
            ),
          );

    // `maxLines` + elipsis SIEMPRE, no solo cuando el ancho aprieta: sin esto,
    // un `Text` al que le queda un ancho de dos caracteres parte el nombre
    // LETRA POR LETRA en vertical. Es lo que se veía en el carrito con el panel
    // abierto: "F / r / ap / p / é" encima del precio.
    final titulo = Text(
      nombre,
      style: tema.textTheme.bodyLarge,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
    final detalle = Text(
      'x$cantidad${nota != null && nota!.isNotEmpty ? ' · $nota' : ''}',
      style: tema.textTheme.bodySmall,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final precio = Text(
      '₡${subtotal.toStringAsFixed(2)}',
      style: tema.textTheme.labelLarge,
      maxLines: 1,
    );
    final editar = IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEditar);
    final quitar = IconButton(icon: const Icon(Icons.delete_outline), onPressed: onQuitar);

    return BentoPozo(
      padding: const EdgeInsets.all(BentoSpacing.unidad),
      child: LayoutBuilder(
        builder: (context, restricciones) {
          final minimo = miniatura == null ? _anchoMinimoSinMiniatura : _anchoMinimoEnUnaFila;
          if (restricciones.maxWidth >= minimo) {
            return Row(
              children: [
                if (miniatura != null) ...[miniatura, const SizedBox(width: BentoSpacing.unidad)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [titulo, detalle],
                  ),
                ),
                precio,
                editar,
                quitar,
              ],
            );
          }

          // Angosto —el carrito con el panel de productos abierto— en dos
          // líneas: qué es arriba, cuánto y qué hacer con ello abajo. Los
          // botones conservan sus 48 dp táctiles, que es lo que no se puede
          // negociar.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (miniatura != null) ...[miniatura, const SizedBox(width: BentoSpacing.unidad)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [titulo, detalle],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BentoSpacing.unidad / 2),
              Row(
                children: [
                  Expanded(child: precio),
                  editar,
                  quitar,
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DialogoEditarLinea extends ConsumerStatefulWidget {
  const _DialogoEditarLinea({required this.linea});

  final LineaVenta linea;

  @override
  ConsumerState<_DialogoEditarLinea> createState() => _DialogoEditarLineaState();
}

class _DialogoEditarLineaState extends ConsumerState<_DialogoEditarLinea> {
  late final TextEditingController _precioController;
  late final TextEditingController _notaController;
  late int _cantidad;

  @override
  void initState() {
    super.initState();
    _precioController = TextEditingController(text: widget.linea.precioAplicado.toStringAsFixed(2));
    _notaController = TextEditingController(text: widget.linea.nota ?? '');
    _cantidad = widget.linea.cantidad;
  }

  @override
  void dispose() {
    _precioController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  void _guardar() {
    ref
        .read(ventaEnCursoNotifierProvider.notifier)
        .editarLinea(
          widget.linea.id,
          precioAplicado: double.tryParse(_precioController.text),
          cantidad: _cantidad,
          nota: _notaController.text.trim().isEmpty ? null : _notaController.text.trim(),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BentoDialogo(
      titulo: const Text('Editar línea'),
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cantidad'),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                  ),
                  Text('$_cantidad'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _cantidad++),
                  ),
                ],
              ),
            ],
          ),
          TextField(
            controller: _precioController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio'),
          ),
          TextField(
            controller: _notaController,
            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
          ),
        ],
      ),
      acciones: BentoAcciones(
        izquierda: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
        derecha: [FilledButton(onPressed: _guardar, child: const Text('Guardar'))],
      ),
    );
  }
}

/// Lista vertical (no cuadrícula, ver decisión del usuario) de productos
/// disponibles. Toque simple agrega; mantener presionado entra en
/// selección múltiple.
class _PanelAgregarProducto extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PanelAgregarProducto> createState() => _PanelAgregarProductoState();
}

class _PanelAgregarProductoState extends ConsumerState<_PanelAgregarProducto> {
  final Set<String> _seleccionados = {};
  bool get _modoSeleccion => _seleccionados.isNotEmpty;

  /// Con variantes pregunta cuál antes de agregar (0039); cancelar la pregunta
  /// no agrega nada. Sin variantes, un toque como siempre.
  Future<void> _agregarUno(Producto producto) async {
    var precio = producto.precioBase;
    String? variante;
    if (producto.tieneVariantes) {
      final elegida = await elegirVariante(context, producto);
      if (elegida == null || !mounted) return;
      precio = elegida.precio;
      variante = elegida.nombre;
    }
    ref
        .read(ventaEnCursoNotifierProvider.notifier)
        .agregarLineaDeCatalogo(productoId: producto.id, precioAplicado: precio, variante: variante);
  }

  /// Uno por uno y en orden: los que tienen variantes preguntan, y dos
  /// preguntas a la vez no se pueden contestar.
  Future<void> _agregarSeleccionados(List<Producto> productos) async {
    for (final id in _seleccionados.toList()) {
      final producto = productos.where((p) => p.id == id).firstOrNull;
      if (producto != null) await _agregarUno(producto);
      if (!mounted) return;
    }
    setState(() => _seleccionados.clear());
  }

  Future<void> _lineaLibre() async {
    final nombreController = TextEditingController();
    final precioController = TextEditingController();
    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('Línea libre'),
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: precioController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio'),
            ),
          ],
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
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (resultado != true) return;
    final nombre = nombreController.text.trim();
    final precio = double.tryParse(precioController.text);
    if (nombre.isEmpty || precio == null) return;
    ref
        .read(ventaEnCursoNotifierProvider.notifier)
        .agregarLineaLibre(nombreLibre: nombre, precio: precio);
  }

  @override
  Widget build(BuildContext context) {
    final productosAsync = ref.watch(productoAgrupadoProvider);
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;

    return Column(
      children: [
        // Cascada invertida: el buscador vive abajo (ver barra inferior), asi
        // que la lista crece hacia arriba desde ahi — con `reverse: true` el
        // primer resultado (mejor match, mismo orden que ya calculaba
        // productoQueryProvider) queda pegado al buscador, y el resto se aleja
        // hacia arriba en vez de leerse de arriba hacia abajo.
        Expanded(
          child: productosAsync.when(
            data: (grupos) => ListaProductosAgrupada(
              grupos: grupos,
              invertida: true,
              padding: EdgeInsets.only(
                left: BentoSpacing.unidad,
                right: BentoSpacing.unidad,
                // El padding de un scroll va en COORDENADAS DE PANTALLA,
                // tambien con `reverse: true` — verificado. Antes esto decia
                // `bottom` creyendo lo contrario, y el resultado era que la
                // lista se despegaba del buscador y se iba hacia arriba: justo
                // lo que rompia la cascada invertida.
                top: bentoInsetSuperior(context),
              ),
              // Una fila por producto: este panel es angosto y lo que se busca
              // acá es el nombre, no comparar tarjetas.
              porFila: 1,
              // Sin alto: cada fila mide lo que pida su nombre. El nombre es lo
              // ÚNICO que se lee acá para elegir, y con una sola línea
              // "Arroz con pollo, tipo chino (entero)" y "…(medio)" quedaban
              // idénticos en pantalla.
              celda: (producto) {
                final seleccionado = _seleccionados.contains(producto.id);
                return ListTile(
                  leading: seleccionado ? const Icon(Icons.check_circle) : null,
                  title: Text(producto.nombre),
                  trailing: Text(precioParaMostrar(producto, decimales: 2)),
                  selected: seleccionado,
                  onTap: () {
                    if (_modoSeleccion) {
                      setState(() {
                        seleccionado
                            ? _seleccionados.remove(producto.id)
                            : _seleccionados.add(producto.id);
                      });
                    } else {
                      _agregarUno(producto);
                    }
                  },
                  onLongPress: () => setState(() => _seleccionados.add(producto.id)),
                );
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => BentoFalla(
              mensaje: 'No se pudo cargar el catálogo.',
              error: e,
              onReintentar: () => ref.invalidate(productoNotifierProvider),
            ),
          ),
        ),
        // El botón de la selección múltiple ocupaba una franja entera con el
        // padding de un botón principal, y en el panel apilado eso se comía una
        // fila de productos. Ahora entra EN la barra de abajo, junto al
        // buscador: aparece solo mientras hay algo seleccionado y no empuja
        // nada.
        // Barra inferior unificada: buscador + acciones en el mismo panel
        // (antes el buscador vivia arriba, separado de estos botones).
        ColoredBox(
          color: lacaDe(context).pozo,
          child: Padding(
            // Vertical a la mitad: esta barra es fija y todo lo que ocupa se lo
            // quita a la lista de productos, que es lo que se viene a mirar.
            padding: const EdgeInsets.symmetric(
              horizontal: BentoSpacing.unidad,
              vertical: BentoSpacing.unidad / 2,
            ),
            child: Row(
              children: [
                if (_modoSeleccion)
                  Padding(
                    padding: const EdgeInsets.only(right: BentoSpacing.unidad / 2),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: BentoSpacing.paddingCelda),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text('${_seleccionados.length}'),
                      onPressed: () => _agregarSeleccionados([
                        for (final g in productosAsync.valueOrNull ?? const []) ...g.productos,
                      ]),
                    ),
                  ),
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
                IconButton(
                  icon: const Icon(Icons.note_add_outlined),
                  tooltip: 'Línea libre',
                  onPressed: _lineaLibre,
                ),
                if (esGerente)
                  IconButton(
                    icon: const Icon(Icons.add_box_outlined),
                    tooltip: 'Producto nuevo al vuelo',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ProductoFormDialog(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
