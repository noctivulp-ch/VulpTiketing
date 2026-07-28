import 'package:flutter/material.dart';

import '../configuracion/ui/configuracion_screen.dart';
import '../producto/ui/producto_crud_screen.dart';
import '../reportes/ui/reportes_screen.dart';
import '../venta/ui/panel_venta_screen.dart';
import '../venta/ui/venta_rapida_screen.dart';

/// Shell de navegacion (decision de pantallas: docs/pantallas/flujo-descripcion.md
/// #dashboard-shell-de-navegacion). Rail lateral en pantalla ancha, pestanas
/// inferiores en angosta — SOLO iconos, sin texto (lenguaje no-textual,
/// docs/pantallas/prototipos-ascii.md#principios-aplicados-en-esta-pasada).
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _indice = 0;

  static const _iconos = [
    Icons.point_of_sale, // Ventana 1 — Venta Rapida
    Icons.shopping_basket, // Ventana 2 — Panel de Venta
    Icons.inventory_2, // Ventana 3 — CRUD de Producto
    Icons.bar_chart, // Ventana 4 — Reportes
    Icons.settings, // Ventana 5 — Configuracion
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
                for (final icono in _iconos)
                  NavigationRailDestination(icon: Icon(icono), label: const Text('')),
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
          for (final icono in _iconos)
            NavigationDestination(icon: Icon(icono), label: ''),
        ],
      ),
    );
  }
}
