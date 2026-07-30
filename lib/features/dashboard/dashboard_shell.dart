import 'package:flutter/material.dart';

import '../../core/theme/bento_bandeja.dart';
import '../../core/theme/bento_icon.dart';
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
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
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
    return IndexedStack(
      index: _indice,
      children: [
        for (var i = 0; i < _pantallas.length; i++)
          ExcludeFocus(excluding: i != _indice, child: _pantallas[i]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchoAmplio = MediaQuery.sizeOf(context).width >= 720;

    // La navegacion es una banda de la BANDEJA, no un NavigationRail de
    // Material: ese traia su propio fondo (`surface`, o sea el color de pozo)
    // y su propia pildora de seleccion, asi que se leia como un pozo altisimo
    // pegado al costado en vez de parte del marco (DESIGN.md, regla 7).
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
          Expanded(child: _stack()),
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

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final acento = Theme.of(context).colorScheme.primary;

    final icono = Center(
      child: BentoIcon(
        nombre,
        color: seleccionado ? acento : laca.textoAtenuadoEnBandeja,
      ),
    );

    if (!seleccionado) {
      return SizedBox(
        width: bentoObjetivoTactilMin,
        height: bentoObjetivoTactilMin,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(BentoRadius.pozo),
            child: icono,
          ),
        ),
      );
    }

    return SizedBox(
      width: bentoObjetivoTactilMin,
      height: bentoObjetivoTactilMin,
      child: BentoPozo(
        onTap: onTap,
        seleccionado: true,
        padding: EdgeInsets.zero,
        child: icono,
      ),
    );
  }
}
