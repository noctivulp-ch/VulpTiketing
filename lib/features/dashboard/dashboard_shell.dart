import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bento_bandeja.dart';
import '../../core/nav/atajos_escritorio.dart';
import '../import_export/archivo_entrante_service.dart';
import '../import_export/ui/archivo_entrante_dialogo.dart';
import '../sync/sync_notifier.dart';
import '../../core/nav/gesto_navegacion.dart';
import '../../core/theme/bento_cuadricula.dart';
import '../../core/theme/bento_icon.dart';
import '../../core/theme/bento_velo.dart';
import '../../core/theme/bento_theme.dart';
import '../configuracion/ui/configuracion_screen.dart';
import '../producto/ui/producto_crud_screen.dart';
import '../reportes/ui/reportes_screen.dart';
import '../venta/ui/panel_venta_screen.dart';
import '../venta/ui/venta_rapida_screen.dart';

/// Shell de navegacion (decision de pantallas: docs/pantallas/flujo-descripcion.md
/// #dashboard-shell-de-navegacion). Rail lateral en pantalla ancha, pestanas
/// inferiores en angosta — SOLO iconos, sin texto (lenguaje no-textual,
/// docs/pantallas/prototipos-ascii.md#principios-aplicados-en-esta-pasada).
/// Iconos propios (docs/pantallas/iconografia.md), no Material Icons.
///
/// Las 5 pantallas se mantienen montadas via `IndexedStack` — cambiar de
/// pestana solo cambia que subarbol es visible, no destruye/reconstruye la
/// pantalla saliente. Reemplazar el hijo directamente (`_pantallas[_indice]`)
/// causaba un parpadeo real al cambiar de tab: cada pantalla perdia su
/// estado y volvia a pedir datos a sus providers desde cero, y como no todas
/// tienen la misma barra superior, el salto de layout se veia como un
/// parpadeo.
///
/// `IndexedStack` solo controla que subarbol se PINTA — no excluye del foco
/// de teclado a las pantallas ocultas, asi que sin `ExcludeFocus` un Tab
/// podia saltar a un campo de busqueda o boton de una pantalla invisible
/// (bug real encontrado al verificar la navegacion por teclado de las
/// fases siguientes).
class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> with WidgetsBindingObserver {
  StreamSubscription<void>? _archivos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // El aviso del lado nativo, para el caso en que la app ya estaba abierta:
    // ahí no hay cambio de ciclo de vida al que engancharse.
    _archivos = ArchivoEntranteService.avisos.listen((_) {
      if (mounted) atenderArchivoEntrante(context, ref);
    });
    // El archivo con el que se abrió la app, si se abrió tocando uno. Se atiende
    // acá y no en el arranque porque importar o restaurar necesita la sesión ya
    // abierta — y el archivo espera: el lado nativo lo guarda hasta que alguien
    // lo recoge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) atenderArchivoEntrante(context, ref);
    });
  }

  @override
  void dispose() {
    _archivos?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Con la app ya abierta, tocar un archivo la trae al frente sin recrear
    // nada: el intent llega por `onNewIntent` y este es el único aviso de que
    // hay algo que recoger.
    if (estado == AppLifecycleState.resumed && mounted) {
      atenderArchivoEntrante(context, ref);
    }
  }

  int _indice = 0;

  static const _iconos = [
    'venta_rapida', // Ventana 1
    'panel_venta', // Ventana 2
    'producto', // Ventana 3
    'reportes', // Ventana 4
    'configuracion', // Ventana 5
  ];

  static const _pantallas = [
    VentaRapidaScreen(),
    PanelVentaScreen(),
    ProductoCrudScreen(),
    ReportesScreen(),
    ConfiguracionScreen(),
  ];

  Widget _stack() {
    // El contenido llega hasta el borde y el velo lo desvanece al pasar por
    // debajo. Con `SafeArea` en cambio se empuja todo hacia abajo y queda un
    // borde muerto, y una lista que sube se corta en seco.
    //
    // Cada pantalla reserva `bentoInsetSuperior` donde le toca: como padding de
    // su scroll —así los elementos suben y se desvanecen— o como espacio fijo
    // cuando lo de arriba no scrollea.
    return AtajosDeVentana(
      indice: _indice,
      cantidad: _pantallas.length,
      onCambio: (i) => setState(() => _indice = i),
      child: NavegacionPorGesto(
        indice: _indice,
        cantidad: _pantallas.length,
        onCambio: (i) => setState(() => _indice = i),
        child: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(
                index: _indice,
                children: [
                  for (var i = 0; i < _pantallas.length; i++)
                    ExcludeFocus(excluding: i != _indice, child: _pantallas[i]),
                ],
              ),
            ),
            const Positioned(top: 0, left: 0, right: 0, child: BentoVeloSuperior()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Se observa el sync aunque esta pantalla no lo muestre: el notifier no
    // existe hasta que alguien lo mira, y si solo lo mirara Configuración, la
    // sincronización no arrancaría sola hasta entrar ahí. Encenderla es una
    // decisión que se recuerda entre arranques, y tiene que valer desde que se
    // abre la app.
    ref.watch(syncNotifierProvider);

    // El rail lateral aparece desde tablet. Antes esto era un `>= 720` suelto,
    // el ÚNICO punto de toda la app que reaccionaba al tamaño; ahora sale del
    // mismo sistema de cortes que usan las cinco pantallas (decisión 0026).
    final anchoAmplio = !BentoAncho.de(context).esCompacto;

    // La navegacion es una banda de la BANDEJA, no un NavigationRail de
    // Material: ese traia su propio fondo (`surface`, o sea el color de pozo)
    // y su propia pildora de seleccion, asi que se leia como un pozo altisimo
    // pegado al costado en vez de parte del marco (DESIGN.md, regla 8).
    if (anchoAmplio) {
      return Scaffold(
        body: Row(
          children: [
            _BandaNavegacion(
              indice: _indice,
              iconos: _iconos,
              onSeleccion: (i) => setState(() => _indice = i),
              vertical: true,
            ),
            Expanded(child: _stack()),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // Las pantallas dejan de ver el inset INFERIOR: aquí abajo está la
          // banda de navegación, y es ella la que toca el borde de la pantalla.
          //
          // Sin esto se reserva dos veces. Una barra inferior de pantalla —el
          // buscador de Venta Rápida, el de Inventario— también lleva su
          // `SafeArea`, y como es hermana y no descendiente de la banda, las dos
          // ven el mismo inset y las dos lo reservan: queda una franja muerta
          // entre el buscador y las pestañas.
          //
          // En Android 10 no se veía porque ahí la barra de navegación del
          // sistema vive fuera de la app y el inset es 0. Apareció en el
          // teléfono de la soda —Android 15, donde `edge-to-edge` es
          // obligatorio y el inset es real—, que es justo para lo que sirve
          // tener un aparato con una base moderna.
          Expanded(
            child: MediaQuery.removePadding(context: context, removeBottom: true, child: _stack()),
          ),
          _BandaNavegacion(
            indice: _indice,
            iconos: _iconos,
            onSeleccion: (i) => setState(() => _indice = i),
            vertical: false,
          ),
        ],
      ),
    );
  }
}

/// Banda de navegacion tallada en la bandeja.
///
/// La seleccion se expresa en la gramatica del propio material: el
/// compartimento activo es el que esta HUNDIDO (un pozo, con el icono en oro
/// de laca), y los inactivos quedan a ras del marco. Es la alternativa a la
/// pildora generica de Material, que no dice nada sobre este mundo.
class _BandaNavegacion extends StatelessWidget {
  const _BandaNavegacion({
    required this.indice,
    required this.iconos,
    required this.onSeleccion,
    required this.vertical,
  });

  final int indice;
  final List<String> iconos;
  final ValueChanged<int> onSeleccion;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);

    final destinos = [
      for (var i = 0; i < iconos.length; i++)
        Padding(
          padding: const EdgeInsets.all(BentoSpacing.unidad / 2),
          child: _Destino(
            // Key explicita: los destinos son solo iconos, sin texto ni
            // tooltip, asi que sin esto el harness del MCP no puede navegar
            // entre ventanas (find.text/byTooltip no tienen a que agarrarse).
            key: ValueKey('nav_${iconos[i]}'),
            nombre: iconos[i],
            seleccionado: i == indice,
            onTap: () => onSeleccion(i),
          ),
        ),
    ];

    return ColoredBox(
      color: laca.bandeja,
      child: Padding(
        padding: const EdgeInsets.all(BentoSpacing.unidad),
        child: vertical
            ? Column(mainAxisSize: MainAxisSize.min, children: destinos)
            : SafeArea(
                top: false,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: destinos),
              ),
      ),
    );
  }
}

