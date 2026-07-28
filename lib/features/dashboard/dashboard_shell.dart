import 'package:flutter/material.dart';

import '../../core/theme/bento_icon.dart';
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

  @override
  Widget build(BuildContext context) {
    final anchoAmplio = MediaQuery.sizeOf(context).width >= 720;

    if (anchoAmplio) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _indice,
              onDestinationSelected: (i) => setState(() => _indice = i),
              labelType: NavigationRailLabelType.none,
              destinations: [
                for (final nombre in _iconos)
                  NavigationRailDestination(
                    icon: BentoIcon(nombre),
                    selectedIcon: BentoIcon(nombre, activo: true),
                    label: const Text(''),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _pantallas[_indice]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _pantallas[_indice],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: [
          for (final nombre in _iconos)
            NavigationDestination(
              icon: BentoIcon(nombre),
              selectedIcon: BentoIcon(nombre, activo: true),
              label: '',
            ),
        ],
      ),
    );
  }
}