class _Destino extends StatelessWidget {
  const _Destino({
    super.key,
    required this.nombre,
    required this.seleccionado,
    required this.onTap,
  });

  final String nombre;
  final bool seleccionado;
  final VoidCallback onTap;

  /// Cómo se llama cada ventana en voz alta.
  ///
  /// La banda de navegación son cinco iconos sin una sola palabra: quien no
  /// reconozca el dibujo no tiene dónde agarrarse, y para un lector de pantalla
  /// eran cinco botones sin nombre. El tooltip lo resuelve para las dos cosas —
  /// mantener presionado lo dice, y `Tooltip` ya publica su texto en el árbol
  /// de semántica.
  static const _etiquetas = {
    'venta_rapida': 'Venta rápida',
    'panel_venta': 'Panel de venta',
    'producto': 'Catálogo',
    'reportes': 'Reportes',
    'configuracion': 'Configuración',
  };

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final acento = Theme.of(context).colorScheme.primary;
    final etiqueta = _etiquetas[nombre] ?? nombre;

    final icono = Center(
      child: BentoIcon(nombre, color: seleccionado ? acento : laca.textoAtenuadoEnBandeja),
    );

    return Tooltip(
      message: etiqueta,
      child: SizedBox(
        width: bentoObjetivoTactilMin,
        height: bentoObjetivoTactilMin,
        child: seleccionado
            ? BentoPozo(onTap: onTap, seleccionado: true, padding: EdgeInsets.zero, child: icono)
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(BentoRadius.pozo),
                  child: icono,
                ),
              ),
      ),
    );
  }
}
